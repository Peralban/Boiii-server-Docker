#!/usr/bin/env bash
# =============================================================================
#  Switch the server between multiplayer / zombies / campaign co-op.
#  BO3 cannot switch mode live (it crashes), so this changes SERVER_CFG in
#  .env and recreates the container (~15s).
#
#  Usage:
#     ./switch.sh mp     -> multiplayer  (server.cfg)
#     ./switch.sh zm     -> zombies      (server_zm.cfg)
#     ./switch.sh cp     -> campaign co-op (server_cp.cfg)
# =============================================================================
set -euo pipefail

case "${1:-}" in
    mp) cfg="server.cfg" ;;
    zm) cfg="server_zm.cfg" ;;
    cp) cfg="server_cp.cfg" ;;
    *)  echo "Usage: $0 {mp|zm|cp}"; exit 1 ;;
esac

if [ ! -f .env ]; then
    echo "No .env found. Copy .env.example to .env first."
    exit 1
fi

if grep -q '^SERVER_CFG=' .env; then
    sed -i "s|^SERVER_CFG=.*|SERVER_CFG=$cfg|" .env
else
    echo "SERVER_CFG=$cfg" >> .env
fi

echo "==> Mode: ${1}  (SERVER_CFG=$cfg)"
echo "==> Recreating the container..."
docker compose up -d --force-recreate
echo "==> Done. Follow the load with: docker logs -f bo3-boiii"
