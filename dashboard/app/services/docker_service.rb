require "yaml"
require "shellwords"
require "open3"

class DockerService
  COMPOSE_DIR = Rails.root.join("..").to_s
  COMPOSE_FILE = File.join(COMPOSE_DIR, "docker-compose.yml")
  EXTRA_CLIENTS_FILE = Rails.root.join("config", "extra_clients.yml").to_s

  class << self
    def clients
      defs = client_definitions
      statuses = container_statuses
      branches = git_branches(defs)

      defs.map do |name, config|
        if config[:type] == "process"
          state, status = process_status(config[:port])
        else
          container = statuses[config[:container_name]]
          state  = container&.dig(:state)  || "not_found"
          status = container&.dig(:status) || "Not created"
        end

        config.merge(state: state, status: status, branch: branches[name] || "")
      end
    end

    def start(name)
      config = client_definitions[name]
      return { success: false, output: "Unknown client" } unless config

      case config[:type]
      when "docker_compose"
        run_compose_in(config[:compose_dir], "up", "-d", config[:compose_service])
      when "process"
        pid_file = "/tmp/dashboard_#{name}.pid"
        cmd = "cd #{Shellwords.escape(config[:host_path])} && #{config[:start_cmd]} & echo $! > #{pid_file}"
        stdout, stderr, st = Open3.capture3("bash", "-c", cmd)
        { success: st.success?, output: (stdout + stderr).strip }
      else
        run_compose("up", "-d", name)
      end
    end

    def stop(name)
      config = client_definitions[name]
      return { success: false, output: "Unknown client" } unless config

      case config[:type]
      when "docker_compose"
        run_compose_in(config[:compose_dir], "stop", config[:compose_service])
      when "process"
        pid_file = "/tmp/dashboard_#{name}.pid"
        if File.exist?(pid_file)
          pid = File.read(pid_file).strip
          stdout, stderr, st = Open3.capture3("bash", "-c", "kill #{pid} 2>/dev/null; rm -f #{pid_file}")
          { success: st.success?, output: (stdout + stderr).strip }
        else
          # Try killing by port
          stdout, stderr, st = Open3.capture3("bash", "-c", "fuser -k #{config[:port]}/tcp 2>/dev/null")
          { success: true, output: "Killed process on port #{config[:port]}" }
        end
      else
        run_compose("stop", name)
      end
    end

    def restart(name)
      config = client_definitions[name]
      return { success: false, output: "Unknown client" } unless config

      case config[:type]
      when "docker_compose"
        run_compose_in(config[:compose_dir], "restart", config[:compose_service])
      when "process"
        stop(name)
        sleep 1
        start(name)
      else
        run_compose("restart", name)
      end
    end

    def logs(name, lines: 200)
      config = client_definitions[name]
      return "" unless config

      case config[:type]
      when "docker_compose"
        stdout, stderr, _st = Open3.capture3(
          "docker", "compose", "logs", "--tail=#{lines}", "--no-color", config[:compose_service],
          chdir: config[:compose_dir]
        )
        (stdout + stderr).strip
      when "process"
        log_file = File.join(config[:host_path], "log", "development.log")
        if File.exist?(log_file)
          `tail -n #{lines} #{Shellwords.escape(log_file)}`
        else
          "No log file found at #{log_file}"
        end
      else
        stdout, stderr, _st = Open3.capture3(
          "docker", "compose", "logs", "--tail=#{lines}", "--no-color", name,
          chdir: COMPOSE_DIR
        )
        (stdout + stderr).strip
      end
    end

    def valid_client?(name)
      client_definitions.key?(name)
    end

    def client_host_path(name)
      client_definitions.dig(name, :host_path)
    end

    def client_type(name)
      client_definitions.dig(name, :type) || "pyr"
    end

    def container_name(name)
      config = client_definitions[name]
      return config[:container_name] if config && config[:container_name].present?
      "pyr-#{name}"
    end

    def client_port(name)
      client_definitions.dig(name, :port) || "3000"
    end

    def compose_dir_for(name)
      client_definitions.dig(name, :compose_dir) || COMPOSE_DIR
    end

    def compose_service_for(name)
      client_definitions.dig(name, :compose_service) || name
    end

    private

    def process_status(port)
      out, _st = Open3.capture2("bash", "-c", "lsof -ti :#{port} 2>/dev/null")
      if out.strip.present?
        [ "running", "Up (pid #{out.strip.split("\n").first})" ]
      else
        [ "exited", "Not running" ]
      end
    end

    def git_branches(defs)
      branches = {}
      defs.each do |name, config|
        path = config[:host_path]
        next unless path && File.directory?(path)

        branch, _status = Open3.capture2("git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD")
        branches[name] = branch.strip
      rescue => e
        Rails.logger.debug("Git branch failed for #{name}: #{e.message}")
      end
      branches
    end

    def client_definitions
      pyr_client_definitions.merge(extra_client_definitions)
    end

    def pyr_client_definitions
      raw = File.read(COMPOSE_FILE)
      compose = YAML.safe_load(raw, aliases: true)
      clients = {}

      (compose["services"] || {}).each do |name, service|
        env = service["environment"] || {}
        port = env["PORT"] || "3000"
        container = service["container_name"] || "pyr-#{name}"

        host_path = nil
        (service["volumes"] || []).each do |vol|
          if vol.is_a?(String) && vol.include?("/platform/")
            host_path = vol.split(":").first
            break
          end
        end

        clients[name] = {
          name: name,
          container_name: container,
          port: port,
          host_path: host_path || "/home/kalyan/platform/clients/#{name}/pyr",
          database: env["DATABASE_NAME"] || "",
          redis_url: env["REDIS_URL"] || "",
          type: "pyr"
        }
      end

      clients
    end

    def extra_client_definitions
      return {} unless File.exist?(EXTRA_CLIENTS_FILE)

      raw = YAML.safe_load(File.read(EXTRA_CLIENTS_FILE)) || {}
      raw.transform_values { |v| v.transform_keys(&:to_sym) }
    rescue => e
      Rails.logger.error("Failed to load extra_clients.yml: #{e.message}")
      {}
    end

    def container_statuses
      output, _status = Open3.capture2(
        "docker", "ps", "-a",
        "--format", '{{.Names}}\t{{.Status}}\t{{.State}}'
      )

      containers = {}
      output.strip.split("\n").each do |line|
        next if line.empty?
        parts = line.split("\t")
        containers[parts[0]] = { status: parts[1], state: parts[2] }
      end
      containers
    rescue => e
      Rails.logger.error("Docker status failed: #{e.message}")
      {}
    end

    def run_compose(*args)
      stdout, stderr, status = Open3.capture3(
        "docker", "compose", *args,
        chdir: COMPOSE_DIR
      )
      { success: status.success?, output: (stdout + stderr).strip }
    end

    def run_compose_in(dir, *args)
      stdout, stderr, status = Open3.capture3(
        "docker", "compose", *args,
        chdir: dir
      )
      { success: status.success?, output: (stdout + stderr).strip }
    end
  end
end
