#!/bin/bash
set -e

# Clean up stale pid
rm -f tmp/pids/server.pid

# Bundle install
bundle install

# Setup python-jobspy venv if not present
if [ ! -d "/rails/.jobspy-venv" ]; then
  python3 -m venv /rails/.jobspy-venv
  /rails/.jobspy-venv/bin/pip install --no-cache-dir python-jobspy
fi
export PATH="/rails/.jobspy-venv/bin:${PATH}"

# Prepare database (create if needed, run migrations)
bin/rails db:prepare 2>&1 || echo "WARNING: db:prepare had errors, continuing..."

# Build Tailwind CSS in background
bin/rails tailwindcss:watch &

# Start rails server
bin/rails server -b 0.0.0.0 -p ${PORT:-1100}
