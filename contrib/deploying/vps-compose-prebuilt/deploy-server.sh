#!/usr/bin/env bash
# VPS: pull prebuilt images and run the stack (no docker build).
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

COMPOSE_FILES="${COMPOSE_FILES:-docker-compose.yml}"
SCALE_CADDY="${SCALE_CADDY:-1}"

[ -f .env ] || { echo "Copy .env.example to .env and configure it." >&2; exit 1; }
[ -f secrets/postgres_password ] || { echo "Run ./init-secrets.sh first." >&2; exit 1; }

set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${CARBON_REPO:?Set CARBON_REPO in .env}"
[ -f "$CARBON_REPO/Dockerfile" ] || {
  echo "CARBON_REPO must point at a full Carbon git checkout (for bind mounts)." >&2
  exit 1
}

compose() {
  # COMPOSE_FILES=docker-compose.yml:docker-compose.publish-30xxx.yml
  local args=()
  local IFS=:
  for f in $COMPOSE_FILES; do args+=(-f "$f"); done
  docker compose "${args[@]}" "$@"
}

echo "Pulling images…"
compose pull erp mes migrate 2>/dev/null || compose pull

echo "Starting stack (caddy scale=$SCALE_CADDY)…"
compose up -d --scale "caddy=$SCALE_CADDY"

wait_healthy() {
  local svc="$1" attempts="${2:-60}"
  echo "Waiting for $svc…"
  for _ in $(seq 1 "$attempts"); do
    if compose ps "$svc" 2>/dev/null | grep -q healthy; then return 0; fi
    sleep 5
  done
  echo "Timed out waiting for $svc" >&2
  return 1
}

wait_healthy postgres 60
wait_healthy storage 60

echo "Running migrations…"
compose --profile migrate run --rm migrate

echo "Done. ERP: ${ERP_URL:-?}  MES: ${MES_URL:-?}"
