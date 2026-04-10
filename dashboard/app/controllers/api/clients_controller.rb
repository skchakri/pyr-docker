require "net/http"

module Api
  class ClientsController < ApplicationController
    skip_forgery_protection

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
  end
end
