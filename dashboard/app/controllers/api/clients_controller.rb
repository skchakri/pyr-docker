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
  end
end
