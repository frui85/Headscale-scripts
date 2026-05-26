#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${HEADSCALE_INSTALL_DIR:-/opt/docker-compose.d/headscale-server}"
OUTPUT=""
FORCE="false"

usage() {
  cat <<'EOF'
Headscale user and node management helper.

Usage:
  ./scripts/manage.sh [global options] <resource> <action> [options]

Global options:
  --install-dir DIR       Install directory. Default: /opt/docker-compose.d/headscale-server
  -o, --output FORMAT     Headscale output format: json, json-line, yaml
  --force                 Disable Headscale confirmation prompts where supported.
  -h, --help              Show this help.

User commands:
  user list
  user create USERNAME
  user rename (--id ID | --name USERNAME) NEW_USERNAME
  user delete (--id ID | --name USERNAME)

Node commands:
  node list [--user USERNAME] [--tags]
  node register --key KEY --user USERNAME
  node rename --id NODE_ID NEW_NAME
  node delete --id NODE_ID
  node move --id NODE_ID --user USERNAME
  node expire --id NODE_ID [--expiry RFC3339_TIME]

Examples:
  ./scripts/manage.sh user list
  ./scripts/manage.sh user create fr-mbp
  ./scripts/manage.sh user rename --name fr-mbp fr-macbook
  ./scripts/manage.sh user delete --name fr-mbp --force

  ./scripts/manage.sh node list
  ./scripts/manage.sh node list --user fr-mbp
  ./scripts/manage.sh node register --key 4h12xxx --user fr-mbp
  ./scripts/manage.sh node rename --id 2 fr-mbp
  ./scripts/manage.sh node move --id 2 --user default
  ./scripts/manage.sh node expire --id 2 --force
  ./scripts/manage.sh node delete --id 2 --force
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_arg() {
  local value="${1:-}"
  local name="$2"
  [[ -n "$value" ]] || die "$name is required"
}

extract_user_id() {
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}.*/\1/p' | head -n 1
}

compose_headscale() {
  local args=()
  if [[ -n "$OUTPUT" ]]; then
    args+=("-o" "$OUTPUT")
  fi
  if [[ "$FORCE" == "true" ]]; then
    args+=("--force")
  fi

  docker compose exec -T headscale headscale "${args[@]}" "$@"
}

resolve_user_id() {
  local username="$1"
  local users_json=""
  local user_id=""

  users_json="$(docker compose exec -T headscale headscale users list --name "$username" -o json 2>/dev/null || true)"
  user_id="$(printf '%s\n' "$users_json" | extract_user_id)"

  [[ -n "$user_id" ]] || die "User not found: ${username}"
  printf '%s\n' "$user_id"
}

parse_identity_flags() {
  ID_VALUE=""
  NAME_VALUE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id|--identifier)
        ID_VALUE="${2:-}"
        shift 2
        ;;
      --name)
        NAME_VALUE="${2:-}"
        shift 2
        ;;
      --force)
        FORCE="true"
        shift
        ;;
      *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
}

run_user() {
  local action="${1:-}"
  shift || true

  case "$action" in
    list|ls)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --force)
            FORCE="true"
            shift
            ;;
          *)
            die "Unknown user list option: $1"
            ;;
        esac
      done
      compose_headscale users list
      ;;
    create)
      local username="${1:-}"
      require_arg "$username" "USERNAME"
      compose_headscale users create "$username"
      ;;
    rename)
      POSITIONAL=()
      parse_identity_flags "$@"
      local new_name="${POSITIONAL[0]:-}"
      require_arg "$new_name" "NEW_USERNAME"
      if [[ -n "$ID_VALUE" ]]; then
        compose_headscale users rename --identifier "$ID_VALUE" --new-name "$new_name"
      elif [[ -n "$NAME_VALUE" ]]; then
        compose_headscale users rename --name "$NAME_VALUE" --new-name "$new_name"
      else
        die "Use --id ID or --name USERNAME"
      fi
      ;;
    delete|destroy|remove|rm)
      POSITIONAL=()
      parse_identity_flags "$@"
      if [[ -n "$ID_VALUE" ]]; then
        compose_headscale users destroy --identifier "$ID_VALUE"
      elif [[ -n "$NAME_VALUE" ]]; then
        compose_headscale users destroy --name "$NAME_VALUE"
      else
        die "Use --id ID or --name USERNAME"
      fi
      ;;
    ""|-h|--help)
      usage
      ;;
    *)
      die "Unknown user action: $action"
      ;;
  esac
}

