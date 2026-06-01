#!/usr/bin/env bash
set -euo pipefail

APP_NAME="agent-heartbeat"
DEFAULT_CRON="0 8,13,18,23 * * *"
MARKER_START="# BEGIN agent-heartbeat managed cron block"
MARKER_END="# END agent-heartbeat managed cron block"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"

declare -A CFG=()
declare -a TARGETS=()
declare -a TARGET_FILTERS=()

CONFIG_PATH="${AGENT_HEARTBEAT_CONFIG:-}"
DRY_RUN=0
MESSAGE_OVERRIDE=""
FORCE=0

default_config_path() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s/%s/%s.ini' "$XDG_CONFIG_HOME" "$APP_NAME" "$APP_NAME"
  else
    printf '%s/.config/%s/%s.ini' "$HOME" "$APP_NAME" "$APP_NAME"
  fi
}

default_log_path() {
  if [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s/%s/%s.log' "$XDG_STATE_HOME" "$APP_NAME" "$APP_NAME"
  else
    printf '%s/.local/state/%s/%s.log' "$HOME" "$APP_NAME" "$APP_NAME"
  fi
}

die() {
  printf '%s: %s\n' "$APP_NAME" "$*" >&2
  exit 1
}

log_info() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" >&2
}

usage() {
  cat <<'EOF'
agent-heartbeat - send scheduled keepalive messages to local agent sessions

Usage:
  agent-heartbeat.sh init-config [--config PATH] [--force]
  agent-heartbeat.sh run [--config PATH] [--target NAME] [--message TEXT] [--dry-run]
  agent-heartbeat.sh cron [--config PATH]
  agent-heartbeat.sh install [--config PATH]
  agent-heartbeat.sh remove
  agent-heartbeat.sh help

Default schedule:
  0 8,13,18,23 * * *

Target types:
  tmux     Send literal text to a tmux pane, optionally pressing Enter.
  command  Run a shell command with AGENT_TARGET and AGENT_MESSAGE set.
  file     Append the message to a file, mainly for smoke tests and logging.
EOF
}

resolve_config_path() {
  if [[ -z "$CONFIG_PATH" ]]; then
    CONFIG_PATH="$(default_config_path)"
  fi
  CONFIG_PATH="$(normalize_path "$CONFIG_PATH")"
}

expand_path() {
  local path="$1"
  case "$path" in
    "~")
      printf '%s' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s' "$HOME" "${path:2}"
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

