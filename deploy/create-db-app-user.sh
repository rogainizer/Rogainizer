#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.production}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Usage: $0 [env-file]"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

required_vars=(MYSQL_ROOT_PASSWORD DB_NAME DB_USER DB_PASSWORD)
for variable_name in "${required_vars[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing required variable in $ENV_FILE: $variable_name"
    exit 1
  fi
done

if [[ "$DB_USER" == "root" ]]; then
  echo "DB_USER is 'root'. Set DB_USER to a dedicated app account first (for example: rogainizer_app)."
  exit 1
fi

if ! [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Invalid DB_NAME '$DB_NAME'. Only letters, numbers, and underscores are allowed."
  exit 1
fi

if ! [[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Invalid DB_USER '$DB_USER'. Only letters, numbers, and underscores are allowed."
  exit 1
fi

escape_sql_string() {
  printf "%s" "$1" | sed "s/'/''/g"
}

escaped_db_user="$(escape_sql_string "$DB_USER")"
escaped_db_password="$(escape_sql_string "$DB_PASSWORD")"

sql="
CREATE USER IF NOT EXISTS '${escaped_db_user}'@'%' IDENTIFIED BY '${escaped_db_password}';
ALTER USER '${escaped_db_user}'@'%' IDENTIFIED BY '${escaped_db_password}';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${DB_NAME}\`.* TO '${escaped_db_user}'@'%';
FLUSH PRIVILEGES;
SHOW GRANTS FOR '${escaped_db_user}'@'%';
"

echo "Creating/updating MySQL app user '$DB_USER' with least-privilege grants on database '$DB_NAME'..."
printf "%s" "$sql" | docker compose --env-file "$ENV_FILE" -f docker-compose.prod.yml exec -T db sh -lc 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'

echo "Done. App user '$DB_USER' is ready."
