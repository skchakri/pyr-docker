#!/bin/bash
set -e

# Install JS deps into the cached node_modules volume. `npm ci` keeps it in lock
# step with package-lock.json and rebuilds native binaries (next, remotion) for
# the container's arch — which is why node_modules is a named volume, not the
# bind-mounted host copy.
npm ci

# Bake/refresh the Remotion-managed Chromium used by the render pipeline. Stored
# under the node_modules volume, so it persists across restarts. Non-fatal if the
# command name shifts across Remotion versions.
npx remotion browser ensure || echo "WARNING: remotion browser ensure failed, renders may download Chromium on first use..."

# Boot the Next.js dev server on the host network (network_mode: host in compose).
exec npm run dev -- --port "${PORT:-3040}" --hostname 0.0.0.0
