require "yaml"
require "shellwords"
require "open3"

class DockerService
  COMPOSE_DIR = Rails.root.join("..").to_s
  COMPOSE_FILE = File.join(COMPOSE_DIR, "docker-compose.yml")

  class << self
    def clients
      defs = client_definitions
      statuses = container_statuses

      defs.map do |name, config|
        container = statuses[config[:container_name]]
        config.merge(
          state: container&.dig(:state) || "not_found",
          status: container&.dig(:status) || "Not created"
        )
      end
    end

    def start(name)
      run_compose("up", "-d", name)
    end

    def stop(name)
      run_compose("stop", name)
    end

    def restart(name)
      run_compose("restart", name)
    end

    def logs(name, lines: 200)
      stdout, stderr, _status = Open3.capture3(
        "docker", "compose", "logs", "--tail=#{lines}", "--no-color", name,
        chdir: COMPOSE_DIR
      )
      (stdout + stderr).strip
    end

    def valid_client?(name)
      client_definitions.key?(name)
    end

    def client_host_path(name)
      client_definitions.dig(name, :host_path)
    end

    def container_name(name)
      client_definitions.dig(name, :container_name) || "pyr-#{name}"
    end

    private

    def client_definitions
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
          redis_url: env["REDIS_URL"] || ""
        }
      end

      clients
    end

    def container_statuses
      output, _status = Open3.capture2(
        "docker", "ps", "-a",
        "--filter", "name=pyr-",
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
  end
end
