# Carbon @ SmartSite (`*.smartsite.vn`)

Production layout: **prebuilt Docker images**, **30xxx ports** on localhost, **TLS on your existing reverse proxy** (Carbon Caddy is not used).

## Domains & ports

| Service | Public URL | Firewall |
|---------|------------|----------|
| ERP | **http://erpcarbon.smartsite.vn:30000/** | TCP **30000** |
| MES | **http://mescarbon.smartsite.vn:30001/** | TCP **30001** |
| API (Kong) | **http://apicarbon.smartsite.vn:30003/** | TCP **30003** |

Set `ERP_URL`, `MES_URL`, `SUPABASE_URL` in `.env` to those URLs (see `env.template`). TLS/nginx on :443 is optional.

**`.env` checklist (HTTP on 30xxx)**

| Variable | Value |
|----------|--------|
| `CARBON_REPO` | Full git checkout on the VPS, e.g. `/home/abinh/CTS-ERPCarbon` |
| `ERP_URL` / `MES_URL` / `SUPABASE_URL` | `http://…smartsite.vn:30000` / `:30001` / `:30003` |
| `DOMAIN` | **Empty** until you serve ERP over HTTPS (avoids Secure cookies on plain HTTP) |
| `GOTRUE_DISABLE_SIGNUP` | `false` until the first admin exists, then `true` |
| `GOTRUE_SMTP_*` | Gmail (or other SMTP); password only in `secrets/smtp_password` |
| `INNGEST_*` | As in `env.template` (Inngest on Docker network) |
| `RATE_LIMIT` | e.g. `30` on self-host (default **5**/hour/IP on login & verify) |

**“Authentication Error — Rate limit exceeded”** — Carbon’s IP limit (Redis), not Postgres. Wait up to 1 hour, or reset counters:

```bash
docker compose -f docker-compose.smartsite.yml exec redis redis-cli --scan --pattern '@carbon/ratelimit:*' \
  | xargs -r docker compose -f docker-compose.smartsite.yml exec -T redis redis-cli DEL
```

If the message is *“For your security, sign-in for this account is temporarily paused”*, that is per-email lockout — scan `@carbon/lockout:*` the same way.

After changing `.env` or `git pull` (compose updates), recreate app containers:

```bash
docker compose -f docker-compose.smartsite.yml up -d --force-recreate erp mes gotrue postgrest
docker compose -f docker-compose.smartsite.yml exec erp sh -c 'echo INTERNAL=$SUPABASE_INTERNAL_URL PUBLIC=$SUPABASE_URL'
# Expect: INTERNAL=http://kong:8000
```

Internal only (do **not** expose on firewall): Postgres, Redis, Inngest, etc.

## DNS

Create **A** (or AAAA) records → IP VPS:

- `erpcarbon.smartsite.vn`
- `mescarbon.smartsite.vn`
- `apicarbon.smartsite.vn`

## Build on the VPS (no tar, no registry)

From a full git checkout on the server (~8 GB RAM for ERP build):

```bash
cd contrib/deploying/vps-compose-prebuilt
cp environments/smartsite/env.template .env   # set CARBON_REPO
bash ./init-secrets.sh
TAG=smartsite-1 bash ./build-on-server.sh
# paste CARBON_IMAGE_* into .env
bash ./environments/smartsite/deploy-smartsite.sh
```

## 1. Local — build & push images

```powershell
# Windows (repo root)
$env:REGISTRY = "ghcr.io/YOUR_ORG/carbon"   # or Docker Hub
$env:TAG = "smartsite-1"
.\contrib\deploying\vps-compose-prebuilt\build-and-push.ps1
```

## 2. VPS — first install

```bash
sudo git clone <your-repo> /opt/carbon
cd /opt/carbon/contrib/deploying/vps-compose-prebuilt

cp environments/smartsite/env.template .env
# Edit .env: CARBON_REPO=/opt/carbon, CARBON_IMAGE_* from build output

bash ./init-secrets.sh
# Gmail: copy env.template SMTP vars into .env; put the App Password in secrets/smtp_password (never commit it)

chmod +x environments/smartsite/deploy-smartsite.sh init-secrets.sh
bash ./environments/smartsite/deploy-smartsite.sh
# (Do not use `sh script.sh` — use bash or ./script after chmod +x)
```

## 3. Nginx (optional)

Default access is **HTTP on ports 30000–30003** (no nginx required). For HTTPS on :443, copy/adapt `nginx-carbon.conf` and proxy to the same host ports.

OAuth providers (Google/Azure): redirect URI  
`http://apicarbon.smartsite.vn:30003/auth/v1/callback`

## 4. Updates

Local: bump `TAG`, run `build-and-push` again.

VPS:

```bash
cd /opt/carbon && git pull
cd contrib/deploying/vps-compose-prebuilt
# Update CARBON_IMAGE_* tags in .env if needed
./environments/smartsite/deploy-smartsite.sh
```

## Files

| File | Purpose |
|------|---------|
| `env.template` | Production `.env` template |
| `nginx-carbon.conf` | Optional TLS proxy to 30xxx |
| `deploy-smartsite.sh` | `compose.smartsite.yml` + migrate |
| `../../docker-compose.smartsite.yml` | Base stack + 30xxx publish |
