#!/usr/bin/env bash
# Local machine: build production images and push to a registry (not on the VPS).
#
# Usage:
#   REGISTRY=registry.example.com/yourorg/carbon TAG=v1.0.0 ./build-and-push.sh
#
# Requires ~8 GB RAM for the ERP build (NODE_OPTIONS in Dockerfile).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
REGISTRY="${REGISTRY:?Set REGISTRY, e.g. ghcr.io/myorg/carbon}"
TAG="${TAG:-latest}"

erp="${REGISTRY}/erp:${TAG}"
mes="${REGISTRY}/mes:${TAG}"
bootstrap="${REGISTRY}/bootstrap:${TAG}"

echo "Building ERP → $erp"
docker build --build-arg APP=erp -t "$erp" "$ROOT"
echo "Building MES → $mes"
docker build --build-arg APP=mes -t "$mes" "$ROOT"
echo "Building bootstrap → $bootstrap"
docker build --target bootstrap -t "$bootstrap" "$ROOT"

echo "Pushing…"
docker push "$erp"
docker push "$mes"
docker push "$bootstrap"

cat <<EOF

Set on the VPS (.env):

CARBON_IMAGE_ERP=$erp
CARBON_IMAGE_MES=$mes
CARBON_IMAGE_BOOTSTRAP=$bootstrap

Then: git pull && ./deploy-server.sh
EOF
