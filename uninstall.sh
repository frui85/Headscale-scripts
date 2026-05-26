#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/docker-compose.d/headscale-server"
PURGE="false"
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Uninstall Headscale stack.

Usage:
  sudo bash uninstall.sh [options]

Options:
  --install-dir DIR  Install directory. Default: /opt/docker-compose.d/headscale-server
  --purge            Delete the install directory after stopping containers.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --purge)
      PURGE="true"
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

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
fi

[[ -d "$INSTALL_DIR" ]] || {
  echo "Install directory not found: $INSTALL_DIR"
  exit 0
}

cd "$INSTALL_DIR"
docker compose down

if [[ "$PURGE" == "true" ]]; then
  rm -rf "$INSTALL_DIR"
  echo "Removed $INSTALL_DIR"
else
  echo "Containers stopped. Data preserved in $INSTALL_DIR"
  echo "Run with --purge only if you want to delete config, data, certs, and backups."
fi
