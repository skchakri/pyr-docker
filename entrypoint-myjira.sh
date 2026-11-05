#!/bin/bash
set -e

rm -f tmp/pids/server.pid

bundle install

bin/rails db:prepare 2>&1 || echo "WARNING: db:prepare had errors, continuing..."

bin/rails tailwindcss:watch &

# Bind to loopback only: myjira has no auth and its API launches unattended
# Claude sessions, so it must not be reachable from the LAN. Override with
# BIND_HOST=0.0.0.0 if you deliberately want remote access.
bin/rails server -b ${BIND_HOST:-127.0.0.1} -p ${PORT:-1200}
