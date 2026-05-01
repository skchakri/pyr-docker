require "redis"

# Shared Redis connection pool for dashboard-level shared data (prompt
# history, etc). Uses db 9 to stay out of the way of the PYR clients, which
# map 0..5, profvault, etc.
REDIS = Redis.new(
  url: ENV.fetch("DASHBOARD_REDIS_URL", "redis://127.0.0.1:6379/9"),
  reconnect_attempts: 1,
  connect_timeout: 1.0,
  read_timeout: 1.0,
  write_timeout: 1.0
)
