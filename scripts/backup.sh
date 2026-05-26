#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${HEADSCALE_INSTALL_DIR:-/opt/docker-compose.d/headscale-server}"
BACKUP_DIR=""

usage() {
  cat <<'EOF'
Create a Headscale stack backup.

Usage:
  ./scripts/backup.sh [options]

Options:
  --install-dir DIR  Install directory. Default: /opt/docker-compose.d/headscale-server
  --backup-dir DIR   Backup output directory. Default: <install-dir>/backups
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR="${2:-}"
      shift 2
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

[[ -d "$INSTALL_DIR" ]] || {
  echo "ERROR: Install directory not found: $INSTALL_DIR" >&2
  exit 1
}

if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$INSTALL_DIR/backups"
fi

mkdir -p "$BACKUP_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
archive="$BACKUP_DIR/headscale-backup-${timestamp}.tar.gz"

tar -czf "$archive" -C "$INSTALL_DIR" \
  .env \
  Caddyfile \
  docker-compose.yml \
  config \
  data \
  certs \
  caddy_config \
  client-connect.txt 2>/dev/null || {
    echo "ERROR: Backup failed" >&2
    exit 1
  }

echo "$archive"
