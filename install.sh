#!/usr/bin/env bash
set -Eeuo pipefail

HEADSCALE_VERSION="0.27.1"
INSTALL_DIR="/opt/headscale"
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
  --install-dir DIR            Install directory. Default: /opt/headscale
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
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  printf '\n==> %s\n' "$*"
}

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
    if [[ ! -f "$0" ]]; then
      die "Please rerun piped installs with sudo, for example: curl -fsSL <url> | sudo bash -s -- --domain hs.example.com"
    fi
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    fi
    die "Please run as root or install sudo"
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

write_stack_files() {
  log "Writing stack files to ${INSTALL_DIR}"
  install -d -m 0755 "$INSTALL_DIR" "$INSTALL_DIR/config" "$INSTALL_DIR/data" "$INSTALL_DIR/caddy_data" "$INSTALL_DIR/caddy_config"

  cat > "${INSTALL_DIR}/.env" <<EOF
HEADSCALE_VERSION=${HEADSCALE_VERSION}
DOMAIN=${DOMAIN}
TZ=${TZ_VALUE}
EOF

  cat > "${INSTALL_DIR}/docker-compose.yml" <<'EOF'
name: headscale-derp

services:
  headscale:
    image: ghcr.io/juanfont/headscale:${HEADSCALE_VERSION}
    container_name: headscale
    restart: unless-stopped
    command: serve
    environment:
      TZ: ${TZ}
    volumes:
      - ./config:/etc/headscale
      - ./data:/var/lib/headscale
    ports:
      - "3478:3478/udp"

  caddy:
    image: caddy:2-alpine
    container_name: headscale-caddy
    restart: unless-stopped
    environment:
      DOMAIN: ${DOMAIN}
    depends_on:
      - headscale
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy_data:/data
      - ./caddy_config:/config
EOF

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

  local derp_ip_lines=""
  if [[ -n "$DERP_IPV4" ]]; then
    derp_ip_lines="${derp_ip_lines}    ipv4: ${DERP_IPV4}"$'\n'
  fi
  if [[ -n "$DERP_IPV6" ]]; then
    derp_ip_lines="${derp_ip_lines}    ipv6: ${DERP_IPV6}"$'\n'
  fi

  local derp_urls_block="  urls: []"
  local derp_auto_update="  auto_update_enabled: false"
  if [[ "$INCLUDE_OFFICIAL_DERP" == "true" ]]; then
    derp_urls_block=$'  urls:\n    - https://controlplane.tailscale.com/derpmap/default'
    derp_auto_update="  auto_update_enabled: true"
  fi

  cat > "${INSTALL_DIR}/config/config.yaml" <<EOF
server_url: https://${DOMAIN}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

trusted_proxies:
  - 127.0.0.1/32
  - 10.0.0.0/8
  - 172.16.0.0/12
  - 192.168.0.0/16

noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

derp:
  server:
    enabled: true
    region_id: 999
    region_code: "headscale"
    region_name: "Headscale Embedded DERP"
    verify_clients: true
    stun_listen_addr: "0.0.0.0:3478"
    private_key_path: /var/lib/headscale/derp_server_private.key
    automatically_add_embedded_derp_region: true
${derp_ip_lines}${derp_urls_block}
  paths: []
${derp_auto_update}
  update_frequency: 3h

disable_check_updates: false

node:
  expiry: 0
  ephemeral:
    inactivity_timeout: 30m
  routes:
    ha:
      probe_interval: 10s
      probe_timeout: 5s

database:
  type: sqlite
  debug: false
  gorm:
    prepare_stmt: true
    parameterized_queries: true
    skip_err_record_not_found: true
    slow_threshold: 1000
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true
    wal_autocheckpoint: 1000

acme_url: https://acme-v02.api.letsencrypt.org/directory
acme_email: ""
tls_letsencrypt_hostname: ""
tls_letsencrypt_cache_dir: /var/lib/headscale/cache
tls_letsencrypt_challenge_type: HTTP-01
tls_letsencrypt_listen: ":http"
tls_cert_path: ""
tls_key_path: ""

log:
  level: info
  format: text

policy:
  mode: file
  path: /etc/headscale/acl.hujson

dns:
  magic_dns: true
  base_domain: ${BASE_DOMAIN}
  override_local_dns: true
  nameservers:
    global:
      - 1.1.1.1
      - 1.0.0.1
      - 2606:4700:4700::1111
      - 2606:4700:4700::1001
    split: {}
  search_domains: []
  extra_records: []

unix_socket: /var/lib/headscale/headscale.sock
unix_socket_permission: "0770"

logtail:
  enabled: false

taildrop:
  enabled: true

auto_update:
  enabled: false
EOF

  cat > "${INSTALL_DIR}/config/acl.hujson" <<'EOF'
{
  "groups": {},
  "tagOwners": {},
  "acls": [
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*:*"]
    }
  ],
  "ssh": [],
  "autoApprovers": {
    "routes": {},
    "exitNode": []
  }
}
EOF
}

compose() {
  docker compose -f "${INSTALL_DIR}/docker-compose.yml" --env-file "${INSTALL_DIR}/.env" "$@"
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
  if ! compose exec -T headscale headscale users list 2>/dev/null | grep -Eq "[[:space:]]${HEADSCALE_USER}([[:space:]]|$)"; then
    compose exec -T headscale headscale users create "$HEADSCALE_USER"
  fi

  local authkey=""
  if [[ "$CREATE_AUTHKEY" == "true" ]]; then
    log "Creating reusable preauth key"
    authkey="$(compose exec -T headscale headscale preauthkeys create --user "$HEADSCALE_USER" --reusable --expiration "$AUTHKEY_EXPIRATION" | tr -d '\r')"
  fi

  write_client_guide "$authkey"
}

write_client_guide() {
  local authkey="${1:-}"
  cat > "${INSTALL_DIR}/client-connect.txt" <<EOF
Headscale URL:
  https://${DOMAIN}

Server files:
  ${INSTALL_DIR}/docker-compose.yml
  ${INSTALL_DIR}/config/config.yaml
  ${INSTALL_DIR}/config/acl.hujson

Useful server commands:
  cd ${INSTALL_DIR}
  docker compose ps
  docker compose logs -f headscale
  docker compose exec headscale headscale users list
  docker compose exec headscale headscale nodes list
  docker compose exec headscale headscale preauthkeys create --user ${HEADSCALE_USER} --reusable --expiration 24h

Client connection:
  Linux:
    tailscale up --login-server https://${DOMAIN} --authkey <AUTH_KEY>

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
User:          ${HEADSCALE_USER}
Client guide:  ${INSTALL_DIR}/client-connect.txt

Next checks:
  cd ${INSTALL_DIR}
  docker compose ps
  docker compose logs -f caddy
  docker compose logs -f headscale

Make sure TCP 80/443 and UDP 3478 are reachable from the Internet.
EOF
}

main() {
  parse_args "$@"
  validate_args
  ensure_root "$@"
  install_docker_if_needed
  write_stack_files
  start_stack
  wait_for_headscale
  create_user_and_key
  print_summary
}

main "$@"
