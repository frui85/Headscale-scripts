#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${HEADSCALE_INSTALL_DIR:-/opt/docker-compose.d/headscale-server}"
USER_NAME=""
EXPIRATION="24h"
REUSABLE="false"
EPHEMERAL="false"

usage() {
  cat <<'EOF'
Generate a client onboarding package.

Usage:
  ./scripts/onboard.sh --user USERNAME [options]

Options:
  --install-dir DIR   Install directory. Default: /opt/docker-compose.d/headscale-server
  --user USERNAME     Headscale user to create/use.
  --expiration VALUE  Auth key expiration. Default: 24h
  --reusable          Generate a reusable auth key. Default is single-use.
  --ephemeral         Generate an ephemeral auth key.
  -h, --help          Show this help.

Examples:
  ./scripts/onboard.sh --user fr-mbp
  ./scripts/onboard.sh --user temp-iphone --ephemeral --expiration 2h
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
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
    --reusable)
      REUSABLE="true"
      shift
      ;;
    --ephemeral)
      EPHEMERAL="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$USER_NAME" ]] || die "--user is required"
[[ -d "$INSTALL_DIR" ]] || die "Install directory not found: $INSTALL_DIR"

cd "$INSTALL_DIR"

server_url="$(sed -n 's/^DOMAIN=//p' .env | head -n 1)"
[[ -n "$server_url" ]] || die "DOMAIN is missing in ${INSTALL_DIR}/.env"
server_url="https://${server_url}"

gen_args=(--user "$USER_NAME" --expiration "$EXPIRATION")
if [[ "$REUSABLE" != "true" ]]; then
  gen_args+=(--single-use)
fi
if [[ "$EPHEMERAL" == "true" ]]; then
  gen_args+=(--ephemeral)
fi

auth_key="$(./scripts/genkey.sh "${gen_args[@]}")"

cat <<EOF
User: ${USER_NAME}
Server: ${server_url}
Auth key: ${auth_key}
Expiration: ${EXPIRATION}
Reusable: ${REUSABLE}
Ephemeral: ${EPHEMERAL}

Linux:
  sudo tailscale up --login-server ${server_url} --authkey ${auth_key}

Windows PowerShell:
  tailscale up --login-server ${server_url} --authkey ${auth_key}

macOS CLI:
  tailscale up --login-server=${server_url} --authkey=${auth_key}

Android/iOS:
  1. Add custom/alternate control server: ${server_url}
  2. Choose auth key login if the app shows the option.
  3. Paste the auth key above.

Logout:
  tailscale logout

Server cleanup:
  ./scripts/cleanup.sh --apply --expired --delete-empty-users
EOF
