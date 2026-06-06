#!/bin/bash
set -e

# GitHub SSH access for private gems if any
git config --global --replace-all url.'git@github.com:'.insteadOf 'https://github.com/' 2>/dev/null || true
git config --global --add url.'git@github.com:'.insteadOf 'git://github.com/' 2>/dev/null || true
export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no'

cd /opt/zevents

rm -f tmp/pids/server.pid

# Bundle install (cached in named volume /usr/local/bundle)
bundle config set --local path '/usr/local/bundle'
bundle install --jobs=4

# Yarn install for webpacker
yarn install --check-files

# Wait for MySQL to be reachable
echo "[zevents] Waiting for MySQL at ${ZEVENTS_DB_HOST}:${ZEVENTS_DB_PORT}..."
until mysql -h "${ZEVENTS_DB_HOST}" -P "${ZEVENTS_DB_PORT}" \
      -u "${ZEVENTS_DB_USER}" -p"${ZEVENTS_DB_PASSWORD}" \
      -e 'SELECT 1' >/dev/null 2>&1; do
  sleep 2
done
echo "[zevents] MySQL ready."

# Verify the target database exists. Do NOT auto-create or migrate —
# user is importing a production dump and any structural change would clobber it.
if ! mysql -h "${ZEVENTS_DB_HOST}" -P "${ZEVENTS_DB_PORT}" \
      -u "${ZEVENTS_DB_USER}" -p"${ZEVENTS_DB_PASSWORD}" \
      -e "USE \`${ZEVENTS_DB_NAME}\`" >/dev/null 2>&1; then
  echo "[zevents] WARNING: database '${ZEVENTS_DB_NAME}' not found. Import a dump or set ZEVENTS_DB_NAME."
fi

# Start webpacker dev server in background
echo "[zevents] Starting webpack-dev-server on :${WEBPACKER_DEV_SERVER_PORT:-3035}..."
WEBPACKER_DEV_SERVER_HOST=0.0.0.0 ./bin/webpack-dev-server &
WP_PID=$!
trap "echo '[zevents] Stopping webpacker (pid $WP_PID)'; kill $WP_PID 2>/dev/null || true" EXIT

# Start Rails (foreground)
echo "[zevents] Starting Rails on :${PORT:-3007}..."
exec bundle exec rails s -b 0.0.0.0 -p "${PORT:-3007}"
