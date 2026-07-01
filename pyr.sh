#!/bin/bash

# Pyr Docker Runner - runs outside the pyr repo
# Usage:
#   ./pyr.sh build                    # Build the Docker image (one-time)
#   ./pyr.sh up                       # Start ALL clients
#   ./pyr.sh up stampinup avon        # Start specific clients
#   ./pyr.sh down                     # Stop all clients
#   ./pyr.sh down stampinup           # Stop specific client
#   ./pyr.sh logs stampinup           # Tail logs for a client
#   ./pyr.sh console stampinup        # Rails console for a client
#   ./pyr.sh bash stampinup           # Shell into a client container
#   ./pyr.sh status                   # Show running clients
#   ./pyr.sh restart stampinup        # Restart a specific client

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ACTION="${1:-status}"
shift

case "$ACTION" in
  build)
    echo "Building pyr Docker image..."
    docker compose build
    ;;
  up)
    if [ $# -eq 0 ]; then
      echo "Starting ALL clients (this will use a lot of memory)..."
      echo "Consider starting specific clients: ./pyr.sh up stampinup avon"
      read -p "Continue? [y/N] " confirm
      [ "$confirm" != "y" ] && exit 0
      docker compose up -d
    else
      echo "Starting: $@"
      docker compose up -d "$@"
    fi
    echo ""
    echo "Port assignments:"
    echo "  myjira:1200  profvault:1100  planmytrip:3010  quapt_agents:3030  brand_reel:3040"
    echo "  avon:3001  naturessunshine:3002  stampinup:3003  monat:3004  partylite:3005  zevents:3007"
    echo "  naturessunshine:3004  monat:3005  avonpr:3006  bluesun:3007"
    echo "  greenzone:3008  idlife:3009  listenuniversity:3011"
    echo "  liveultimate:3012  longaberger:3013  nevetica:3014  primelife:3015"
    echo "  retro:3016  rxexpress:3017  saba:3018  trurise:3019"
    echo "  tupperware:3020  worldventures:3021  zsuite:3022"
    ;;
  down)
    if [ $# -eq 0 ]; then
      docker compose down
    else
      docker compose stop "$@"
      docker compose rm -f "$@"
    fi
    ;;
  logs)
    docker compose logs -f "$@"
    ;;
  console)
    CLIENT="${1:?Usage: ./pyr.sh console <client>}"
    docker exec -it "pyr-$CLIENT" bundle exec rails console
    ;;
  bash)
    CLIENT="${1:?Usage: ./pyr.sh bash <client>}"
    docker exec -it "pyr-$CLIENT" bash
    ;;
  status)
    docker compose ps
    ;;
  restart)
    if [ $# -eq 0 ]; then
      echo "Usage: ./pyr.sh restart <client> [client2...]"
      exit 1
    fi
    docker compose restart "$@"
    ;;
  restart-vite)
    CLIENT="${1:?Usage: ./pyr.sh restart-vite <client>}"
    case "$CLIENT" in
      ownsites) COMPOSE_DIR_OVERRIDE="/home/kalyan/platform/skchakri/ownsites" ;;
      *) echo "No vite service registered for client: $CLIENT"; exit 1 ;;
    esac
    echo "Restarting vite in $COMPOSE_DIR_OVERRIDE..."
    docker compose -f "$COMPOSE_DIR_OVERRIDE/docker-compose.yml" restart vite
    ;;
  *)
    echo "Usage: ./pyr.sh {build|up|down|logs|console|bash|status|restart|restart-vite} [clients...]"
    exit 1
    ;;
esac
