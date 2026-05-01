require "net/http"
require "fileutils"
require "securerandom"

module Api
  class ClientsController < ApplicationController
    skip_forgery_protection

    ALLOWED_PASTE_TYPES = {
      "image/png"  => "png",
      "image/jpeg" => "jpg",
      "image/gif"  => "gif",
      "image/webp" => "webp"
    }.freeze
    MAX_PASTE_BYTES = 10 * 1024 * 1024 # 10 MB

    def index
      render json: DockerService.clients
    end

    def start
      result = DockerService.start(params[:name])
      render json: result
    end

    def stop
      result = DockerService.stop(params[:name])
      render json: result
    end

    def restart
      result = DockerService.restart(params[:name])
      render json: result
    end

    def restart_vite
      result = DockerService.restart_vite(params[:name])
      render json: result
    end

    def logs
      lines = params[:lines] || 200
      render json: { logs: DockerService.logs(params[:name], lines: lines.to_i) }
    end

    def dev_login
      name = params[:name]
      unless DockerService.valid_client?(name)
        return render json: { error: "Unknown client" }, status: :not_found
      end

      port = DockerService.client_port(name)
      uri = URI("http://localhost:#{port}/users/sign_in")

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 10

      # POST with JSON content type to bypass CSRF (verified_request? returns true for JSON)
      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"] = "application/json"
      req.body = { user: { login: "kevin.mcevoy", password: "password1" } }.to_json

      res = http.request(req)

      # Forward session cookies from the client to the browser
      (res.get_fields("set-cookie") || []).each do |cookie_header|
        response.headers["Set-Cookie"] = cookie_header
      end

      redirect_to "http://localhost:#{port}/", allow_other_host: true
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      render plain: "Cannot connect to #{name} on port #{port}: #{e.message}", status: :bad_gateway
    end

    def upload_paste
      unless DockerService.valid_client?(params[:name])
        return render json: { success: false, error: "Unknown client" }, status: :not_found
      end

      file = params[:file]
      unless file.respond_to?(:read) && file.respond_to?(:content_type)
        return render json: { success: false, error: "Missing file" }, status: :bad_request
      end

      ext = ALLOWED_PASTE_TYPES[file.content_type]
      unless ext
        return render json: { success: false, error: "Unsupported type: #{file.content_type}" }, status: :unsupported_media_type
      end

      if file.size > MAX_PASTE_BYTES
        return render json: { success: false, error: "File too large (max #{MAX_PASTE_BYTES / 1_048_576} MB)" }, status: :payload_too_large
      end

      dir = Rails.root.join("tmp", "claude_pastes")
      FileUtils.mkdir_p(dir)
      basename = "#{Time.now.to_i}_#{SecureRandom.hex(4)}.#{ext}"
      path     = dir.join(basename)
      File.binwrite(path, file.read)

      render json: { success: true, path: path.to_s, filename: basename }
    end
  end
end
