require "json"

# Redis-backed store of user prompts typed into Claude terminals, keyed
# per-client. Entries are JSON blobs with {text, at, source} pushed onto a
# Redis list via LPUSH and capped by LTRIM so the list never grows unbounded.
#
# Storage layout (Redis db 9):
#   pyr:claude_prompts:<client>     list of JSON strings, newest first
class ClaudePromptHistoryService
  LIST_KEY_PREFIX = "pyr:claude_prompts:".freeze
  MAX_ENTRIES     = 500
  MAX_TEXT_BYTES  = 16 * 1024 # 16 KB

  class << self
    def add(client:, text:, source: "keyboard")
      return false unless valid_client?(client)

      text = text.to_s.strip
      return false if text.empty?
      text = text.byteslice(0, MAX_TEXT_BYTES) if text.bytesize > MAX_TEXT_BYTES

      payload = {
        text:   text,
        at:     Time.now.to_i,
        source: source.to_s
      }.to_json

      key = list_key(client)
      REDIS.multi do |tx|
        tx.lpush(key, payload)
        tx.ltrim(key, 0, MAX_ENTRIES - 1)
      end
      true
    rescue Redis::BaseError => e
      Rails.logger.warn("[ClaudePromptHistory] add failed: #{e.message}")
      false
    end

    def list(client:, limit: 100, offset: 0)
      return [] unless valid_client?(client)

      limit  = limit.to_i.clamp(1, MAX_ENTRIES)
      offset = offset.to_i.clamp(0, MAX_ENTRIES - 1)

      entries = REDIS.lrange(list_key(client), offset, offset + limit - 1)
      entries.map { |raw| parse(raw) }.compact
    rescue Redis::BaseError => e
      Rails.logger.warn("[ClaudePromptHistory] list failed: #{e.message}")
      []
    end

    def clear(client:)
      return false unless valid_client?(client)
      REDIS.del(list_key(client))
      true
    rescue Redis::BaseError => e
      Rails.logger.warn("[ClaudePromptHistory] clear failed: #{e.message}")
      false
    end

    def count(client:)
      return 0 unless valid_client?(client)
      REDIS.llen(list_key(client))
    rescue Redis::BaseError
      0
    end

    private

    def list_key(client)
      "#{LIST_KEY_PREFIX}#{client}"
    end

    def valid_client?(client)
      DockerService.valid_client?(client.to_s)
    end

    def parse(raw)
      JSON.parse(raw).slice("text", "at", "source")
    rescue JSON::ParserError
      nil
    end
  end
end
