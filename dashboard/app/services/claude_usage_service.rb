require "net/http"
require "json"
require "uri"

# Fetches Claude Code /usage-style rate limit stats by reading the
# `anthropic-ratelimit-unified-*` response headers from a minimal Sonnet
# streaming request. Results are cached for 60s in Rails.cache (memory_store
# in dev) to avoid hammering the endpoint on every dashboard poll.
#
# Requires a Claude Code OAuth access token at ~/.claude/.credentials.json.
# The 7d_sonnet bucket is only returned when the request:
#   - targets a Sonnet model
#   - includes the Claude Code system prompt (first line verbatim)
#   - uses streaming
class ClaudeUsageService
  CACHE_KEY = "claude_usage/unified_v1".freeze
  CACHE_TTL = 60 # seconds
  CREDENTIALS_PATH = File.expand_path("~/.claude/.credentials.json").freeze
  API_URL = URI("https://api.anthropic.com/v1/messages").freeze
  SONNET_MODEL = "claude-sonnet-4-5".freeze
  # Verbatim Claude Code system prompt prefix — required for the 7d_sonnet
  # claim to appear. Shorter than the full prompt but starts with the
  # expected identity line, which is what the rate-limit classifier keys on.
  SYSTEM_PROMPT = "You are Claude Code, Anthropic's official CLI for Claude.".freeze

  class << self
    def fetch(force: false)
      Rails.cache.delete(CACHE_KEY) if force
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch_fresh }
    end

    private

    def fetch_fresh
      token = read_token
      return { error: "no_credentials" } unless token

      headers = probe_headers(token)
      return { error: "probe_failed" } unless headers

      build_payload(headers)
    rescue => e
      Rails.logger.warn("[ClaudeUsageService] #{e.class}: #{e.message}")
      { error: e.message }
    end

    def read_token
      return nil unless File.exist?(CREDENTIALS_PATH)
      data = JSON.parse(File.read(CREDENTIALS_PATH))
      data.dig("claudeAiOauth", "accessToken")
    end

    def probe_headers(token)
      http = Net::HTTP.new(API_URL.host, API_URL.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      req = Net::HTTP::Post.new(API_URL.request_uri)
      req["Authorization"]     = "Bearer #{token}"
      req["anthropic-version"] = "2023-06-01"
      req["anthropic-beta"]    = "oauth-2025-04-20"
      req["Content-Type"]      = "application/json"
      req.body = {
        model:      SONNET_MODEL,
        max_tokens: 1,
        stream:     true,
        system:     SYSTEM_PROMPT,
        messages:   [ { role: "user", content: "." } ]
      }.to_json

      # We only need the headers — abort the stream body as soon as we
      # see the first chunk to minimize token spend (cost is ~25 input
      # tokens + 1 output token per probe).
      captured = nil
      http.request(req) do |res|
        captured = res.each_header.to_h
        res.read_body { |_| break }
      end
      captured
    end

    def build_payload(headers)
      now = Time.now.to_i
      {
        session: bucket(headers, "5h"),
        weekly_all: bucket(headers, "7d"),
        weekly_sonnet: bucket(headers, "7d_sonnet"),
        representative_claim: headers["anthropic-ratelimit-unified-representative-claim"],
        fallback_available: headers["anthropic-ratelimit-unified-fallback"] == "available",
        fallback_percentage: headers["anthropic-ratelimit-unified-fallback-percentage"]&.to_f,
        fetched_at: now,
        error: nil
      }
    end

    def bucket(headers, key)
      util = headers["anthropic-ratelimit-unified-#{key}-utilization"]
      reset = headers["anthropic-ratelimit-unified-#{key}-reset"]
      return nil unless util && reset

      {
        utilization: util.to_f,
        percent: (util.to_f * 100).round,
        reset_at: reset.to_i,
        status: headers["anthropic-ratelimit-unified-#{key}-status"]
      }
    end
  end
end
