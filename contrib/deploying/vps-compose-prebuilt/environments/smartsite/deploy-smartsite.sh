#!/usr/bin/env bash
# SmartSite prod: pull images, start stack on 30xxx ports, run migrations (no Carbon Caddy).
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

COMPOSE="-f docker-compose.smartsite.yml"
SCALE_CADDY="${SCALE_CADDY:-0}"

[ -f .env ] || {
  echo "Missing $ROOT/.env — run: cp environments/smartsite/env.template .env && edit it" >&2
  exit 1
}
[ -f secrets/postgres_password ] || {
  echo "Run ./init-secrets.sh first." >&2
  exit 1
}

set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${CARBON_REPO:?Set CARBON_REPO in .env}"
[ -f "$CARBON_REPO/Dockerfile" ] || {
  echo "CARBON_REPO must point at a full Carbon git checkout." >&2
  exit 1
}

# Images from build-on-server.sh use tags like carbon/erp:tag — not on Docker Hub.
should_pull() {
  [ "${SKIP_PULL:-0}" = "1" ] && return 1
  case "${CARBON_IMAGE_ERP:-}" in
    carbon/*) return 1 ;;
  esac
  return 0
}

if should_pull; then
  echo "Pulling Carbon images from registry…"
  docker compose $COMPOSE pull erp mes migrate 2>/dev/null || docker compose $COMPOSE pull
else
  echo "Using local images (carbon/*) — skipping docker pull"
  for ref in "$CARBON_IMAGE_ERP" "$CARBON_IMAGE_MES" "$CARBON_IMAGE_BOOTSTRAP"; do
    docker image inspect "$ref" >/dev/null 2>&1 || {
      echo "Missing local image $ref — run build-on-server.sh or set SKIP_PULL=0 and a registry tag" >&2
      exit 1
    }
  done
fi

echo "Starting stack (Caddy scaled to $SCALE_CADDY)…"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --scale "caddy=$SCALE_CADDY"

echo "Waiting for postgres…"
for _ in $(seq 1 60); do
  if docker compose $COMPOSE ps postgres 2>/dev/null | grep -q healthy; then break; fi
  sleep 5
done

echo "Running migrations…"
docker compose $COMPOSE --profile migrate run --rm migrate

cat <<EOF

Carbon (SmartSite) is up.

  ERP  https://erpcarbon.smartsite.vn  → 127.0.0.1:30000
  MES  https://mescarbon.smartsite.vn  → 127.0.0.1:30001
  API  https://apicarbon.smartsite.vn  → 127.0.0.1:30003

Ensure nginx (or your edge proxy) matches environments/smartsite/nginx-carbon.conf
and DNS A records for the three hostnames point at this server.

EOF
