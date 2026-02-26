# Runs the backend db:init script against a locally reachable database (no Docker)
# Usage: ./deploy/run-db-init-local.ps1
# Ensure your local environment has DB_HOST/DB_USER/DB_PASSWORD/DB_NAME available
# (via environment variables or a preloaded .env file) before invoking this script.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$backendPath = Join-Path $projectRoot 'backend'

Write-Host "Running backend db:init locally..."

Push-Location $backendPath
try {
    $npm = Get-Command npm -ErrorAction Stop
    & $npm.Path run db:init
    Write-Host "Database initialization finished."
}
finally {
    Pop-Location
}
