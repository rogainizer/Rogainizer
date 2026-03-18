#!/usr/bin/env bash
set -euo pipefail

ENV_FILE_INPUT="${1:-.env.production}"
COMPOSE_FILE_INPUT="${2:-docker-compose.prod.yml}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$ENV_FILE_INPUT" = /* ]]; then
  ENV_FILE="$ENV_FILE_INPUT"
else
  ENV_FILE="$REPO_ROOT/$ENV_FILE_INPUT"
fi

if [[ "$COMPOSE_FILE_INPUT" = /* ]]; then
  COMPOSE_FILE="$COMPOSE_FILE_INPUT"
else
  COMPOSE_FILE="$REPO_ROOT/$COMPOSE_FILE_INPUT"
fi

TUNING_FILE="$REPO_ROOT/deploy/mysql/99-rogainizer-small-vm.cnf"
CONTAINER_TUNING_FILE="/etc/mysql/conf.d/99-rogainizer-small-vm.cnf"
DB_SERVICE="db"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Usage: $0 [env-file] [compose-file]"
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Missing compose file: $COMPOSE_FILE"
  echo "Usage: $0 [env-file] [compose-file]"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not on PATH"
  exit 1
fi

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

mysql_scalar() {
  local sql="$1"
  compose exec -T "$DB_SERVICE" sh -lc 'exec mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD"' <<< "$sql"
}

normalize_scalar() {
  printf "%s" "$1" | tr -d '\r\n'
}

echo "Writing MySQL small-VM tuning file: $TUNING_FILE"
install -d "$(dirname "$TUNING_FILE")"
cat > "$TUNING_FILE" <<'EOF'
[mysqld]
innodb_buffer_pool_size = 134217728
max_connections = 25
table_open_cache = 128
thread_cache_size = 4
tmp_table_size = 16777216
max_heap_table_size = 16777216
innodb_stats_on_metadata = OFF
performance_schema = OFF
EOF

echo "Ensuring MySQL service is running"
compose up -d "$DB_SERVICE"

echo "Restarting MySQL service so startup-only settings are applied"
compose restart "$DB_SERVICE"

ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if compose exec -T "$DB_SERVICE" sh -lc 'mysqladmin ping -h localhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 3
done

if [[ "$ready" -ne 1 ]]; then
  echo "MySQL did not become ready after restart"
  exit 1
fi

failures=0

check_setting() {
  local name="$1"
  local expected="$2"
  local sql="$3"
  local actual

  actual="$(normalize_scalar "$(mysql_scalar "$sql")")"

  if [[ "$actual" == "$expected" ]]; then
    echo "PASS ${name}=${actual}"
  else
    echo "FAIL ${name} expected=${expected} actual=${actual}"
    failures=$((failures + 1))
  fi
}

echo "Verifying MySQL small-VM settings"
check_setting "innodb_buffer_pool_size" "134217728" "SELECT @@GLOBAL.innodb_buffer_pool_size;"
check_setting "max_connections" "25" "SELECT @@GLOBAL.max_connections;"
check_setting "table_open_cache" "128" "SELECT @@GLOBAL.table_open_cache;"
check_setting "thread_cache_size" "4" "SELECT @@GLOBAL.thread_cache_size;"
check_setting "tmp_table_size" "16777216" "SELECT @@GLOBAL.tmp_table_size;"
check_setting "max_heap_table_size" "16777216" "SELECT @@GLOBAL.max_heap_table_size;"
check_setting "innodb_stats_on_metadata" "OFF" "SELECT IF(@@GLOBAL.innodb_stats_on_metadata = 1, 'ON', 'OFF');"
check_setting "performance_schema" "OFF" "SELECT IF(@@performance_schema = 1, 'ON', 'OFF');"

if [[ "$failures" -gt 0 ]]; then
  echo "MySQL tuning verification failed with ${failures} mismatch(es)."
  exit 1
fi

echo "MySQL tuning applied and verified."
echo "Persisted file on host: $TUNING_FILE"
echo "Mounted in container as: $CONTAINER_TUNING_FILE"
