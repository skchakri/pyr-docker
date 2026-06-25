require "yaml"
require "shellwords"
require "open3"
require "socket"
require "uri"

class DockerService
  COMPOSE_DIR = Rails.root.join("..").to_s
  COMPOSE_FILE = File.join(COMPOSE_DIR, "docker-compose.yml")
  EXTRA_CLIENTS_FILE = Rails.root.join("config", "extra_clients.yml").to_s

  # Overall wall-clock budget for one concurrent port-probe sweep. Each probe is
  # a bare TCP connect with a 0.4s timeout, run in its own thread; this caps the
  # total wait so a sweep stays well under the controller's response budget no
  # matter how many clients are running.
  PORT_PROBE_BUDGET = 1.0

  class << self
    def clients
      defs = client_definitions
      statuses = container_statuses
      branches = git_branches(defs)
      probes = port_probes(defs, statuses)

      defs.map do |name, config|
        if config[:type] == "process"
          state, status = process_status(config[:port])
          serving = (state == "running")
        else
          container = statuses[config[:container_name]]
          state  = container&.dig(:state)  || "not_found"
          status = container&.dig(:status) || "Not created"
          # "Up" only means the container exists. For proxied apps (ownsites' web
          # container can be up while its nginx on :8088 is down) that produces a
          # misleading green dot, so probe the port the client actually serves on.
          # The probe runs in the cached, concurrent port_probes sweep below.
          serving = state == "running" ? probes.fetch(name, false) : false
        end

        config.merge(state: state, status: status, serving: serving, branch: branches[name] || "")
      end
    end

    def start(name)
      config = client_definitions[name]
      return { success: false, output: "Unknown client" } unless config

      case config[:type]
      when "docker_compose"
        run_compose_in(config[:compose_dir], "up", "-d", *compose_target_args(config))
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
        run_compose_in(config[:compose_dir], "stop", *compose_target_args(config))
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
        # Ensure the full stack is up first (creates/starts any missing services such
        # as the nginx proxy that fronts the Access URL), then restart for a clean boot.
        if config[:compose_all]
          run_compose_in(config[:compose_dir], "up", "-d")
          run_compose_in(config[:compose_dir], "restart")
        else
          run_compose_in(config[:compose_dir], "restart", config[:compose_service])
        end
      when "process"
        stop(name)
        sleep 1
        start(name)
      else
        run_compose("restart", name)
      end
    end

    def restart_vite(name)
      config = client_definitions[name]
      return { success: false, output: "Unknown client" } unless config

      service = config[:vite_service]
      return { success: false, output: "No vite service registered for #{name}" } if service.blank?
      return { success: false, output: "Vite restart only supported for docker_compose clients" } unless config[:type] == "docker_compose"

      run_compose_in(config[:compose_dir], "restart", service)
    end

    def logs(name, lines: 200)
      config = client_definitions[name]
      return "" unless config

      case config[:type]
      when "docker_compose"
        stdout, stderr, _st = Open3.capture3(
          "docker", "compose", "logs", "--tail=#{lines}", "--no-color", *compose_target_args(config),
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

    # Service arguments for `docker compose` lifecycle commands. When a client sets
    # `compose_all: true`, we operate on the whole compose project (no service filter)
    # so multi-service apps bring up every service — including front proxies like the
    # ownsites nginx container on :8088 that the Access button targets. Otherwise we
    # scope to the single declared service.
    def compose_target_args(config)
      return [] if config[:compose_all]

      [ config[:compose_service] ].compact
    end

    def process_status(port)
      out, _st = Open3.capture2("bash", "-c", "lsof -ti :#{port} 2>/dev/null")
      if out.strip.present?
        [ "running", "Up (pid #{out.strip.split("\n").first})" ]
      else
        [ "exited", "Not running" ]
      end
    end

    # Is the client actually reachable on the port it serves? For clients with an
    # explicit access_url (e.g. ownsites' nginx on :8088) we probe that port;
    # otherwise the declared PORT. A bare TCP connect distinguishes "serving" from
    # "container up but proxy/app dead" without coupling to any health endpoint.
    def access_responding?(config)
      port = probe_port(config)
      return true if port.nil?

      port_open?("127.0.0.1", port)
    end

    def probe_port(config)
      if config[:access_url].present?
        URI.parse(config[:access_url]).port || config[:port]
      else
        config[:port]
      end
    rescue URI::InvalidURIError
      config[:port]
    end

    def port_open?(host, port, timeout = 0.4)
      return false unless port.to_i.positive?

      Socket.tcp(host, port.to_i, connect_timeout: timeout, &:close)
      true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
           Errno::ENETUNREACH, Errno::EADDRNOTAVAIL, SocketError, IOError
      false
    end

    # Cached briefly: branches change rarely, but resolving them forks a `git`
    # process per client on every status poll. Rails.cache (MemoryStore in dev)
    # collapses that to one sweep per few seconds, without the cross-request
    # staleness that made class-level memoization of definitions a bug.
    def git_branches(defs)
      Rails.cache.fetch("dashboard:git_branches", expires_in: 3.seconds) do
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

    # Cached briefly (see git_branches): a single `docker ps` per few seconds is
    # plenty for a status board and keeps fast poll intervals from shelling out
    # on every tick. Status lags an action by at most the TTL.
    def container_statuses
      Rails.cache.fetch("dashboard:container_statuses", expires_in: 3.seconds) do
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
    end

    # Cached, concurrent port-probe sweep (mirrors container_statuses/git_branches).
    # For every running, non-`process` client we open a bare TCP connect to the
    # port it actually serves on. Done inline + sequentially in #clients this cost
    # ~0.4s per running client, so a dozen clients blocked the Puma thread for
    # several seconds on every 8s poll. Here each probe runs in its own thread and
    # the whole sweep is bounded by a single monotonic deadline, so a cold sweep
    # costs ~one connect-timeout instead of N of them; the 3s TTL means warm polls
    # return instantly. Returns a hash keyed per client name => "is it serving".
    def port_probes(defs, statuses)
      Rails.cache.fetch("dashboard:port_probes", expires_in: 3.seconds) do
        threads = defs.filter_map do |name, config|
          next if config[:type] == "process"
          next unless statuses[config[:container_name]]&.dig(:state) == "running"

          [ name, Thread.new { probe_serving(config) } ]
        end

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PORT_PROBE_BUDGET
        threads.each_with_object({}) do |(name, thread), results|
          remaining = [ deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0 ].max
          # A probe that outlives the budget is recorded as "not serving" rather
          # than stalling the sweep; its thread self-terminates within one
          # connect-timeout, so there's nothing to kill.
          results[name] = thread.join(remaining) ? thread.value : false
        end
      rescue => e
        Rails.logger.error("Port probe sweep failed: #{e.message}")
        {}
      end
    end

    # Probe one client in a worker thread. access_responding? is already fully
    # guarded (probe_port/port_open? rescue their own errors), but we belt-and-
    # suspenders here so an unexpected failure resolves to "not serving" instead
    # of tearing down the whole sweep when join later calls thread.value.
    def probe_serving(config)
      access_responding?(config)
    rescue => e
      Rails.logger.debug("Port probe failed for #{config[:name]}: #{e.message}")
      false
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
