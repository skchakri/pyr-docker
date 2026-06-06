# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Rails 8.1 control dashboard for managing Docker containers across multiple PYR Rails clients (and a few non-PYR Rails apps). It lives in `/home/kalyan/pyr-docker/dashboard/` inside the larger `pyr-docker/` project — the dashboard's parent directory contains the `docker-compose.yml` it controls.

## Common commands

```bash
# Run dashboard (port 3000)
bin/dev                        # exec rails server (reads PORT env if set)
bin/rails server -p 3000

# Lint / security
bin/rubocop -f github
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit

# Setup after fresh clone
bin/setup                      # bundle install, clears logs/tmp, restarts server
```

There are **no tests** in this repo. CI (`.github/workflows/ci.yml`) runs only the linters and security scanners above.

The parent project has a `pyr.sh` wrapper for the docker-compose lifecycle:
```bash
../pyr.sh build                       # build all images
../pyr.sh up stampinup avon           # start specific clients
../pyr.sh down [client]               # stop
../pyr.sh logs <client>
../pyr.sh console <client>            # docker exec rails console
../pyr.sh status
../pyr.sh restart <client>
```

## Architecture

### No database
`config/application.rb` explicitly removes `active_record`, `active_storage`, `action_mailer`, `action_mailbox`, `action_text`, and `rails/test_unit`. Only ActionCable, ActionPack, ActionView, ActiveJob, ActiveModel are loaded. **Do not add ActiveRecord models** — there is no DB connection. Persistent state lives in memory (`PtySessionStore`) or `localStorage` on the client.

### Two services do all the work

**`app/services/docker_service.rb`** — single source of truth for client definitions and lifecycle. It merges two sources:
1. **PYR clients** parsed from `../docker-compose.yml` (stampinup, partylite, avon, naturessunshine, monat, profvault). Each has a port, container name, host path, database, and git branch.
2. **Extra clients** from `config/extra_clients.yml` — currently `ownsites` (a separate `docker_compose` app).

Each client has a **type** that controls how start/stop/restart/logs work:
- `pyr` — `docker compose -f ../docker-compose.yml up/stop <name>` (PYR clients in the main compose file)
- `docker_compose` — `docker compose -f <compose_dir>/docker-compose.yml up/stop <service>` (apps with their own compose file, e.g. ownsites)
- `process` — host process; status via `lsof -i :PORT`, kill via PID lookup

When adding a new client, decide which type fits and add to the appropriate source. **Do not memoize `client_definitions` at the class level** — it caches across requests and was previously a bug; the current code intentionally rebuilds each call.

**`app/services/pty_session_store.rb`** — thread-safe in-memory store of PTY sessions keyed by `"#{client}__#{type}"` (e.g. `"stampinup__console"`). Holds a 100KB ring buffer per session for scrollback replay. This is **the** mechanism that makes terminals survive page refresh. Sessions are intentionally not killed in `unsubscribed` — only via the explicit kill button.

### Terminal channel

`app/channels/terminal_channel.rb` is the only ActionCable channel. On subscribe, it either:
- **Reattaches**: if `PtySessionStore.exists?(key)`, replays the buffer and sends `{reattached: true}` so the UI shows the green "live" dot.
- **Spawns**: builds a shell command based on `params[:type]` (`console`, `bash`, `terminal`, `logs`, `worker`, `scheduler`) and the client's type, then `PTY.spawn`s it. The command form differs for `pyr`/`docker_compose` (uses `docker exec`) vs `process` types (runs on host).

The read thread broadcasts output to `pty_session_<key>` and writes it into the ring buffer simultaneously, so a fresh subscriber gets the full scrollback. **`unsubscribed` deliberately does NOT kill the PTY** — that's the whole point of the persistence design.

### Frontend

Single-page vanilla JS in `app/views/dashboard/index.html.erb` (~425 lines, all logic in one inline `<script>`). No framework — no Stimulus, no Turbo Drive, no React. Uses:
- `fetch()` against `/api/clients/...` for REST calls
- A custom minimal ActionCable WebSocket client (not the `@rails/actioncable` JS lib)
- `xterm.js` from CDN (v5.5.0) with `FitAddon` and `WebLinksAddon`
- `localStorage` key `pyr_open_terminals` to remember which client/type sessions to reattach on page load

The terminal UI is a two-row tab bar: top row = client tabs, second row = type sub-tabs (console / bash / logs / worker / scheduler / terminal) with a green pulsing "live" dot, a kill button (■), and a close button (×). Only one pane is visible at a time inside `.terminal-panes`. The whole layout is `flex-direction: column` from `<body>` down so the terminal fills remaining viewport height under the cards — **do not break this flex chain** when editing CSS, or the terminal will either collapse to zero height or push cards off-screen (both have happened).

### Auto-login (`/api/clients/:name/dev_login`)

`Api::ClientsController#dev_login` proxies a Devise sign-in: it POSTs JSON to `http://localhost:<port>/users/sign_in` with hardcoded credentials, captures the `_pyr_session` cookie from the response, and forwards it to the browser before redirecting. The session cookie is set with `domain=localhost` so it's port-agnostic across all clients. CSRF is bypassed because Devise treats JSON content type as `verified_request?`. **Do not add `.json` to the sign-in URL** — Devise returns 406 for that path; the plain `/users/sign_in` with `Content-Type: application/json` is what works.

## Configuration

- `config/cable.yml` — `async` adapter in dev (in-process), `redis` in production
- `config/routes.rb` — mounts `/cable`, declares `Api::ClientsController` member routes (`start`, `stop`, `restart`, `logs`, `dev_login`), root → `dashboard#index`
- `config/extra_clients.yml` — non-PYR client definitions (currently just ownsites)
- `../docker-compose.yml` — authoritative source of PYR client services; `DockerService` parses it
- `../pyr_override_config.yml` — mounted into PYR containers as `/opt/.pyr/config.yml`

## Conventions specific to this repo

- **Importmap, not a JS bundler.** No `package.json`, no esbuild, no node_modules. Add JS deps via `bin/importmap pin` or pull from CDN.
- **Propshaft, not Sprockets.** CSS lives in `app/assets/stylesheets/application.css` as plain CSS (no SCSS).
- **Vanilla JS in ERB, not Stimulus.** When modifying frontend behavior, edit the inline `<script>` in `app/views/dashboard/index.html.erb`. Don't introduce Stimulus controllers unless restructuring the whole frontend.
- **Use Redis for shared data, Rails cache for repetitive data** (per global preference).
- The PYR clients run on host network mode and talk to local MySQL (3306), MongoDB (27017), Elasticsearch (9200), and Redis (6379) — assume these are running on the host when debugging client startup issues.
