#!/usr/bin/env bash
set -euo pipefail

# Restart all containers defined in docker-compose.prod.yml
# Usage: ./deploy/restart-prod.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/deploy}"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.prod.yml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Unable to locate docker-compose.prod.yml at ${COMPOSE_FILE}" >&2
  exit 1
fi

cd "${PROJECT_ROOT}"

echo "[1/3] Pulling latest container images..."
docker compose -f "${COMPOSE_FILE}" pull

echo "[2/3] Stopping existing containers..."
docker compose -f "${COMPOSE_FILE}" down

echo "[3/3] Starting containers in detached mode..."
docker compose -f "${COMPOSE_FILE}" up -d --build --remove-orphans

echo "Containers restarted successfully."
