#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${HEADSCALE_INSTALL_DIR:-/opt/docker-compose.d/headscale-server}"
USER_NAME="default"
EXPIRATION="24h"
REUSABLE="true"

usage() {
  cat <<'EOF'
Generate a Headscale preauth key.

Usage:
  ./scripts/genkey.sh [options]

Options:
  --install-dir DIR   Install directory. Default: /opt/docker-compose.d/headscale-server
  --user USER         Headscale user. Default: default
  --expiration VALUE  Key expiration. Default: 24h
  --single-use        Generate a single-use key instead of reusable.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --expiration)
      EXPIRATION="${2:-}"
      shift 2
      ;;
    --single-use)
      REUSABLE="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

cd "$INSTALL_DIR"

extract_user_id() {
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}.*/\1/p' | head -n 1
}

users_json="$(docker compose exec -T headscale headscale users list --name "$USER_NAME" -o json 2>/dev/null || true)"
user_id="$(printf '%s\n' "$users_json" | extract_user_id)"

if [[ -z "$user_id" ]]; then
  docker compose exec -T headscale headscale users create "$USER_NAME" >/dev/null
  users_json="$(docker compose exec -T headscale headscale users list --name "$USER_NAME" -o json)"
  user_id="$(printf '%s\n' "$users_json" | extract_user_id)"
fi

[[ -n "$user_id" ]] || {
  echo "ERROR: Unable to resolve Headscale user ID for '${USER_NAME}'" >&2
  exit 1
}

args=(preauthkeys create --user "$user_id" --expiration "$EXPIRATION")
if [[ "$REUSABLE" == "true" ]]; then
  args+=(--reusable)
fi

docker compose exec -T headscale headscale "${args[@]}" | tr -d '\r' | tail -n 1
