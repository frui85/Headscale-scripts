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

if ! docker compose exec -T headscale headscale users list 2>/dev/null | grep -Eq "[[:space:]]${USER_NAME}([[:space:]]|$)"; then
  docker compose exec -T headscale headscale users create "$USER_NAME"
fi

args=(preauthkeys create --user "$USER_NAME" --expiration "$EXPIRATION")
if [[ "$REUSABLE" == "true" ]]; then
  args+=(--reusable)
fi

docker compose exec -T headscale headscale "${args[@]}"
