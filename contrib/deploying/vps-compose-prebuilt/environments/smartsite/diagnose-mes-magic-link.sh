#!/usr/bin/env bash
# Diagnose MES "Failed to send magic link" on SmartSite VPS.
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
COMPOSE="-f docker-compose.smartsite.yml"

if [ ! -f .env ]; then
  echo "Missing $ROOT/.env" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

echo "=== MES magic link diagnostics ==="
echo

fail=0
ok() { echo "  OK: $*"; }
bad() { echo "  FAIL: $*"; fail=1; }

: "${MES_URL:?Set MES_URL in .env}"
: "${ERP_URL:?Set ERP_URL in .env}"
: "${SUPABASE_URL:?Set SUPABASE_URL in .env}"

echo "1) Container env (MES)"
mes_env="$(docker compose $COMPOSE exec -T mes printenv MES_URL ERP_URL SUPABASE_URL SUPABASE_INTERNAL_URL APP_URL 2>/dev/null || true)"
if [ -z "$mes_env" ]; then
  bad "mes container not running"
else
  echo "$mes_env" | sed 's/^/    /'
  echo "$mes_env" | grep -q "SUPABASE_INTERNAL_URL=http://kong:8000" && ok "SUPABASE_INTERNAL_URL" || bad "SUPABASE_INTERNAL_URL should be http://kong:8000 — recreate mes"
  echo "$mes_env" | grep -q "MES_URL=$MES_URL" && ok "MES_URL matches .env" || bad "MES_URL in container != .env"
fi
echo

echo "2) Kong auth health from MES"
if docker compose $COMPOSE exec -T mes node -e "fetch('http://kong:8000/auth/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(2))" 2>/dev/null; then
  ok "http://kong:8000/auth/v1/health"
else
  bad "MES cannot reach Kong — magic link OTP call will fail"
fi
echo

echo "3) GoTrue URI allow list (must include MES_URL/**)"
allow="$(docker compose $COMPOSE exec -T gotrue printenv GOTRUE_URI_ALLOW_LIST 2>/dev/null || true)"
if [ -z "$allow" ]; then
  bad "gotrue not running"
else
  echo "    $allow"
  echo "$allow" | grep -q "${MES_URL}/\*\*" && ok "MES_URL/** wildcard present" || bad "Missing ${MES_URL}/** — git pull compose and: docker compose $COMPOSE up -d --force-recreate gotrue"
fi
echo

echo "4) GoTrue SMTP"
for v in GOTRUE_SMTP_HOST GOTRUE_SMTP_USER; do
  val="$(docker compose $COMPOSE exec -T gotrue printenv "$v" 2>/dev/null || true)"
  [ -n "$val" ] && ok "$v=$val" || bad "$v empty"
done
pw_len="$(docker compose $COMPOSE exec -T gotrue sh -c 'wc -c < /run/secrets/smtp_password' 2>/dev/null | tr -d ' \r\n' || echo 0)"
if [ "$pw_len" -ge 16 ] 2>/dev/null; then
  ok "smtp_password length=$pw_len"
else
  bad "secrets/smtp_password too short ($pw_len) — use Gmail App Password"
fi
echo

echo "5) Magic-link email template (GoTrue fetches from ERP)"
if docker compose $COMPOSE exec -T gotrue wget -qO- http://erp:3000/templates/magic-link.html 2>/dev/null | head -c 120 | grep -q ConfirmationURL; then
  ok "template uses {{ .ConfirmationURL }}"
elif docker compose $COMPOSE exec -T gotrue wget -qO- http://erp:3000/templates/magic-link.html 2>/dev/null | head -c 80 | grep -q SiteURL; then
  bad "template still uses SiteURL (ERP-only links) — rebuild erp image after git pull"
else
  bad "cannot fetch http://erp:3000/templates/magic-link.html from gotrue"
fi
echo

echo "6) Test OTP + redirect (same call MES login uses)"
TEST_EMAIL="${1:-}"
if [ -n "$TEST_EMAIL" ]; then
  REDIRECT="${MES_URL}/callback"
  echo "    email=$TEST_EMAIL email_redirect_to=$REDIRECT"
  otp_out="$(docker compose $COMPOSE exec -T mes node -e "
    const email = $(printf '%s' "$TEST_EMAIL" | node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync(0,'utf8').trim()))");
    const redirect = $(printf '%s' "$REDIRECT" | node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync(0,'utf8').trim()))");
    fetch((process.env.SUPABASE_INTERNAL_URL||'http://kong:8000')+'/auth/v1/otp', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: 'Bearer '+process.env.SUPABASE_SERVICE_ROLE_KEY
      },
      body: JSON.stringify({ email, options: { email_redirect_to: redirect } })
    }).then(r=>r.json().then(j=>({ status: r.status, body: j }))).then(r=>{ console.log(JSON.stringify(r)); process.exit(r.status>=400?1:0); }).catch(e=>{ console.error(e); process.exit(2); });
  " 2>&1)" || {
    echo "$otp_out" | sed 's/^/    /'
    bad "POST /auth/v1/otp failed — read error msg (redirect allow list / SMTP / user)"
  }
  echo "$otp_out" | sed 's/^/    /'
  ok "OTP endpoint accepted request (if user exists, check email)"
else
  echo "    (skip) pass email: bash $0 you@example.com"
fi
echo

echo "7) Recent logs"
echo "--- mes (magic link) ---"
docker compose $COMPOSE logs mes --tail 15 2>/dev/null | grep -iE 'magic|login_failed|error' || echo "    (no matching lines)"
echo "--- gotrue ---"
docker compose $COMPOSE logs gotrue --tail 15 2>/dev/null || true
echo

if [ "$fail" -eq 0 ]; then
  echo "All static checks passed. If UI still fails, run with your email and read gotrue logs during login."
else
  echo "Fix FAIL items above, then: docker compose $COMPOSE up -d --force-recreate gotrue mes erp"
  exit 1
fi
