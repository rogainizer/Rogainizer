#!/usr/bin/env bash
# Load a SQL dump into the production database container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_FILE="${ROOT_DIR}/.env.production"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.prod.yml"
DB_SERVICE="db"

usage() {
  cat <<'USAGE'
Usage: deploy/load-sql-into-prod.sh /path/to/dump.sql[.gz]

Streams the provided SQL file into the production MySQL container using
credentials from .env.production. Supports plain .sql or gzip-compressed
.sql.gz files.
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

SQL_PATH="$1"
if [[ ! -f "${SQL_PATH}" ]]; then
  echo "SQL file not found: ${SQL_PATH}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}." >&2
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Missing ${COMPOSE_FILE}." >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

DB_NAME="${DB_NAME:-rogainizer}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
if [[ -z "${DB_PASSWORD}" ]]; then
  echo "DB_PASSWORD or MYSQL_ROOT_PASSWORD must be set in ${ENV_FILE}." >&2
  exit 1
fi

IMPORT_CMD="exec mysql -u\"${DB_USER}\" -p\"${DB_PASSWORD}\" \"${DB_NAME}\""
COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T "${DB_SERVICE}" sh -c "${IMPORT_CMD}")

if [[ "${SQL_PATH}" == *.gz ]]; then
  echo "Importing gzip-compressed dump into ${DB_NAME}..."
  gunzip -c "${SQL_PATH}" | "${COMPOSE[@]}"
else
  echo "Importing SQL dump into ${DB_NAME}..."
  cat "${SQL_PATH}" | "${COMPOSE[@]}"
fi

echo "Import complete."