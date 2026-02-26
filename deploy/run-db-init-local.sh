#!/usr/bin/env bash
set -euo pipefail

# Runs the backend db:init script against a locally reachable database (no Docker)
# Usage: ./deploy/run-db-init-local.sh
# Ensure your local environment has DB_HOST/DB_USER/DB_PASSWORD/DB_NAME exported
# or defined in a .env file loaded before invoking this script.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/deploy}"

cd "${PROJECT_ROOT}/backend"

echo "Running backend db:init locally..."
npm run db:init

echo "Database initialization finished."
