require "pty"

class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @client = params[:client]
    @type = params[:type]
    @cols = (params[:cols] || 120).to_i
    @rows = (params[:rows] || 30).to_i

    unless DockerService.valid_client?(@client)
      transmit({ error: "Unknown client: #{@client}" })
      reject
      return
    end

    @stream_id = "terminal_#{@client}_#{@type}_#{object_id}"
    stream_from @stream_id

    spawn_terminal
  end

  def receive(data)
    if data["type"] == "resize"
      resize(data["cols"].to_i, data["rows"].to_i)
    elsif data["input"]
      @writer&.write(data["input"])
    end
  end

  def unsubscribed
    cleanup
  end

  private

  def spawn_terminal
    container = DockerService.container_name(@client)
    host_path = DockerService.client_host_path(@client)

    cmd = case @type
    when "console"
      "docker exec -it #{Shellwords.escape(container)} bundle exec rails console"
    when "bash"
      "docker exec -it #{Shellwords.escape(container)} bash"
    when "terminal"
      "cd #{Shellwords.escape(host_path)} && PS1='pyr:#{@client} \\w\\$ ' exec bash"
    when "logs"
      "cd #{Shellwords.escape(DockerService::COMPOSE_DIR)} && docker compose logs -f --tail=100 #{Shellwords.escape(@client)}"
    else
      transmit_output("\r\n\e[31mUnknown terminal type: #{@type}\e[0m\r\n")
      reject
      return
    end

    @reader, @writer, @pid = PTY.spawn(cmd)

    # Set initial terminal size
    resize(@cols, @rows)

    @read_thread = Thread.new do
      loop do
        data = @reader.readpartial(4096)
        transmit_output(data)
      rescue EOFError, Errno::EIO, IOError
        transmit_output("\r\n\e[90m[Process exited]\e[0m\r\n")
        break
      rescue => e
        transmit_output("\r\n\e[31m[Error: #{e.message}]\e[0m\r\n")
        break
      end
    end
  rescue => e
    transmit_output("\r\n\e[31mFailed to spawn terminal: #{e.message}\e[0m\r\n")
  end

  def resize(cols, rows)
    return unless @writer && cols > 0 && rows > 0
    @writer.winsize = [ rows, cols ]
  rescue Errno::EIO, IOError
    # Process already exited
  end

  def transmit_output(data)
    ActionCable.server.broadcast(@stream_id, { output: data })
  end

  def cleanup
    @read_thread&.kill
    if @pid
      Process.kill("TERM", @pid) rescue nil
      Process.wait(@pid) rescue nil
    end
    @reader&.close rescue nil
    @writer&.close rescue nil
  end
end
