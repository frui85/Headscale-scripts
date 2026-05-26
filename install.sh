#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ARCHIVE_URL="https://github.com/frui85/Headscale-scripts/archive/refs/heads/main.tar.gz"
INSTALL_DIR="/opt/docker-compose.d/headscale-server"
HEADSCALE_VERSION="0.27.1"
DOMAIN=""
ACME_EMAIL=""
HEADSCALE_USER="default"
BASE_DOMAIN=""
TZ_VALUE="Asia/Shanghai"
AUTHKEY_EXPIRATION="24h"
CREATE_AUTHKEY="true"
INCLUDE_OFFICIAL_DERP="false"
SKIP_DOCKER_INSTALL="false"
DERP_IPV4=""
DERP_IPV6=""
SOURCE_DIR=""
TMP_SOURCE=""

usage() {
  cat <<'EOF'
Headscale + embedded DERP one-click installer

Usage:
  sudo bash install.sh --domain hs.example.com [options]

Required:
  --domain DOMAIN              Public HTTPS domain for Headscale.

Options:
  --email EMAIL                ACME email used by Caddy.
  --user USER                  Initial Headscale user. Default: default
  --base-domain DOMAIN         MagicDNS base domain. Default: tailnet.<domain>
  --install-dir DIR            Install directory. Default: /opt/docker-compose.d/headscale-server
  --headscale-version VERSION  Headscale container tag. Default: 0.27.1
  --timezone TZ                Container timezone. Default: Asia/Shanghai
  --authkey-expiration VALUE   Initial reusable preauth key expiry. Default: 24h
  --no-authkey                 Do not create an initial preauth key.
  --include-official-derp      Keep Tailscale official DERP map as fallback.
  --derp-ipv4 IP               Optional public IPv4 to publish in the DERP map.
  --derp-ipv6 IP               Optional public IPv6 to publish in the DERP map.
  --skip-docker-install        Fail if Docker or docker compose is missing.
  -h, --help                   Show this help.

Examples:
  sudo bash install.sh --domain hs.example.com --email admin@example.com --user fr
  curl -fsSL https://raw.githubusercontent.com/frui85/Headscale-scripts/main/install.sh \
    | sudo bash -s -- --domain hs.example.com --email admin@example.com

Required firewall/DNS:
  - DOMAIN A/AAAA record points to this server.
  - TCP 80 and 443 are open for HTTPS and ACME.
  - UDP 3478 is open for embedded DERP/STUN.

Reinstall:
  Re-run the same install command to refresh compose/config/scripts.
  Existing data, certificates, and backups under the install directory are preserved.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  printf '\n==> %s\n' "$*"
}

cleanup() {
  if [[ -n "$TMP_SOURCE" && -d "$TMP_SOURCE" ]]; then
    rm -rf "$TMP_SOURCE"
  fi
}
trap cleanup EXIT

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --email)
        ACME_EMAIL="${2:-}"
        shift 2
        ;;
      --user)
        HEADSCALE_USER="${2:-}"
        shift 2
        ;;
      --base-domain)
        BASE_DOMAIN="${2:-}"
        shift 2
        ;;
      --install-dir)
        INSTALL_DIR="${2:-}"
        shift 2
        ;;
      --headscale-version)
        HEADSCALE_VERSION="${2:-}"
        shift 2
        ;;
      --timezone)
        TZ_VALUE="${2:-}"
        shift 2
        ;;
      --authkey-expiration)
        AUTHKEY_EXPIRATION="${2:-}"
        shift 2
        ;;
      --no-authkey)
        CREATE_AUTHKEY="false"
        shift
        ;;
      --include-official-derp)
        INCLUDE_OFFICIAL_DERP="true"
        shift
        ;;
      --derp-ipv4)
        DERP_IPV4="${2:-}"
        shift 2
        ;;
      --derp-ipv6)
        DERP_IPV6="${2:-}"
        shift 2
        ;;
      --skip-docker-install)
        SKIP_DOCKER_INSTALL="true"
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
}

