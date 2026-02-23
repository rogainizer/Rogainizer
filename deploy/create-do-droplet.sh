#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DEFAULT_CLOUD_INIT_FILE="$SCRIPT_DIR/digitalocean-cloud-init-autodeploy.yaml"

DO_API_BASE_URL="https://api.digitalocean.com/v2"

DROPLET_NAME="rogainizer-prod"
DROPLET_REGION="syd1"
DROPLET_SIZE="s-1vcpu-1gb"
DROPLET_IMAGE="ubuntu-22-04-x64"
DROPLET_TAGS="rogainizer"
DO_SSH_KEY_IDS=""
DO_PROJECT_ID=""
DO_VPC_UUID=""
DO_BACKUPS="false"
DO_IPV6="false"
DO_MONITORING="true"
CLOUD_INIT_FILE="$DEFAULT_CLOUD_INIT_FILE"
WAIT_FOR_IP="true"
PASSWORD_LOGIN_USER=""
PASSWORD_LOGIN_PASSWORD=""

usage() {
  cat <<'EOF'
Create a DigitalOcean droplet via API.

Required environment variables:
  DO_API_TOKEN   DigitalOcean personal access token

Optional environment variables:
  DO_SSH_KEY_IDS Comma-separated SSH key IDs or fingerprints (recommended)

Options:
  --name <value>        Droplet name (default: rogainizer-prod)
  --region <value>      Region slug (default: syd1)
  --size <value>        Size slug (default: s-1vcpu-1gb)
  --image <value>       Image slug (default: ubuntu-22-04-x64)
  --tags <csv>          Comma-separated tags (default: rogainizer)
  --ssh-keys <csv>      Comma-separated SSH key IDs/fingerprints
  --project-id <value>  Optional project UUID to assign droplet
  --vpc-uuid <value>    Optional VPC UUID
  --backups <true|false>
  --ipv6 <true|false>
  --monitoring <true|false>
  --cloud-init <file>   Cloud-init file path (default: deploy/digitalocean-cloud-init-autodeploy.yaml)
  --password-user <v>   Enable SSH password login for this Linux user
  --password-pass <v>   Password for --password-user (avoid shell history leaks)
  --wait <true|false>   Wait for public IPv4 and print it (default: true)
  -h, --help            Show this help

Example:
  DO_API_TOKEN=... ./deploy/create-do-droplet.sh \
    --name rogainizer-prod \
    --region syd1 \
    --ssh-keys "12345678"
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

parse_bool() {
  local value="${1:-}"
  case "$value" in
    true|false) printf "%s" "$value" ;;
    *)
      echo "Invalid boolean value: $value (expected true or false)"
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      DROPLET_NAME="${2:-}"; shift 2 ;;
    --region)
      DROPLET_REGION="${2:-}"; shift 2 ;;
    --size)
      DROPLET_SIZE="${2:-}"; shift 2 ;;
    --image)
      DROPLET_IMAGE="${2:-}"; shift 2 ;;
    --tags)
      DROPLET_TAGS="${2:-}"; shift 2 ;;
    --ssh-keys)
      DO_SSH_KEY_IDS="${2:-}"; shift 2 ;;
    --project-id)
      DO_PROJECT_ID="${2:-}"; shift 2 ;;
    --vpc-uuid)
      DO_VPC_UUID="${2:-}"; shift 2 ;;
    --backups)
      DO_BACKUPS="$(parse_bool "${2:-}")"; shift 2 ;;
    --ipv6)
      DO_IPV6="$(parse_bool "${2:-}")"; shift 2 ;;
    --monitoring)
      DO_MONITORING="$(parse_bool "${2:-}")"; shift 2 ;;
    --cloud-init)
      CLOUD_INIT_FILE="${2:-}"; shift 2 ;;
    --password-user)
      PASSWORD_LOGIN_USER="${2:-}"; shift 2 ;;
    --password-pass)
      PASSWORD_LOGIN_PASSWORD="${2:-}"; shift 2 ;;
    --wait)
      WAIT_FOR_IP="$(parse_bool "${2:-}")"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

require_command curl
require_command jq

if [[ -z "${DO_API_TOKEN:-}" ]]; then
  echo "DO_API_TOKEN is required."
  exit 1
fi

if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
  echo "Cloud-init file not found: $CLOUD_INIT_FILE"
  exit 1
fi

