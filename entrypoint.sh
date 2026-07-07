#!/bin/bash
set -e

# Git config for GitHub access
git config --global --replace-all url.'git@github.com:'.insteadOf 'https://github.com/'
git config --global --add url.'git@github.com:'.insteadOf 'git://github.com/'

# The host ~/.ssh is mounted read-only and owned by the host user (uid 1000);
# in-container ssh runs as root and rejects it with "Bad owner or permissions on
# /root/.ssh/config", which breaks git-over-ssh gem fetches (e.g. datetimepicker).
# Copy the keys into a root-owned dir with correct perms and bypass the host's
# ssh config (it only defines an unrelated 'gateway' host).
mkdir -p /root/.ssh_container
cp -f /root/.ssh/id_* /root/.ssh_container/ 2>/dev/null || true
chown -R root:root /root/.ssh_container
chmod 700 /root/.ssh_container
chmod 600 /root/.ssh_container/* 2>/dev/null || true
chmod 644 /root/.ssh_container/*.pub 2>/dev/null || true
SSH_KEY_OPTS=""
for k in /root/.ssh_container/id_ed25519 /root/.ssh_container/id_rsa; do
  [ -f "$k" ] && SSH_KEY_OPTS="$SSH_KEY_OPTS -i $k"
done
export GIT_SSH_COMMAND="ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes $SSH_KEY_OPTS"

# Clean up stale pid
rm -f tmp/pids/server.pid

# Temporarily comment out yanked gem (meta_request 0.3.3 removed from rubygems)
sed -i "s/^  gem 'meta_request'/#  gem 'meta_request'/" /opt/pyr/common_pyr_dependencies.rb

# Uncomment auth_source in mongoid.yml development section (line 37)
sed -i '37s/# //' /opt/pyr/config/mongoid.yml

# Restore files on exit
cleanup() {
  sed -i "s/^#  gem 'meta_request'/  gem 'meta_request'/" /opt/pyr/common_pyr_dependencies.rb
  sed -i '37s/^        auth_source/        # auth_source/' /opt/pyr/config/mongoid.yml
}
trap cleanup EXIT

# Bundle install
bundle config set --local path '/usr/local/bundle'
bundle install

# Ensure pyr_widgets table has required columns (migration may not have run)
mysql -h ${DATABASE_HOST:-127.0.0.1} -P ${DATABASE_PORT:-3306} -u ${DATABASE_USER:-root} -p${DATABASE_PASSWORD:-password} ${DATABASE_NAME} -e "
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='${DATABASE_NAME}' AND TABLE_NAME='pyr_widgets' AND COLUMN_NAME='tab_configurable';
" 2>/dev/null | grep -q 1 || {
  echo "Adding missing pyr_widgets columns..."
  mysql -h ${DATABASE_HOST:-127.0.0.1} -P ${DATABASE_PORT:-3306} -u ${DATABASE_USER:-root} -p${DATABASE_PASSWORD:-password} ${DATABASE_NAME} -e "
    ALTER TABLE pyr_widgets ADD \`column\` varchar(255), ADD \`order\` int, ADD tab_configurable tinyint(1);
  " 2>/dev/null || true
}

# Run pending migrations
bundle exec rake db:migrate 2>&1 || echo "WARNING: db:migrate had errors, continuing..."

# Start rails
bundle exec rails s -b 0.0.0.0 -p ${PORT:-3000}
