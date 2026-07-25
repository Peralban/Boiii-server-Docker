#!/usr/bin/env bash
# =============================================================================
#  Starts the BO3 server, then opens an RCON terminal once it is ready.
#
#  Typing `switch <preset>` inside the RCON CLI writes a request that this
#  script picks up once the CLI exits: it restarts the server with that
#  preset and reopens the CLI automatically, looping until you type `exit`.
#
#  Usage:
#     ./start.sh            -> start + open the RCON terminal
#     ./start.sh --no-rcon  -> start only
#     ./start.sh --logs     -> start + follow the logs instead of RCON
# =============================================================================
set -euo pipefail

# Always resolve paths relative to this script's real location, not the
# caller's current directory (matters for the switch-request file below).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODE="rcon"
case "${1:-}" in
    --no-rcon) MODE="none" ;;
    --logs)    MODE="logs" ;;
esac

wait_for_ready() {
    for _ in $(seq 1 60); do
        if docker compose exec -T bo3 rcon status 2>/dev/null | grep -q "map:"; then
            return 0
        fi
        sleep 3
    done
    return 1
}

echo "==> Starting the BO3 server..."
docker compose up -d

if [ "$MODE" = "none" ]; then
    echo "Server started in the background."
    echo "  Logs : docker logs -f bo3-boiii"
    echo "  RCON : docker compose exec bo3 rcon"
    exit 0
fi

echo "==> Waiting for the map to load (can take ~1 min)..."
if ! wait_for_ready; then
    echo "The server did not answer RCON in time."
    echo "Troubleshoot with: docker logs -f bo3-boiii"
    exit 1
fi

echo "==> Server ready!"

if [ "$MODE" = "logs" ]; then
    docker logs -f bo3-boiii
    exit 0
fi

SWITCH_FILE="$SCRIPT_DIR/config/.switch_request"
while true; do
    echo
    # `|| true`: a non-zero exit here must not trip `set -e` before we get a
    # chance to check for a switch request below.
    docker compose exec bo3 rcon || true
    echo "(rcon exited — checking for a switch request at $SWITCH_FILE...)"

    if [ ! -f "$SWITCH_FILE" ]; then
        echo "(no switch request found)"
        break
    fi

    preset="$(tr -d '[:space:]' < "$SWITCH_FILE")"
    rm -f "$SWITCH_FILE"
    echo
    echo "==> Switch requested: '$preset'"
    "$SCRIPT_DIR/switch.sh" "$preset"

    if ! wait_for_ready; then
        echo "The server did not answer RCON in time after switching."
        exit 1
    fi
    echo "==> Server ready!"
done
