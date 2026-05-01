module Api
  class ClaudeController < ApplicationController
    skip_forgery_protection

    def usage
      render json: ClaudeUsageService.fetch(force: params[:force] == "1")
    end

    def history_index
      client = params[:client].to_s
      unless DockerService.valid_client?(client)
        return render json: { error: "Unknown client" }, status: :not_found
      end

      limit = (params[:limit] || 100).to_i
      render json: {
        client:  client,
        count:   ClaudePromptHistoryService.count(client: client),
        entries: ClaudePromptHistoryService.list(client: client, limit: limit)
      }
    end

    def history_create
      client = params[:client].to_s
      text   = params[:text].to_s
      source = params[:source].presence || "keyboard"

      unless DockerService.valid_client?(client)
        return render json: { error: "Unknown client" }, status: :not_found
      end
      if text.strip.empty?
        return render json: { error: "empty" }, status: :unprocessable_entity
      end

      ok = ClaudePromptHistoryService.add(client: client, text: text, source: source)
      render json: { success: ok }
    end

    def history_destroy
      client = params[:client].to_s
      unless DockerService.valid_client?(client)
        return render json: { error: "Unknown client" }, status: :not_found
      end
      ClaudePromptHistoryService.clear(client: client)
      render json: { success: true }
    end
  end
end