run_node() {
  local action="${1:-}"
  shift || true

  case "$action" in
    list|ls)
      local user_filter=""
      local show_tags="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --user)
            user_filter="${2:-}"
            shift 2
            ;;
          --tags)
            show_tags="true"
            shift
            ;;
          --force)
            FORCE="true"
            shift
            ;;
          *)
            die "Unknown node list option: $1"
            ;;
        esac
      done
      local args=(nodes list)
      [[ -n "$user_filter" ]] && args+=(--user "$user_filter")
      [[ "$show_tags" == "true" ]] && args+=(--tags)
      compose_headscale "${args[@]}"
      ;;
    register)
      local key=""
      local username=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --key)
            key="${2:-}"
            shift 2
            ;;
          --user)
            username="${2:-}"
            shift 2
            ;;
          --force)
            FORCE="true"
            shift
            ;;
          *)
            die "Unknown node register option: $1"
            ;;
        esac
      done
      require_arg "$key" "--key"
      require_arg "$username" "--user"
      compose_headscale nodes register --key "$key" --user "$username"
      ;;
    rename)
      local node_id=""
      POSITIONAL=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --id|--identifier)
            node_id="${2:-}"
            shift 2
            ;;
          --force)
            FORCE="true"
            shift
            ;;
          *)
            POSITIONAL+=("$1")
            shift
            ;;
        esac
      done
      local new_name="${POSITIONAL[0]:-}"
      require_arg "$node_id" "--id"
      require_arg "$new_name" "NEW_NAME"
      compose_headscale nodes rename --identifier "$node_id" "$new_name"
      ;;
    delete|remove|rm)
      local node_id=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --id|--identifier)
            node_id="${2:-}"
            shift 2
            ;;
          --force)
            FORCE="true"
            shift
            ;;
          *)
            die "Unknown node delete option: $1"
            ;;
        esac
      done
      require_arg "$node_id" "--id"
      compose_headscale nodes delete --identifier "$node_id"
      ;;
    move)
      local node_id=""
      local username=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --id|--identifier)
            node_id="${2:-}"
            shift 2
            ;;
          --user)
            username="${2:-}"
            shift 2
            ;;
          --force)
            FORCE="true"
            shift
            ;;
          *)
            die "Unknown node move option: $1"
            ;;
        esac
      done
      require_arg "$node_id" "--id"
      require_arg "$username" "--user"
      local user_id=""
      user_id="$(resolve_user_id "$username")"
      compose_headscale nodes move --identifier "$node_id" --user "$user_id"
      ;;
    expire)
      local node_id=""
      local expiry=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --id|--identifier)
            node_id="${2:-}"
            shift 2
            ;;
          --expiry)
            expiry="${2:-}"
            shift 2
            ;;
          --force)
            FORCE="true"
            shift
            ;;
          *)
            die "Unknown node expire option: $1"
            ;;
        esac
      done
      require_arg "$node_id" "--id"
      local args=(nodes expire --identifier "$node_id")
      [[ -n "$expiry" ]] && args+=(--expiry "$expiry")
      compose_headscale "${args[@]}"
      ;;
    ""|-h|--help)
      usage
      ;;
    *)
      die "Unknown node action: $action"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    -o|--output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    user|users|node|nodes)
      break
      ;;
    *)
      die "Unknown global option or resource: $1"
      ;;
  esac
done

RESOURCE="${1:-}"
[[ -n "$RESOURCE" ]] || {
  usage
  exit 1
}
shift

[[ -d "$INSTALL_DIR" ]] || die "Install directory not found: $INSTALL_DIR"
cd "$INSTALL_DIR"

case "$RESOURCE" in
  user|users)
    run_user "$@"
    ;;
  node|nodes)
    run_node "$@"
    ;;
  *)
    die "Unknown resource: $RESOURCE"
    ;;
esac
