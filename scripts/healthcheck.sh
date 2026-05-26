#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${HEADSCALE_INSTALL_DIR:-/opt/docker-compose.d/headscale-server}"

usage() {
  cat <<'EOF'
Check Headscale stack health.

Usage:
  ./scripts/healthcheck.sh [--install-dir DIR]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
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

cd "$INSTALL_DIR"

echo "== docker compose ps =="
docker compose ps

echo
echo "== headscale users =="
docker compose exec -T headscale headscale users list

echo
echo "== headscale nodes =="
docker compose exec -T headscale headscale nodes list || true

echo
echo "== caddy certificate directory =="
if [[ -d "./certs/caddy/certificates" ]]; then
  find ./certs/caddy/certificates -maxdepth 3 -type f | sort
else
  echo "No Caddy certificates found yet. Check DNS, TCP 80/443, and Caddy logs."
fi