validate_args() {
  [[ -n "$DOMAIN" ]] || die "--domain is required"
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "--domain contains invalid characters"
  [[ "$DOMAIN" == *.* ]] || die "--domain must be a real FQDN, for example hs.example.com"
  [[ "$HEADSCALE_USER" =~ ^[A-Za-z0-9._-]+$ ]] || die "--user can only contain letters, digits, dot, underscore, and dash"
  [[ "$INSTALL_DIR" = /* ]] || die "--install-dir must be an absolute path"

  if [[ -z "$BASE_DOMAIN" ]]; then
    BASE_DOMAIN="tailnet.${DOMAIN}"
  fi

  [[ "$BASE_DOMAIN" != "$DOMAIN" ]] || die "--base-domain must differ from --domain"
}

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if [[ -f "${BASH_SOURCE[0]:-$0}" ]] && command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
    fi
    die "Please run with sudo, for example: curl -fsSL <url> | sudo bash -s -- --domain hs.example.com"
  fi
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

install_docker_if_needed() {
  if docker_ready; then
    return
  fi

  [[ "$SKIP_DOCKER_INSTALL" == "false" ]] || die "Docker or docker compose is missing"

  log "Installing Docker"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg docker.io docker-compose-plugin || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl docker docker-compose-plugin || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl docker docker-compose-plugin || true
  fi

  if ! docker_ready; then
    command -v curl >/dev/null 2>&1 || die "curl is required to install Docker"
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
  fi

  systemctl enable --now docker >/dev/null 2>&1 || true
  docker_ready || die "Docker installation did not provide 'docker compose'"
}

detect_source_dir() {
  local script_path="${BASH_SOURCE[0]:-$0}"
  local candidate=""

  download_source_archive() {
    command -v curl >/dev/null 2>&1 || die "curl is required to download install files"
    command -v tar >/dev/null 2>&1 || die "tar is required to unpack install files"

    log "Downloading install files from GitHub"
    TMP_SOURCE="$(mktemp -d)"
    curl -fsSL "$REPO_ARCHIVE_URL" -o "$TMP_SOURCE/repo.tar.gz"
    tar -xzf "$TMP_SOURCE/repo.tar.gz" --strip-components=1 -C "$TMP_SOURCE"
    SOURCE_DIR="$TMP_SOURCE"
  }

  if [[ -f "$script_path" ]]; then
    candidate="$(cd "$(dirname "$script_path")" && pwd)"
    if [[ -f "$candidate/docker-compose.yml" && -f "$candidate/config/config.yaml" ]]; then
      if [[ "$candidate" == "$INSTALL_DIR" ]]; then
        download_source_archive
        return
      fi
      SOURCE_DIR="$candidate"
      return
    fi
  fi

  if [[ -f "./docker-compose.yml" && -f "./config/config.yaml" ]]; then
    candidate="$(pwd)"
    if [[ "$candidate" == "$INSTALL_DIR" ]]; then
      download_source_archive
      return
    fi
    SOURCE_DIR="$candidate"
    return
  fi

  download_source_archive
}

copy_tree_file() {
  local src="$1"
  local dst="$2"

  if [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == "$(cd "$(dirname "$dst")" && pwd)/$(basename "$dst")" ]]; then
    return
  fi

  install -D -m 0644 "$src" "$dst"
}

write_env_file() {
  cat > "${INSTALL_DIR}/.env" <<EOF
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
HEADSCALE_VERSION=${HEADSCALE_VERSION}
TZ=${TZ_VALUE}
EOF
}

write_caddyfile() {
  if [[ -n "$ACME_EMAIL" ]]; then
    cat > "${INSTALL_DIR}/Caddyfile" <<EOF
{
    email ${ACME_EMAIL}
}

${DOMAIN} {
    encode zstd gzip
    reverse_proxy headscale:8080
}
EOF
  else
    cat > "${INSTALL_DIR}/Caddyfile" <<EOF
${DOMAIN} {
    encode zstd gzip
    reverse_proxy headscale:8080
}
EOF
  fi
}

render_config() {
  local config_path="${INSTALL_DIR}/config/config.yaml"

  sed -i.bak \
    -e "s|https://hs.example.com|https://${DOMAIN}|g" \
    -e "s|base_domain: tailnet.hs.example.com|base_domain: ${BASE_DOMAIN}|g" \
    "$config_path"
  rm -f "${config_path}.bak"

  if [[ "$INCLUDE_OFFICIAL_DERP" == "true" ]]; then
    awk '
      $0 == "  urls: []" {
        print "  urls:"
        print "    - https://controlplane.tailscale.com/derpmap/default"
        next
      }
      $0 == "  auto_update_enabled: false" {
        print "  auto_update_enabled: true"
        next
      }
      { print }
    ' "$config_path" > "${config_path}.tmp"
    mv "${config_path}.tmp" "$config_path"
  fi

  if [[ -n "$DERP_IPV4" || -n "$DERP_IPV6" ]]; then
    awk -v ipv4="$DERP_IPV4" -v ipv6="$DERP_IPV6" '
      { print }
      $0 ~ /automatically_add_embedded_derp_region: true/ {
        if (ipv4 != "") print "    ipv4: " ipv4
        if (ipv6 != "") print "    ipv6: " ipv6
      }
    ' "$config_path" > "${config_path}.tmp"
    mv "${config_path}.tmp" "$config_path"
  fi
}

write_stack_files() {
  log "Writing stack files to ${INSTALL_DIR}"
  install -d -m 0755 \
    "$INSTALL_DIR" \
    "$INSTALL_DIR/config" \
    "$INSTALL_DIR/data" \
    "$INSTALL_DIR/certs" \
    "$INSTALL_DIR/caddy_config" \
    "$INSTALL_DIR/backups" \
    "$INSTALL_DIR/scripts"

  copy_tree_file "$SOURCE_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
  copy_tree_file "$SOURCE_DIR/config/config.yaml" "$INSTALL_DIR/config/config.yaml"
  copy_tree_file "$SOURCE_DIR/config/derp.yaml" "$INSTALL_DIR/config/derp.yaml"
  copy_tree_file "$SOURCE_DIR/config/acl.hujson" "$INSTALL_DIR/config/acl.hujson"
  copy_tree_file "$SOURCE_DIR/scripts/healthcheck.sh" "$INSTALL_DIR/scripts/healthcheck.sh"
  copy_tree_file "$SOURCE_DIR/scripts/genkey.sh" "$INSTALL_DIR/scripts/genkey.sh"
  copy_tree_file "$SOURCE_DIR/scripts/backup.sh" "$INSTALL_DIR/scripts/backup.sh"
  copy_tree_file "$SOURCE_DIR/scripts/manage.sh" "$INSTALL_DIR/scripts/manage.sh"
  chmod +x "$INSTALL_DIR/scripts/"*.sh

  write_env_file
  write_caddyfile
  render_config
}

compose() {
  docker compose -f "${INSTALL_DIR}/docker-compose.yml" --env-file "${INSTALL_DIR}/.env" "$@"
}

extract_user_id() {
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}.*/\1/p' | head -n 1
}

resolve_headscale_user_id() {
  local user_name="$1"
  local users_json=""
  local user_id=""

  users_json="$(compose exec -T headscale headscale users list --name "$user_name" -o json 2>/dev/null || true)"
  user_id="$(printf '%s\n' "$users_json" | extract_user_id)"

  if [[ -z "$user_id" ]]; then
    compose exec -T headscale headscale users create "$user_name" >/dev/null
    users_json="$(compose exec -T headscale headscale users list --name "$user_name" -o json)"
    user_id="$(printf '%s\n' "$users_json" | extract_user_id)"
  fi

  [[ -n "$user_id" ]] || die "Unable to resolve Headscale user ID for '${user_name}'"
  printf '%s\n' "$user_id"
}

start_stack() {
  log "Starting Headscale and Caddy"
  compose up -d
}

wait_for_headscale() {
  log "Waiting for Headscale to become ready"
  for _ in $(seq 1 60); do
    if compose exec -T headscale headscale users list >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done

  compose ps || true
  compose logs --tail=120 headscale || true
  die "Headscale did not become ready"
}

create_user_and_key() {
  log "Ensuring Headscale user '${HEADSCALE_USER}' exists"
  local headscale_user_id=""
  headscale_user_id="$(resolve_headscale_user_id "$HEADSCALE_USER")"

  local authkey=""
  if [[ "$CREATE_AUTHKEY" == "true" ]]; then
    log "Creating reusable preauth key"
    authkey="$(compose exec -T headscale headscale preauthkeys create --user "$headscale_user_id" --reusable --expiration "$AUTHKEY_EXPIRATION" | tr -d '\r' | tail -n 1)"
  fi

  write_client_guide "$authkey"
}

write_client_guide() {
  local authkey="${1:-}"
  cat > "${INSTALL_DIR}/client-connect.txt" <<EOF
Headscale URL:
  https://${DOMAIN}

Install directory:
  ${INSTALL_DIR}

Useful server commands:
  cd ${INSTALL_DIR}
  docker compose ps
  docker compose logs -f headscale
  docker compose logs -f caddy
  ./scripts/healthcheck.sh
  ./scripts/manage.sh user list
  ./scripts/manage.sh node list
  ./scripts/genkey.sh --user ${HEADSCALE_USER}
  ./scripts/backup.sh

Client connection:
  Linux:
    sudo tailscale up --login-server https://${DOMAIN} --authkey <AUTH_KEY>

  Windows PowerShell:
    tailscale login --login-server https://${DOMAIN}

  macOS CLI:
    tailscale login --login-server=https://${DOMAIN}

  Android:
    Tailscale app -> Accounts -> three-dot menu -> Use an alternate server -> https://${DOMAIN}

  iOS:
    Tailscale app -> add account/custom control server -> https://${DOMAIN}

DERP verification from any connected desktop client:
  tailscale debug derp-map
  tailscale debug derp headscale

Caddy certificate storage:
  ${INSTALL_DIR}/certs/caddy/certificates
EOF

  if [[ -n "$authkey" ]]; then
    cat >> "${INSTALL_DIR}/client-connect.txt" <<EOF

Initial reusable auth key:
  ${authkey}
EOF
  fi
}

print_summary() {
  cat <<EOF

Install complete.

Headscale URL: https://${DOMAIN}
Install dir:   ${INSTALL_DIR}
Certs dir:     ${INSTALL_DIR}/certs
User:          ${HEADSCALE_USER}
Client guide:  ${INSTALL_DIR}/client-connect.txt

Next checks:
  cd ${INSTALL_DIR}
  docker compose ps
  ./scripts/healthcheck.sh

Make sure TCP 80/443 and UDP 3478 are reachable from the Internet.
EOF
}

main() {
  parse_args "$@"
  validate_args
  ensure_root "$@"
  install_docker_if_needed
  detect_source_dir
  write_stack_files
  start_stack
  wait_for_headscale
  create_user_and_key
  print_summary
}

main "$@"
