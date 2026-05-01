# frozen_string_literal: true

module Api
  class ManagerController < ApplicationController
    CLAUDE_DIR    = Pathname.new(Dir.home) / ".claude"
    SETTINGS_FILE = CLAUDE_DIR / "settings.json"
    SKILLS_DIR    = CLAUDE_DIR / "skills"
    HISTORY_FILE  = CLAUDE_DIR / "history.jsonl"

    SKILL_SIGNALS = {
      "stripe"       => [ "stripe-billing",   "Stripe payments detected in your prompts" ],
      "billing"      => [ "stripe-billing",   "Billing work detected in your prompts" ],
      "subscription" => [ "stripe-billing",   "Subscription logic detected" ],
      "deploy"       => [ "kamal-deploy",     "Deployment prompts detected" ],
      "kamal"        => [ "kamal-deploy",     "Kamal deploy prompts detected" ],
      "hotwire"      => [ "rails-hotwire",    "Hotwire usage detected" ],
      "turbo"        => [ "rails-hotwire",    "Turbo frame/stream usage detected" ],
      "stimulus"     => [ "rails-hotwire",    "Stimulus controller usage detected" ],
      "chrome"       => [ "chrome-extension", "Browser extension work detected" ],
      "extension"    => [ "chrome-extension", "Extension development detected" ],
      "embedding"    => [ "rag-embeddings",   "Embedding/RAG work detected" ],
      "pgvector"     => [ "rag-embeddings",   "pgvector usage detected" ],
      "vector"       => [ "rag-embeddings",   "Vector search detected" ],
      "security"     => [ "rails-security",   "Security-related prompts detected" ],
      "brakeman"     => [ "rails-security",   "Brakeman scan detected" ],
      "android"      => [ "android-dev",      "Android development detected" ],
      "kotlin"       => [ "android-dev",      "Kotlin/Android work detected" ],
      "error"        => [ "fix-errors",       "Error-fixing prompts detected" ],
      "bug"          => [ "fix-errors",       "Bug-fixing patterns detected" ],
      "anthropic"    => [ "ai-prompts",       "Anthropic API usage detected" ]
    }.freeze

    MCP_SIGNALS = {
      "github"   => [ "github",       "GitHub work in your history" ],
      "postgres" => [ "postgres",     "PostgreSQL queries in history" ],
      "database" => [ "postgres",     "Database work detected" ],
      "search"   => [ "brave-search", "Web search requests detected" ],
      "browser"  => [ "puppeteer",    "Browser automation detected" ],
      "scrape"   => [ "puppeteer",    "Scraping work detected" ],
      "slack"    => [ "slack",        "Slack references detected" ],
      "redis"    => [ "redis",        "Redis usage in history" ],
      "sqlite"   => [ "sqlite",       "SQLite usage detected" ],
      "file"     => [ "filesystem",   "File system operations detected" ]
    }.freeze

    # GET /api/manager/state
    def state
      render json: {
        skills:  read_skills,
        plugins: read_plugins,
        mcps:    read_mcps
      }
    end

    # GET /api/manager/suggestions
    def suggestions
      render json: analyze_history
    end

    # POST /api/manager/skills/install  { repo: "owner/repo" }
    def skills_install
      repo = params[:repo].to_s.strip
      return render_error("repo required") if repo.blank?

      if repo.start_with?("http")
        url  = repo.end_with?(".git") ? repo : "#{repo}.git"
        name = url.rstrip.delete_suffix(".git").split("/").last
      elsif repo.include?("/")
        parts = repo.split("/")
        name  = parts.last
        url   = "https://github.com/#{parts.first(2).join('/')}.git"
      else
        return render_error("Expected owner/repo or full GitHub URL")
      end

      dest = SKILLS_DIR / name
      return render_error("Skill '#{name}' already installed") if dest.exist?

      SKILLS_DIR.mkpath
      result = system("git clone --depth=1 #{Shellwords.escape(url)} #{Shellwords.escape(dest.to_s)}")
      if result
        render json: { ok: true, name: name }
      else
        render_error("git clone failed — check the repo URL")
      end
    end

    # POST /api/manager/skills/remove  { name: "skill-name" }
    def skills_remove
      name = params[:name].to_s.strip
      return render_error("invalid name") if name.blank? || name.include?("/") || name.start_with?(".")

      dest = SKILLS_DIR / name
      return render_error("Skill '#{name}' not found") unless dest.exist?

      FileUtils.rm_rf(dest)
      render json: { ok: true }
    end

    # POST /api/manager/plugins/add  { id: "name@marketplace" }
    def plugins_add
      id = params[:id].to_s.strip
      return render_error("id required") if id.blank?

      update_settings { |s| s["enabledPlugins"] ||= {}; s["enabledPlugins"][id] = true }
      render json: { ok: true }
    end

    # POST /api/manager/plugins/toggle  { id:, enabled: }
    def plugins_toggle
      id      = params[:id].to_s.strip
      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      update_settings do |s|
        return render_error("plugin not found") unless s.dig("enabledPlugins", id)
        s["enabledPlugins"][id] = enabled
      end
      render json: { ok: true }
    end

    # POST /api/manager/plugins/remove  { id: }
    def plugins_remove
      id = params[:id].to_s.strip
      update_settings do |s|
        return render_error("plugin not found") unless s.dig("enabledPlugins", id)
        s["enabledPlugins"].delete(id)
      end
      render json: { ok: true }
    end

    # POST /api/manager/mcp/add  { name:, config: {} }
    def mcp_add
      name   = params[:name].to_s.strip
      config = params[:config].to_unsafe_h rescue {}
      return render_error("name required") if name.blank?

      update_settings { |s| s["mcpServers"] ||= {}; s["mcpServers"][name] = config }
      render json: { ok: true }
    end

    # POST /api/manager/mcp/remove  { name: }
    def mcp_remove
      name = params[:name].to_s.strip
      update_settings do |s|
        return render_error("MCP server not found") unless s.dig("mcpServers", name)
        s["mcpServers"].delete(name)
      end
      render json: { ok: true }
    end

    private

    def read_settings
      return {} unless SETTINGS_FILE.exist?
      JSON.parse(SETTINGS_FILE.read)
    rescue JSON::ParserError
      {}
    end

    def write_settings(data)
      SETTINGS_FILE.write(JSON.pretty_generate(data) + "\n")
    end

    def update_settings(&block)
      s = read_settings
      block.call(s)
      write_settings(s)
    end

    def read_skills
      return [] unless SKILLS_DIR.exist?
      SKILLS_DIR.children.select(&:directory?).reject { |d| d.basename.to_s.start_with?(".") }.sort.map do |d|
        desc = ""
        %w[README.md readme.md DESCRIPTION].each do |fn|
          f = d / fn
          next unless f.exist?
          f.read(encoding: "utf-8", invalid: :replace).lines.each do |line|
            line = line.strip.sub(/\A#+\s*/, "")
            next if line.blank?
            desc = line.truncate(100)
            break
          end
          break unless desc.blank?
        end
        { name: d.basename.to_s, description: desc }
      end
    end

    def read_plugins
      read_settings.fetch("enabledPlugins", {}).map { |id, enabled| { id: id, enabled: enabled } }
    end

    def read_mcps
      read_settings.fetch("mcpServers", {}).map { |name, config| { name: name, config: config } }
    end

    def analyze_history
      return empty_suggestions unless HISTORY_FILE.exist?

      entries      = []
      proj_counts  = Hash.new(0)

      HISTORY_FILE.each_line(encoding: "utf-8", invalid: :replace) do |line|
        e = JSON.parse(line) rescue next
        entries << e
        proj_counts[e["project"]] += 1 if e["project"].present?
      end

      all_text = entries.filter_map { |e|
        t = e["display"].to_s
        t unless t.blank? || t.start_with?("/")
      }.join(" ").downcase

      installed_skills  = read_skills.map  { |s| s[:name] }.to_set
      installed_mcps    = read_mcps.map    { |m| m[:name] }.to_set

      skill_suggestions = {}
      SKILL_SIGNALS.each do |kw, (skill, reason)|
        next if installed_skills.include?(skill) || skill_suggestions.key?(skill)
        skill_suggestions[skill] = reason if all_text.include?(kw)
      end

      mcp_suggestions = {}
      MCP_SIGNALS.each do |kw, (mcp, reason)|
        next if installed_mcps.include?(mcp) || mcp_suggestions.key?(mcp)
        mcp_suggestions[mcp] = reason if all_text.include?(kw)
      end

      prompt_count = entries.count { |e| e["display"].present? && !e["display"].start_with?("/") }
      top_projects = proj_counts.sort_by { |_, c| -c }.first(5).map { |p, c| { path: p, count: c } }

      {
        skill_suggestions: skill_suggestions.first(6).map { |n, r| { name: n, reason: r } },
        mcp_suggestions:   mcp_suggestions.first(4).map   { |n, r| { name: n, reason: r } },
        top_projects:      top_projects,
        prompt_count:      prompt_count
      }
    end

    def empty_suggestions
      { skill_suggestions: [], mcp_suggestions: [], top_projects: [], prompt_count: 0 }
    end

    def render_error(msg, status = :unprocessable_entity)
      render json: { ok: false, error: msg }, status: status
    end
  end
end
