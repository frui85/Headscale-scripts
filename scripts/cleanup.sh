#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${HEADSCALE_INSTALL_DIR:-/opt/docker-compose.d/headscale-server}"
APPLY="false"
CLEAN_EXPIRED="true"
OFFLINE_HOURS=""
DELETE_EMPTY_USERS="false"
USER_PREFIX=""
PROTECT_USERS=("default" "tagged-devices")

usage() {
  cat <<'EOF'
Clean up Headscale nodes and empty users.

By default this script is a dry run. Add --apply to delete.

Usage:
  ./scripts/cleanup.sh [options]

Options:
  --install-dir DIR       Install directory. Default: /opt/docker-compose.d/headscale-server
  --apply                 Actually delete matching nodes/users.
  --expired               Delete expired nodes. Enabled by default.
  --no-expired            Do not delete expired nodes.
  --offline-hours HOURS   Delete offline nodes last seen more than HOURS ago.
  --delete-empty-users    Delete users with no remaining nodes.
  --user-prefix PREFIX    Only delete empty users whose username starts with PREFIX.
  --protect-user USER     Never delete this user. Can be repeated.
  -h, --help              Show this help.

Examples:
  ./scripts/cleanup.sh
  ./scripts/cleanup.sh --apply --expired
  ./scripts/cleanup.sh --apply --expired --delete-empty-users
  ./scripts/cleanup.sh --apply --offline-hours 24 --delete-empty-users --user-prefix temp-

Cron example:
  */10 * * * * cd /opt/docker-compose.d/headscale-server && ./scripts/cleanup.sh --apply --expired --delete-empty-users >> /var/log/headscale-cleanup.log 2>&1
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

trim() {
  local value="$*"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_protected_user() {
  local username="$1"
  local protected=""
  for protected in "${PROTECT_USERS[@]}"; do
    [[ "$username" == "$protected" ]] && return 0
  done
  return 1
}

delete_node() {
  local node_id="$1"
  local reason="$2"
  if [[ "$APPLY" == "true" ]]; then
    echo "Deleting node ${node_id}: ${reason}"
    docker compose exec -T headscale headscale --force nodes delete --identifier "$node_id"
  else
    echo "DRY-RUN delete node ${node_id}: ${reason}"
  fi
}

delete_user() {
  local user_id="$1"
  local username="$2"
  if [[ "$APPLY" == "true" ]]; then
    echo "Deleting empty user ${username} (${user_id})"
    docker compose exec -T headscale headscale --force users destroy --identifier "$user_id"
  else
    echo "DRY-RUN delete empty user ${username} (${user_id})"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --expired)
      CLEAN_EXPIRED="true"
      shift
      ;;
    --no-expired)
      CLEAN_EXPIRED="false"
      shift
      ;;
    --offline-hours)
      OFFLINE_HOURS="${2:-}"
      shift 2
      ;;
    --delete-empty-users)
      DELETE_EMPTY_USERS="true"
      shift
      ;;
    --user-prefix)
      USER_PREFIX="${2:-}"
      shift 2
      ;;
    --protect-user)
      PROTECT_USERS+=("${2:-}")
      shift 2
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

[[ -d "$INSTALL_DIR" ]] || die "Install directory not found: $INSTALL_DIR"
if [[ -n "$OFFLINE_HOURS" && ! "$OFFLINE_HOURS" =~ ^[0-9]+$ ]]; then
  die "--offline-hours must be a non-negative integer"
fi

cd "$INSTALL_DIR"

nodes_output="$(docker compose exec -T headscale headscale nodes list || true)"
now_epoch="$(date +%s)"

echo "Cleanup mode: $([[ "$APPLY" == "true" ]] && echo apply || echo dry-run)"

while IFS='|' read -r raw_id _raw_hostname _raw_name _raw_machine _raw_node raw_user _raw_ips _raw_ephemeral raw_last_seen _raw_expiration raw_connected raw_expired _rest; do
  node_id="$(trim "$raw_id")"
  [[ "$node_id" =~ ^[0-9]+$ ]] || continue

  username="$(trim "$raw_user")"
  last_seen="$(trim "$raw_last_seen")"
  connected="$(trim "$raw_connected")"
  expired="$(trim "$raw_expired")"

  if [[ "$CLEAN_EXPIRED" == "true" && "$expired" =~ ^(yes|true)$ ]]; then
    delete_node "$node_id" "expired user=${username}"
    continue
  fi

  if [[ -n "$OFFLINE_HOURS" && "$connected" == "offline" && "$last_seen" != "N/A" && -n "$last_seen" ]]; then
    if last_seen_epoch="$(date -d "$last_seen" +%s 2>/dev/null)"; then
      age_hours="$(( (now_epoch - last_seen_epoch) / 3600 ))"
      if (( age_hours >= OFFLINE_HOURS )); then
        delete_node "$node_id" "offline ${age_hours}h user=${username}"
      fi
    else
      echo "Skipping node ${node_id}: cannot parse last seen '${last_seen}'"
    fi
  fi
done <<< "$nodes_output"

if [[ "$DELETE_EMPTY_USERS" != "true" ]]; then
  exit 0
fi

nodes_after="$(docker compose exec -T headscale headscale nodes list || true)"
users_output="$(docker compose exec -T headscale headscale users list || true)"
tmp_users_with_nodes="$(mktemp)"
trap 'rm -f "$tmp_users_with_nodes"' EXIT

while IFS='|' read -r _raw_id _raw_hostname _raw_name _raw_machine _raw_node raw_user _rest; do
  username="$(trim "$raw_user")"
  [[ -n "$username" && "$username" != "User" ]] && printf '%s\n' "$username"
done <<< "$nodes_after" | sort -u > "$tmp_users_with_nodes"

while IFS='|' read -r raw_user_id _raw_name raw_username _raw_email _raw_created _rest; do
  user_id="$(trim "$raw_user_id")"
  username="$(trim "$raw_username")"
  [[ "$user_id" =~ ^[0-9]+$ ]] || continue
  [[ -n "$username" ]] || continue

  if is_protected_user "$username"; then
    continue
  fi

  if [[ -n "$USER_PREFIX" && "$username" != "$USER_PREFIX"* ]]; then
    continue
  fi

  if ! grep -Fxq "$username" "$tmp_users_with_nodes"; then
    delete_user "$user_id" "$username"
  fi
done <<< "$users_output"
