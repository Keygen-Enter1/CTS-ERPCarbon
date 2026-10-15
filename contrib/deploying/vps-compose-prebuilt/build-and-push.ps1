# Local Windows: build production images and push to a registry.
#   $env:REGISTRY = "ghcr.io/myorg/carbon"
#   $env:TAG = "v1.0.0"
#   .\build-and-push.ps1
param(
  [string]$Registry = $env:REGISTRY,
  [string]$Tag = $(if ($env:TAG) { $env:TAG } else { "latest" })
)

$ErrorActionPreference = "Stop"
if (-not $Registry) {
  Write-Error "Set `$env:REGISTRY (e.g. ghcr.io/myorg/carbon) or pass -Registry"
}

$Root = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$erp = "${Registry}/erp:${Tag}"
$mes = "${Registry}/mes:${Tag}"
$bootstrap = "${Registry}/bootstrap:${Tag}"

Write-Host "Building ERP -> $erp"
docker build --build-arg APP=erp -t $erp $Root
Write-Host "Building MES -> $mes"
docker build --build-arg APP=mes -t $mes $Root
Write-Host "Building bootstrap -> $bootstrap"
docker build --target bootstrap -t $bootstrap $Root

Write-Host "Pushing..."
docker push $erp
docker push $mes
docker push $bootstrap

Write-Host @"

Set on the VPS (.env):

CARBON_IMAGE_ERP=$erp
CARBON_IMAGE_MES=$mes
CARBON_IMAGE_BOOTSTRAP=$bootstrap

Then on server: git pull && ./deploy-server.sh
"@