normalize_path() {
  local path
  path="$(expand_path "$1")"

  case "$path" in
    /*)
      printf '%s' "$path"
      ;;
    *)
      printf '%s/%s' "$PWD" "$path"
      ;;
  esac
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

add_target() {
  local target="$1"
  local existing
  for existing in "${TARGETS[@]}"; do
    [[ "$existing" == "$target" ]] && return 0
  done
  TARGETS+=("$target")
}

load_config() {
  local file="$1"
  [[ -f "$file" ]] || die "config not found: $file"

  CFG=()
  TARGETS=()

  local section=""
  local raw line key value target

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="${raw%$'\r'}"
    line="$(trim "$raw")"

    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" || "${line:0:1}" == ";" ]] && continue

    if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
      section="$(trim "${BASH_REMATCH[1]}")"
      [[ -n "$section" ]] || die "empty section name in $file"
      if [[ "$section" == target.* ]]; then
        target="${section#target.}"
        [[ -n "$target" ]] || die "empty target name in $file"
        add_target "$target"
      fi
      continue
    fi

    [[ "$line" == *"="* ]] || die "invalid config line: $raw"
    [[ -n "$section" ]] || die "key outside section: $raw"

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    value="$(strip_quotes "$value")"
    [[ -n "$key" ]] || die "empty key in section [$section]"

    CFG["$section.$key"]="$value"
  done < "$file"
}

load_config_if_present() {
  CFG=()
  TARGETS=()
  if [[ -f "$CONFIG_PATH" ]]; then
    load_config "$CONFIG_PATH"
  fi
}

cfg_get() {
  local section="$1"
  local key="$2"
  local default="${3:-}"
  local full_key="$section.$key"
  printf '%s' "${CFG[$full_key]:-$default}"
}

cfg_bool_is_true() {
  local section="$1"
  local key="$2"
  local default="$3"
  local value
  value="$(cfg_get "$section" "$key" "$default")"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    0|false|no|off)
      return 1
      ;;
    *)
      die "invalid boolean for [$section] $key: $value"
      ;;
  esac
}

shell_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

configured_cron() {
  cfg_get "schedule" "cron" "$DEFAULT_CRON"
}

configured_log_path() {
  normalize_path "$(cfg_get "schedule" "log_path" "$(default_log_path)")"
}

cron_line() {
  local cron log_path
  cron="$(configured_cron)"
  log_path="$(configured_log_path)"
  printf '%s /bin/bash %s run --config %s >> %s 2>&1' \
    "$cron" \
    "$(shell_quote "$SCRIPT_PATH")" \
    "$(shell_quote "$CONFIG_PATH")" \
    "$(shell_quote "$log_path")"
}

print_cron_block() {
  printf '%s\n' "$MARKER_START"
  cron_line
  printf '\n%s\n' "$MARKER_END"
}

init_config() {
  resolve_config_path

  local example="$SCRIPT_DIR/agent-heartbeat.ini.example"
  [[ -f "$example" ]] || die "example config not found: $example"

  if [[ -e "$CONFIG_PATH" && "$FORCE" -ne 1 ]]; then
    die "config already exists: $CONFIG_PATH (use --force to overwrite)"
  fi

  mkdir -p -- "$(dirname -- "$CONFIG_PATH")"
  cp -- "$example" "$CONFIG_PATH"
  log_info "wrote config: $CONFIG_PATH"
}

strip_managed_cron_block() {
  local input_file="$1"
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    !in_block { print }
  ' "$input_file"
}

install_cron() {
  resolve_config_path

  if [[ ! -f "$CONFIG_PATH" ]]; then
    log_info "config missing; creating template before installing cron"
    init_config
  fi

  load_config "$CONFIG_PATH"

  local log_path tmpdir current filtered next
  log_path="$(configured_log_path)"
  mkdir -p -- "$(dirname -- "$log_path")"

  tmpdir="$(mktemp -d)"
  current="$tmpdir/current"
  filtered="$tmpdir/filtered"
  next="$tmpdir/next"

  if ! crontab -l > "$current" 2>/dev/null; then
    : > "$current"
  fi

  strip_managed_cron_block "$current" > "$filtered"
  {
    if [[ -s "$filtered" ]]; then
      cat "$filtered"
      printf '\n'
    fi
    printf '%s\n' "$MARKER_START"
    cron_line
    printf '\n%s\n' "$MARKER_END"
  } > "$next"

  crontab "$next"
  rm -rf -- "$tmpdir"
  log_info "installed cron schedule: $(configured_cron)"
}

remove_cron() {
  local tmpdir current next
  tmpdir="$(mktemp -d)"
  current="$tmpdir/current"
  next="$tmpdir/next"

  if ! crontab -l > "$current" 2>/dev/null; then
    rm -rf -- "$tmpdir"
    log_info "no crontab found"
    return 0
  fi

  strip_managed_cron_block "$current" > "$next"
  crontab "$next"
  rm -rf -- "$tmpdir"
  log_info "removed managed cron block"
}

target_selected() {
  local target="$1"
  local selected

  [[ "${#TARGET_FILTERS[@]}" -eq 0 ]] && return 0

  for selected in "${TARGET_FILTERS[@]}"; do
    [[ "$selected" == "$target" ]] && return 0
  done

  return 1
}

render_message() {
  local target="$1"
  local section="target.$target"
  local message

  if [[ -n "$MESSAGE_OVERRIDE" ]]; then
    message="$MESSAGE_OVERRIDE"
  else
    message="$(cfg_get "$section" "message" "")"
    if [[ -z "$message" ]]; then
      message="$(cfg_get "message" "text" "5-hour agent heartbeat ping.")"
    fi
  fi

  if cfg_bool_is_true "message" "prefix_timestamp" "true"; then
    printf '[%s] %s' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$message"
  else
    printf '%s' "$message"
  fi
}

send_tmux_target() {
  local target="$1"
  local section="target.$target"
  local message="$2"
  local pane socket submit

  pane="$(cfg_get "$section" "pane" "")"
  socket="$(cfg_get "$section" "socket" "")"
  submit=0
  if cfg_bool_is_true "$section" "submit" "true"; then
    submit=1
  fi

  [[ -n "$pane" ]] || die "missing pane for tmux target [$section]"

  local tmux_cmd=(tmux)
  if [[ -n "$socket" ]]; then
    tmux_cmd+=(-S "$socket")
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: tmux target=%s pane=%s submit=%s message=%s\n' "$target" "$pane" "$submit" "$message"
    return 0
  fi

  "${tmux_cmd[@]}" send-keys -t "$pane" -l "$message"
  if [[ "$submit" -eq 1 ]]; then
    "${tmux_cmd[@]}" send-keys -t "$pane" Enter
  fi
}

send_command_target() {
  local target="$1"
  local section="target.$target"
  local message="$2"
  local command

  command="$(cfg_get "$section" "command" "")"
  [[ -n "$command" ]] || die "missing command for command target [$section]"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: command target=%s command=%s message=%s\n' "$target" "$command" "$message"
    return 0
  fi

  AGENT_TARGET="$target" AGENT_MESSAGE="$message" bash -lc "$command"
}

send_file_target() {
  local target="$1"
  local section="target.$target"
  local message="$2"
  local path

  path="$(cfg_get "$section" "path" "")"
  [[ -n "$path" ]] || die "missing path for file target [$section]"
  path="$(normalize_path "$path")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: file target=%s path=%s message=%s\n' "$target" "$path" "$message"
    return 0
  fi

  mkdir -p -- "$(dirname -- "$path")"
  printf '%s\n' "$message" >> "$path"
}

send_target() {
  local target="$1"
  local section="target.$target"
  local type message

  type="$(cfg_get "$section" "type" "tmux")"
  type="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"
  message="$(render_message "$target")"

  case "$type" in
    tmux)
      send_tmux_target "$target" "$message"
      ;;
    command)
      send_command_target "$target" "$message"
      ;;
    file)
      send_file_target "$target" "$message"
      ;;
    *)
      die "unknown target type for [$section]: $type"
      ;;
  esac

  log_info "sent heartbeat to target: $target"
}

run_targets() {
  resolve_config_path
  load_config "$CONFIG_PATH"

  [[ "${#TARGETS[@]}" -gt 0 ]] || die "no [target.NAME] sections found in $CONFIG_PATH"

  local target sent_count=0 skipped_count=0
  for target in "${TARGETS[@]}"; do
    target_selected "$target" || continue

    if ! cfg_bool_is_true "target.$target" "enabled" "true"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    send_target "$target"
    sent_count=$((sent_count + 1))
  done

  if [[ "$sent_count" -eq 0 ]]; then
    die "no enabled targets matched (skipped: $skipped_count)"
  fi
}

parse_config_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a path"
        CONFIG_PATH="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

parse_init_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a path"
        CONFIG_PATH="$2"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

parse_run_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a path"
        CONFIG_PATH="$2"
        shift 2
        ;;
      --target)
        [[ $# -ge 2 ]] || die "--target requires a name"
        TARGET_FILTERS+=("$2")
        shift 2
        ;;
      --message)
        [[ $# -ge 2 ]] || die "--message requires text"
        MESSAGE_OVERRIDE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

main() {
  local command="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$command" in
    init-config)
      parse_init_options "$@"
      init_config
      ;;
    run)
      parse_run_options "$@"
      run_targets
      ;;
    cron)
      parse_config_options "$@"
      resolve_config_path
      load_config_if_present
      print_cron_block
      ;;
    install)
      parse_config_options "$@"
      install_cron
      ;;
    remove)
      [[ $# -eq 0 ]] || die "remove does not accept options"
      remove_cron
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      die "unknown command: $command"
      ;;
  esac
}

main "$@"