if [[ -n "$PASSWORD_LOGIN_USER" || -n "$PASSWORD_LOGIN_PASSWORD" ]]; then
  if [[ -z "$PASSWORD_LOGIN_USER" || -z "$PASSWORD_LOGIN_PASSWORD" ]]; then
    echo "Both --password-user and --password-pass must be provided together."
    exit 1
  fi

  if [[ "$PASSWORD_LOGIN_USER" =~ [:[:space:]] ]]; then
    echo "--password-user must not contain spaces or ':'"
    exit 1
  fi

  if [[ "$PASSWORD_LOGIN_PASSWORD" == *$'\n'* || "$PASSWORD_LOGIN_PASSWORD" == *$'\r'* ]]; then
    echo "--password-pass must not contain newlines"
    exit 1
  fi
fi

if [[ -z "$DROPLET_NAME" || -z "$DROPLET_REGION" || -z "$DROPLET_SIZE" || -z "$DROPLET_IMAGE" ]]; then
  echo "name, region, size, and image must be non-empty"
  exit 1
fi

echo "Creating droplet '$DROPLET_NAME' in region '$DROPLET_REGION'..."

user_data_content="$(cat "$CLOUD_INIT_FILE")"

if [[ -n "$PASSWORD_LOGIN_USER" ]]; then
  temp_cloud_init_file="$(mktemp)"
  {
    echo "#cloud-config"
    echo "ssh_pwauth: true"
    echo "chpasswd:"
    echo "  expire: false"
    echo "  list: |"
    printf "    %s:%s\n" "$PASSWORD_LOGIN_USER" "$PASSWORD_LOGIN_PASSWORD"
    echo
    sed '1{/^#cloud-config[[:space:]]*$/d;}' "$CLOUD_INIT_FILE"
  } > "$temp_cloud_init_file"

  user_data_content="$(cat "$temp_cloud_init_file")"
  rm -f "$temp_cloud_init_file"
fi

payload="$(jq -n \
  --arg name "$DROPLET_NAME" \
  --arg region "$DROPLET_REGION" \
  --arg size "$DROPLET_SIZE" \
  --arg image "$DROPLET_IMAGE" \
  --arg tags "$DROPLET_TAGS" \
  --arg sshKeys "$DO_SSH_KEY_IDS" \
  --arg userData "$user_data_content" \
  --argjson backups "$DO_BACKUPS" \
  --argjson ipv6 "$DO_IPV6" \
  --argjson monitoring "$DO_MONITORING" \
  --arg projectId "$DO_PROJECT_ID" \
  --arg vpcUuid "$DO_VPC_UUID" '
  {
    name: $name,
    region: $region,
    size: $size,
    image: $image,
    user_data: $userData,
    backups: $backups,
    ipv6: $ipv6,
    monitoring: $monitoring,
    tags: ($tags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
  }
  + (if ($sshKeys | length) > 0 then { ssh_keys: ($sshKeys | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) } else {} end)
  + (if ($vpcUuid | length) > 0 then { vpc_uuid: $vpcUuid } else {} end)
')"

response="$(curl -sS -X POST "$DO_API_BASE_URL/droplets" \
  -H "Authorization: Bearer $DO_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$payload")"

if ! echo "$response" | jq -e '.droplet.id' >/dev/null 2>&1; then
  echo "DigitalOcean API returned an error:"
  echo "$response" | jq . 2>/dev/null || echo "$response"
  exit 1
fi

droplet_id="$(echo "$response" | jq -r '.droplet.id')"
echo "Droplet created. ID: $droplet_id"

if [[ -n "$DO_PROJECT_ID" ]]; then
  assign_payload="$(jq -n --argjson id "$droplet_id" '{ resources: ["do:droplet:" + ($id|tostring)] }')"
  assign_response="$(curl -sS -X POST "$DO_API_BASE_URL/projects/$DO_PROJECT_ID/resources" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$assign_payload")"

  if echo "$assign_response" | jq -e '.links.self' >/dev/null 2>&1; then
    echo "Assigned droplet to project: $DO_PROJECT_ID"
  else
    echo "Warning: failed to assign droplet to project."
    echo "$assign_response" | jq . 2>/dev/null || echo "$assign_response"
  fi
fi

if [[ "$WAIT_FOR_IP" == "true" ]]; then
  echo "Waiting for public IPv4 assignment..."

  ip_address=""
  for _ in $(seq 1 30); do
    details="$(curl -sS -X GET "$DO_API_BASE_URL/droplets/$droplet_id" -H "Authorization: Bearer $DO_API_TOKEN")"
    ip_address="$(echo "$details" | jq -r '.droplet.networks.v4[]? | select(.type == "public") | .ip_address' | head -n 1)"

    if [[ -n "$ip_address" && "$ip_address" != "null" ]]; then
      break
    fi

    sleep 5
  done

  if [[ -n "$ip_address" && "$ip_address" != "null" ]]; then
    echo "Public IPv4: $ip_address"
  else
    echo "Public IPv4 not available yet. Check DigitalOcean control panel for droplet ID $droplet_id."
  fi
fi

echo "Done."
