#!/usr/bin/env bash
# =============================================================================
#  Starts the BO3 server, then opens an RCON terminal once it is ready.
#
#  Usage:
#     ./start.sh            -> start + open the RCON terminal
#     ./start.sh --no-rcon  -> start only
#     ./start.sh --logs     -> start + follow the logs instead of RCON
# =============================================================================
set -euo pipefail

MODE="rcon"
case "${1:-}" in
    --no-rcon) MODE="none" ;;
    --logs)    MODE="logs" ;;
esac

echo "==> Starting the BO3 server..."
docker compose up -d

if [ "$MODE" = "none" ]; then
    echo "Server started in the background."
    echo "  Logs : docker logs -f bo3-boiii"
    echo "  RCON : docker compose exec bo3 rcon"
    exit 0
fi

echo "==> Waiting for the map to load (can take ~1 min)..."
ready=0
for _ in $(seq 1 60); do
    if docker compose exec -T bo3 rcon status 2>/dev/null | grep -q "map:"; then
        ready=1
        break
    fi
    sleep 3
done

if [ "$ready" -ne 1 ]; then
    echo "The server did not answer RCON in time."
    echo "Troubleshoot with: docker logs -f bo3-boiii"
    exit 1
fi

echo "==> Server ready!"

if [ "$MODE" = "logs" ]; then
    docker logs -f bo3-boiii
else
    echo
    docker compose exec bo3 rcon
fi
