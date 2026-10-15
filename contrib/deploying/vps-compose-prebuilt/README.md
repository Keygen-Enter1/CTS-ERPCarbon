# VPS Docker Compose — prebuilt images

Deploy Carbon on a **single Linux VPS** with `docker compose`. **Production images are built on your machine** (or CI), pushed to a container registry, and **pulled on the server** — the VPS does not run `docker build`.

Git carries **source + this compose folder**, not build artifacts. Only Docker images carry the compiled ERP/MES bundles.

## Flow

```text
[Local / CI]  build-and-push.sh  →  container registry
[Git]         push repo (compose, .env.example, migrations in tree)
[VPS]         git clone → .env + secrets → deploy-server.sh (pull + up + migrate)
```

## 1. Local — build & push images

From the **repo root** (needs Docker, ~8 GB RAM for ERP):

**Linux / macOS / Git Bash:**

```bash
export REGISTRY=ghcr.io/YOUR_ORG/carbon   # or Docker Hub, private registry
export TAG=v1.0.0
./contrib/deploying/vps-compose-prebuilt/build-and-push.sh
```

**Windows PowerShell:**

```powershell
$env:REGISTRY = "ghcr.io/YOUR_ORG/carbon"
$env:TAG = "v1.0.0"
.\contrib\deploying\vps-compose-prebuilt\build-and-push.ps1
```

Log in first: `docker login ghcr.io` (or your registry).

## 2. Git — what to publish

Push the normal Carbon repository (migrations, Kong config, Caddyfile, this folder). Do **not** commit:

- `.env` on the server
- `secrets/*`
- Docker images

## 3. VPS — first-time setup

Requirements: Docker Engine + Compose plugin, DNS for `erp` / `mes` / `api` hostnames, ports 80/443 open.

```bash
sudo git clone https://github.com/YOUR_ORG/CTS-ERPCarbon.git /opt/carbon
cd /opt/carbon/contrib/deploying/vps-compose-prebuilt

cp .env.example .env
# Edit .env: CARBON_REPO, domains, CARBON_IMAGE_* from build-and-push output

./init-secrets.sh
# Edit secrets/smtp_password (and OAuth in .env if used)

chmod +x deploy-server.sh init-secrets.sh
./deploy-server.sh
```

`CARBON_REPO=/opt/carbon` must be the **full checkout** (bind-mounts for Caddy, Kong, edge functions, Postgres init scripts). No compile step on the server — only config from git.

## 4. Updates

**Local** (after code changes):

```bash
export TAG=v1.0.1
./contrib/deploying/vps-compose-prebuilt/build-and-push.sh
```

**VPS:**

```bash
cd /opt/carbon
git pull
cd contrib/deploying/vps-compose-prebuilt
# Bump CARBON_IMAGE_* tags in .env if needed
./deploy-server.sh
```

## Files

| File | Role |
|------|------|
| `docker-compose.yml` | Full stack; `image:` only (no `build:`) |
| `.env.example` | Public config template |
| `secrets/` | Passwords & keys (gitignored) |
| `init-secrets.sh` | Generate secret files |
| `build-and-push.sh` / `.ps1` | Local prod build + registry push |
| `deploy-server.sh` | Pull, `up`, migrations |
| `scripts/swarm-to-compose.mjs` | Regenerate compose from Swarm template |

## Alternative: save/load without a registry

```bash
docker save carbon/erp:tag carbon/mes:tag carbon/bootstrap:tag | gzip > carbon-images.tar.gz
# scp to VPS
docker load < carbon-images.tar.gz
# Set CARBON_IMAGE_* to local tags in .env
```

## Ports already in use on the VPS (e.g. another nginx on :443)

Carbon’s own Caddy wants **80/443**. If those are taken, **do not run Carbon’s `caddy` service** and publish the **30xxx** ports (same idea as local dev):

| Host port | Service |
|-----------|---------|
| 30000 | ERP |
| 30001 | MES |
| 30003 | Supabase API (Kong) |

Postgres (30002), Redis, Inngest, etc. stay **internal only** — do not expose them publicly.

```bash
docker compose -f docker-compose.yml -f docker-compose.publish-30xxx.yml --scale caddy=0 up -d
docker compose -f docker-compose.yml -f docker-compose.publish-30xxx.yml --profile migrate run --rm migrate
```

Point your **existing** reverse proxy at `127.0.0.1:30000`, `:30001`, `:30003` with three hostnames.

**SmartSite production (fixed domains):** see [`environments/smartsite/README.md`](environments/smartsite/README.md) — `erpcarbon.smartsite.vn`, `mescarbon.smartsite.vn`, `apicarbon.smartsite.vn`.

Carbon needs **three URLs** (ERP, MES, API) for auth and cookies — one domain alone is not enough unless you add custom routing (unsupported out of the box).

## Docs

Full production checklist: [Self-hosting with Docker + Caddy](https://docs.carbon.ms/docs/platform/self-hosting/docker-caddy) (Swarm variant; same services, different orchestrator).
