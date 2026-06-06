require "pty"

class TerminalChannel < ApplicationCable::Channel
  # Whitelists for Claude CLI flag values — anything not listed is dropped
  # before we interpolate into a shell command.
  CLAUDE_MODELS  = %w[default sonnet opus haiku claude-sonnet-4-6 claude-opus-4-6 claude-haiku-4-5].freeze
  CLAUDE_EFFORTS = %w[low medium high max].freeze

  def subscribed
    @client      = params[:client]
    @type        = params[:type]
    @session_key = "#{@client}__#{@type}"
    @stream_id   = "pty_session_#{@session_key}"

    unless DockerService.valid_client?(@client)
      transmit({ error: "Unknown client: #{@client}" })
      reject
      return
    end

    stream_from @stream_id

    if PtySessionStore.exists?(@session_key)
      # Reattach — replay buffered output then signal live
      buf = PtySessionStore.buffer(@session_key)
      transmit({ output: buf }) unless buf.empty?
      transmit({ output: "\r\n\e[90m[Reattached to running session]\e[0m\r\n", reattached: true })
    else
      spawn_session
    end
  end

  def receive(data)
    if data["type"] == "resize"
      PtySessionStore.resize(@session_key, data["cols"].to_i, data["rows"].to_i)
    elsif data["type"] == "kill"
      kill_session
    elsif data["input"]
      PtySessionStore.write(@session_key, data["input"])
    end
  end

  def unsubscribed
    # Leave PTY running — do NOT kill it
  end

  private

  # Split raw PTY bytes at a valid UTF-8 boundary. PTY chunks routinely cut
  # multi-byte sequences (em-dashes / box-drawing start with 0xE2) in half,
  # which makes ActionCable's JSON encoder raise UndefinedConversionError
  # and kill the session. Returns [complete_utf8_to_broadcast, leftover_bytes].
  def split_utf8_safe(bytes)
    return [ "", "" ] if bytes.empty?
    bin = bytes.dup.force_encoding(Encoding::ASCII_8BIT)
    cut = bin.bytesize
    i = cut - 1
    steps = 0
    while i >= 0 && steps < 4
      b = bin.getbyte(i)
      if b < 0x80
        break
      elsif (b & 0xC0) == 0x80
        i -= 1
        steps += 1
      else
        seq_len = if    (b & 0xE0) == 0xC0 then 2
        elsif (b & 0xF0) == 0xE0 then 3
        elsif (b & 0xF8) == 0xF0 then 4
        else 1
        end
        cut = i if (bin.bytesize - i) < seq_len
        break
      end
    end
    complete = bin.byteslice(0, cut).force_encoding(Encoding::UTF_8).scrub
    leftover = bin.byteslice(cut, bin.bytesize - cut) || ""
    leftover.force_encoding(Encoding::ASCII_8BIT)
    [ complete, leftover ]
  end

  # Build "--model X --effort Y" from subscribe params, after whitelisting.
  # "default" (or anything unrecognized) means: don't pass that flag.
  def claude_flags
    parts = []
    model = params[:model].to_s
    if CLAUDE_MODELS.include?(model) && model != "default"
      parts << "--model #{Shellwords.escape(model)}"
    end
    effort = params[:effort].to_s
    if CLAUDE_EFFORTS.include?(effort)
      parts << "--effort #{Shellwords.escape(effort)}"
    end
    parts.empty? ? "" : " #{parts.join(' ')}"
  end

  def kill_session
    session = PtySessionStore.get(@session_key)
    return unless session
    ActionCable.server.broadcast(@stream_id, { output: "\r\n\e[31m[Session killed]\e[0m\r\n", exited: true })
    session[:read_thread]&.kill
    Process.kill("TERM", session[:pid]) rescue nil
    Process.wait(session[:pid]) rescue nil
    session[:reader]&.close rescue nil
    session[:writer]&.close rescue nil
    PtySessionStore.delete(@session_key)
  end

  def spawn_session
    container   = DockerService.container_name(@client)
    host_path   = DockerService.client_host_path(@client)
    type        = DockerService.client_type(@client)
    compose_dir = DockerService.compose_dir_for(@client)
    compose_svc = DockerService.compose_service_for(@client)
    uses_docker = type == "pyr" || type == "docker_compose"

    cmd = case @type
    when "console"
      uses_docker ? "docker exec -it #{Shellwords.escape(container)} bundle exec rails console"
                  : "cd #{Shellwords.escape(host_path)} && bundle exec rails console"
    when "bash"
      uses_docker ? "docker exec -it #{Shellwords.escape(container)} bash"
                  : "cd #{Shellwords.escape(host_path)} && PS1='#{@client} \\w\\$ ' exec bash"
    when "terminal"
      "cd #{Shellwords.escape(host_path)} && PS1='#{@client} \\w\\$ ' exec bash"
    when "claude"
      flags = claude_flags
      "cd #{Shellwords.escape(host_path)} && exec claude#{flags}"
    when "logs"
      if uses_docker
        "cd #{Shellwords.escape(compose_dir)} && docker compose logs -f --tail=100 #{Shellwords.escape(compose_svc)}"
      else
        log_file = File.join(host_path, "log", "development.log")
        "tail -f #{Shellwords.escape(log_file)}"
      end
    when "worker"
      uses_docker ? "docker exec -it #{Shellwords.escape(container)} bundle exec rake resque:work"
                  : "cd #{Shellwords.escape(host_path)} && bundle exec rake resque:work"
    when "scheduler"
      uses_docker ? "docker exec -it #{Shellwords.escape(container)} bundle exec rake resque:scheduler"
                  : "cd #{Shellwords.escape(host_path)} && bundle exec rake resque:scheduler"
    else
      transmit({ error: "Unknown terminal type: #{@type}" })
      reject
      return
    end

    reader, writer, pid = PTY.spawn(cmd)

    # Rate-limit PTY -> WebSocket broadcasts: at most one frame every 20ms
    # (50 fps). High-volume output (claude streaming, big tool dumps) is
    # accumulated in `pending` and flushed once per window. Without this the
    # browser main thread spends all its time in JSON.parse + xterm.write
    # and input events stop firing.
    read_thread = Thread.new do
      pending        = +""
      last_flush     = Time.now
      flush_interval = 0.020   # 20ms ~= 50fps
      max_pending    = 262_144 # 256KB safety cap so memory doesn't balloon

      loop do
        # Sleep up to whatever time is left in the current flush window
        until_next = flush_interval - (Time.now - last_flush)
        until_next = 0 if until_next.negative?

        ready = IO.select([ reader ], nil, nil, until_next)

        if ready
          begin
            pending << reader.read_nonblock(32_768)
          rescue IO::WaitReadable
            # spurious; loop and try again
          end
        end

        elapsed = Time.now - last_flush
        if !pending.empty? && (elapsed >= flush_interval || pending.bytesize >= max_pending)
          out, leftover = split_utf8_safe(pending)
          pending.clear
          pending << leftover unless leftover.empty?
          unless out.empty?
            PtySessionStore.append_buffer(@session_key, out)
            ActionCable.server.broadcast(@stream_id, { output: out })
          end
          last_flush = Time.now
        end
      rescue EOFError, Errno::EIO, IOError
        unless pending.empty?
          final = pending.dup.force_encoding(Encoding::UTF_8).scrub
          PtySessionStore.append_buffer(@session_key, final)
          ActionCable.server.broadcast(@stream_id, { output: final })
        end
        ActionCable.server.broadcast(@stream_id, { output: "\r\n\e[90m[Process exited]\e[0m\r\n", exited: true })
        PtySessionStore.delete(@session_key)
        break
      rescue => e
        ActionCable.server.broadcast(@stream_id, { output: "\r\n\e[31m[Error: #{e.message}]\e[0m\r\n", exited: true })
        PtySessionStore.delete(@session_key)
        break
      end
    end

    PtySessionStore.create(@session_key, reader: reader, writer: writer, pid: pid, read_thread: read_thread)

    cols = (params[:cols] || 120).to_i
    rows = (params[:rows] || 30).to_i
    PtySessionStore.resize(@session_key, cols, rows)
  rescue => e
    transmit({ error: "Failed to spawn terminal: #{e.message}" })
  end
end
