#!/bin/bash
set -e

rm -f tmp/pids/server.pid

bundle install

# Create the databases if needed and run migrations.
bin/rails db:prepare 2>&1 || echo "WARNING: db:prepare had errors, continuing..."

# Tailwind: build once so the first request has CSS, then watch for changes.
bin/rails tailwindcss:build
bin/rails tailwindcss:watch &

# Solid Queue: background jobs plus the recurring schedule (menu and calendar
# syncs, allowance, digests). Runs alongside the web server in this container.
bin/jobs &

# Reachable on the LAN (Android app, phones on home Wi-Fi).
bin/rails server -b ${BIND_HOST:-0.0.0.0} -p ${PORT:-1400}
