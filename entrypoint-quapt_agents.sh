#!/bin/bash
set -e

# Drop stale puma pid (container restart leftover).
rm -f tmp/pids/server.pid

# Install gems into the cached bundler volume.
bundle install

# Create/migrate the dev DB against the shared dev_datastack Postgres on the host.
bin/rails db:prepare 2>&1 || echo "WARNING: db:prepare had errors, continuing..."

# Seed the 8 use cases + synthetic fraud data so the demo always has content.
# Seeds are idempotent (use cases upserted; fraud domain reset for a clean demo).
bin/rails db:seed 2>&1 || echo "WARNING: db:seed had errors, continuing..."

# Tailwind in watch mode — keeps app/assets/builds/tailwind.css fresh.
bin/rails tailwindcss:watch &

# Boot Rails on the host network (network_mode: host in compose).
exec bin/rails server -b 0.0.0.0 -p "${PORT:-3030}"
