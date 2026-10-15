#!/usr/bin/env bash
# Build ERP/MES/bootstrap images on the VPS from a git checkout (no registry, no tar).
# Needs ~8 GB RAM free during the ERP build. Run from vps-compose-prebuilt/.
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TAG="${TAG:-smartsite-1}"

[ -f "$HERE/.env" ] && set -a && . "$HERE/.env" && set +a
ROOT="${CARBON_REPO:-$(cd "$HERE/../../.." && pwd)}"

[ -f "$ROOT/Dockerfile" ] || {
  echo "No Dockerfile at CARBON_REPO=$ROOT — set CARBON_REPO in .env" >&2
  exit 1
}

erp="carbon/erp:${TAG}"
mes="carbon/mes:${TAG}"
bootstrap="carbon/bootstrap:${TAG}"

echo "Building ERP (needs ~8 GB RAM) -> $erp"
docker build --build-arg APP=erp -t "$erp" "$ROOT"
echo "Building MES -> $mes"
docker build --build-arg APP=mes -t "$mes" "$ROOT"
echo "Building bootstrap -> $bootstrap"
docker build --target bootstrap -t "$bootstrap" "$ROOT"

cat <<EOF

Add to $HERE/.env:

CARBON_IMAGE_ERP=$erp
CARBON_IMAGE_MES=$mes
CARBON_IMAGE_BOOTSTRAP=$bootstrap

Then: bash ./environments/smartsite/deploy-smartsite.sh
EOF
