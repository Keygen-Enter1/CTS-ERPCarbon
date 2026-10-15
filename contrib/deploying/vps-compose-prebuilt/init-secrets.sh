#!/usr/bin/env bash
# Create ./secrets/* for Docker Compose (first-time VPS setup).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SECRETS="$HERE/secrets"
GEN="$HERE/../simple-docker-caddy/scripts/gen-supabase-keys.sh"

mkdir -p "$SECRETS"

rand() { openssl rand -hex 32; }

if [ ! -f "$SECRETS/postgres_password" ]; then
  pw="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
  printf '%s' "$pw" >"$SECRETS/postgres_password"
  printf 'postgres://authenticator:%s@postgres:5432/postgres' "$pw" >"$SECRETS/postgrest_db_uri"
fi

if [ ! -f "$SECRETS/jwt_secret" ]; then
  "$GEN" >"$HERE/.supabase-keys.tmp"
  # shellcheck disable=SC1091
  . "$HERE/.supabase-keys.tmp"
  rm -f "$HERE/.supabase-keys.tmp"
  printf '%s' "$SUPABASE_JWT_SECRET" >"$SECRETS/jwt_secret"
  printf '%s' "$SUPABASE_ANON_KEY" >"$SECRETS/anon_key"
  printf '%s' "$SUPABASE_SERVICE_ROLE_KEY" >"$SECRETS/service_role_key"
fi

for name in session_secret inngest_signing_key inngest_event_key; do
  [ -f "$SECRETS/$name" ] || rand >"$SECRETS/$name"
done

[ -f "$SECRETS/resend_api_key" ] || : >"$SECRETS/resend_api_key"
[ -f "$SECRETS/smtp_password" ] || printf 'change_me' >"$SECRETS/smtp_password"
[ -f "$SECRETS/saml_private_key" ] || printf 'change_me' >"$SECRETS/saml_private_key"

chmod 600 "$SECRETS"/* 2>/dev/null || true
echo "Secrets written under $SECRETS"
echo "Edit smtp_password (and optional resend_api_key) before production use."
