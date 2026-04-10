require "pty"

class TerminalChannel < ApplicationCable::Channel
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

    read_thread = Thread.new do
      loop do
        data = reader.readpartial(4096)
        PtySessionStore.append_buffer(@session_key, data)
        ActionCable.server.broadcast(@stream_id, { output: data })
      rescue EOFError, Errno::EIO, IOError
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
