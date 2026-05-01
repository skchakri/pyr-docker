#!/bin/bash
set -e

rm -f tmp/pids/server.pid

bundle install

bin/rails db:prepare 2>&1 || echo "WARNING: db:prepare had errors, continuing..."

bin/rails tailwindcss:watch &

bin/rails server -b 0.0.0.0 -p ${PORT:-1200}
