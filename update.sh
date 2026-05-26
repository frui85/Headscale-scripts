#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/docker-compose.d/headscale-server"
HEADSCALE_VERSION=""
SKIP_BACKUP="false"
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Update Headscale Docker Compose stack.

Usage:
  sudo bash update.sh [options]

Options:
  --install-dir DIR            Install directory. Default: /opt/docker-compose.d/headscale-server
  --headscale-version VERSION  Update HEADSCALE_VERSION in .env before pulling.
  --skip-backup                Do not run scripts/backup.sh before update.
  -h, --help                   Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --headscale-version)
      HEADSCALE_VERSION="${2:-}"
      shift 2
      ;;
    --skip-backup)
      SKIP_BACKUP="true"
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
  echo "ERROR: Install directory not found: $INSTALL_DIR" >&2
  exit 1
}

cd "$INSTALL_DIR"

if [[ "$SKIP_BACKUP" != "true" && -x "./scripts/backup.sh" ]]; then
  ./scripts/backup.sh --install-dir "$INSTALL_DIR"
fi

if [[ -n "$HEADSCALE_VERSION" ]]; then
  if grep -q '^HEADSCALE_VERSION=' .env; then
    sed -i.bak "s/^HEADSCALE_VERSION=.*/HEADSCALE_VERSION=${HEADSCALE_VERSION}/" .env
    rm -f .env.bak
  else
    printf '\nHEADSCALE_VERSION=%s\n' "$HEADSCALE_VERSION" >> .env
  fi
fi

docker compose pull
docker compose up -d
docker compose ps

if [[ -x "./scripts/healthcheck.sh" ]]; then
  ./scripts/healthcheck.sh --install-dir "$INSTALL_DIR"
fi
