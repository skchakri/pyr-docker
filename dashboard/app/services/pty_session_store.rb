class PtySessionStore
  BUFFER_SIZE = 100_000 # bytes of scrollback to replay on reattach

  @sessions = {}
  @mutex    = Mutex.new

  class << self
    def get(key)
      @mutex.synchronize { @sessions[key] }
    end

    def create(key, reader:, writer:, pid:, read_thread:)
      @mutex.synchronize do
        @sessions[key] = {
          reader:      reader,
          writer:      writer,
          pid:         pid,
          read_thread: read_thread,
          buffer:      +"",
          created_at:  Time.now
        }
      end
    end

    def delete(key)
      @mutex.synchronize { @sessions.delete(key) }
    end

    def exists?(key)
      @mutex.synchronize { @sessions.key?(key) }
    end

    def append_buffer(key, data)
      @mutex.synchronize do
        s = @sessions[key]
        return unless s
        s[:buffer] << data
        excess = s[:buffer].bytesize - BUFFER_SIZE
        s[:buffer] = s[:buffer].byteslice(excess, s[:buffer].bytesize) if excess > 0
      end
    end

    def buffer(key)
      @mutex.synchronize { @sessions.dig(key, :buffer)&.dup || "" }
    end

    def write(key, data)
      @mutex.synchronize { @sessions.dig(key, :writer) }&.write(data)
    rescue Errno::EIO, IOError
      nil
    end

    def resize(key, cols, rows)
      @mutex.synchronize { @sessions.dig(key, :writer) }&.winsize = [rows, cols]
    rescue Errno::EIO, IOError, ArgumentError
      nil
    end

    def all_keys
      @mutex.synchronize { @sessions.keys.dup }
    end

    def cleanup_dead
      @mutex.synchronize do
        @sessions.each do |key, s|
          begin
            Process.kill(0, s[:pid])
          rescue Errno::ESRCH, Errno::EPERM
            @sessions.delete(key)
          end
        end
      end
    end
  end
end
