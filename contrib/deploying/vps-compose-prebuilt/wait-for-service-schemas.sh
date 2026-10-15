#!/usr/bin/env bash
# Wait until GoTrue, Storage and Realtime have migrated auth/storage/realtime schemas.
# Carbon SQL migrations reference auth.mfa_factors, storage.buckets, realtime.messages, etc.
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

COMPOSE="${COMPOSE:--f docker-compose.smartsite.yml}"
attempts="${1:-120}"

read -r -d '' SQL <<'EOSQL' || true
SELECT
  to_regclass('auth.users') IS NOT NULL
  AND to_regclass('auth.mfa_factors') IS NOT NULL
  AND to_regclass('storage.buckets') IS NOT NULL
  AND to_regclass('storage.objects') IS NOT NULL
  AND to_regclass('realtime.messages') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'users'
      AND column_name = 'email_confirmed_at'
  );
EOSQL

echo "Waiting for GoTrue / Storage / Realtime schemas (up to $((attempts * 5))s)…"
echo "Ensure stack is up: gotrue, storage, realtime, postgres"

for _ in $(seq 1 "$attempts"); do
  ready=$(docker compose $COMPOSE exec -T postgres \
    psql -U postgres -d postgres -tAc "$SQL" 2>/dev/null | tr -d '[:space:]' || true)
  if [ "$ready" = "t" ]; then
    echo "Service schemas ready"
    exit 0
  fi
  sleep 5
done

echo "Timed out — check containers:" >&2
docker compose $COMPOSE ps gotrue storage realtime postgres >&2 || true
echo "Logs:" >&2
docker compose $COMPOSE logs gotrue storage realtime --tail 30 >&2 || true
exit 1
