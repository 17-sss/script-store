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
declare -a TEMP_DIRS=()

CONFIG_PATH="${AGENT_HEARTBEAT_CONFIG:-}"
DRY_RUN=0
MESSAGE_OVERRIDE=""
FORCE=0
LAST_TEMP_DIR=""
CRONTAB_READ_PRESENT=0
RUN_LOCK_FD=""

cleanup_temp_dirs() {
  local dir
  for dir in "${TEMP_DIRS[@]}"; do
    if [[ -n "$dir" && "$dir" != "/" && -d "$dir" ]]; then
      rm -rf -- "$dir"
    fi
  done
}

trap cleanup_temp_dirs EXIT

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

default_lock_path() {
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    printf '%s/%s/run.lock' "$XDG_RUNTIME_DIR" "$APP_NAME"
  elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s/%s/run.lock' "$XDG_STATE_HOME" "$APP_NAME"
  else
    printf '%s/.local/state/%s/run.lock' "$HOME" "$APP_NAME"
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

configured_timeout_seconds() {
  local section="$1"
  local value
  value="$(cfg_get "$section" "timeout_seconds" "$(cfg_get "runtime" "timeout_seconds" "30")")"

  if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || (( value > 86400 )); then
    die "timeout_seconds must be an integer from 1 to 86400 in [$section]: $value"
  fi

  printf '%s' "$value"
}

validate_cron_schedule() {
  local cron="$1"
  local -a fields=()
  local field

  [[ "$cron" != *$'\n'* && "$cron" != *$'\r'* ]] || die "cron schedule must be one line"
  [[ "$cron" != *%* ]] || die "cron schedule must not contain %"

  read -r -a fields <<< "$cron"
  [[ "${#fields[@]}" -eq 5 ]] || die "cron schedule must contain exactly five fields: $cron"

  for field in "${fields[@]}"; do
    [[ "$field" =~ ^[[:alnum:]*/,-]+$ ]] || die "unsupported character in cron field: $field"
  done
}

reject_cron_percent() {
  local label="$1"
  local value="$2"
  [[ "$value" != *%* ]] || die "$label must not contain % because cron treats it as a newline"
}

cron_line() {
  local cron log_path
  cron="$(configured_cron)"
  log_path="$(configured_log_path)"
  validate_cron_schedule "$cron"
  reject_cron_percent "script path" "$SCRIPT_PATH"
  reject_cron_percent "config path" "$CONFIG_PATH"
  reject_cron_percent "log path" "$log_path"
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

validate_managed_cron_block() {
  local input_file="$1"
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start {
      if (in_block || start_count > 0) invalid = 1
      in_block = 1
      start_count++
      next
    }
    $0 == end {
      if (!in_block || end_count > 0) invalid = 1
      in_block = 0
      end_count++
      next
    }
    END {
      if (in_block || start_count != end_count || start_count > 1) invalid = 1
      exit invalid ? 1 : 0
    }
  ' "$input_file"
}

make_temp_dir() {
  LAST_TEMP_DIR="$(mktemp -d)"
  TEMP_DIRS+=("$LAST_TEMP_DIR")
}

read_crontab_snapshot() {
  local output_file="$1"
  local error_file="$2"
  local status detail

  if crontab -l > "$output_file" 2> "$error_file"; then
    CRONTAB_READ_PRESENT=1
    return 0
  else
    status=$?
  fi

  if [[ "$status" -eq 1 && ! -s "$output_file" ]] && \
      grep -Eiq 'no crontab( for)?|does not exist' "$error_file"; then
    : > "$output_file"
    CRONTAB_READ_PRESENT=0
    return 0
  fi

  detail="$(head -n 1 "$error_file")"
  [[ -n "$detail" ]] || detail="exit status $status"
  printf '%s: unable to read crontab: %s\n' "$APP_NAME" "$detail" >&2
  return 1
}

verify_crontab_unchanged() {
  local original_file="$1"
  local original_present="$2"
  local verify_file="$3"
  local verify_error="$4"
  local verify_present

  read_crontab_snapshot "$verify_file" "$verify_error" || return 1
  verify_present="$CRONTAB_READ_PRESENT"

  if [[ "$original_present" -ne "$verify_present" ]] || ! cmp -s -- "$original_file" "$verify_file"; then
    printf '%s: crontab changed while preparing the update; refusing to overwrite it\n' "$APP_NAME" >&2
    return 1
  fi
}

install_cron() {
  resolve_config_path

  if [[ ! -f "$CONFIG_PATH" ]]; then
    log_info "config missing; creating template before installing cron"
    init_config
  fi

  load_config "$CONFIG_PATH"

  local log_path tmpdir current current_error filtered next verify verify_error original_present
  log_path="$(configured_log_path)"
  cron_line > /dev/null

  make_temp_dir
  tmpdir="$LAST_TEMP_DIR"
  current="$tmpdir/current"
  current_error="$tmpdir/current.error"
  filtered="$tmpdir/filtered"
  next="$tmpdir/next"
  verify="$tmpdir/verify"
  verify_error="$tmpdir/verify.error"

  read_crontab_snapshot "$current" "$current_error" || die "cron installation aborted"
  original_present="$CRONTAB_READ_PRESENT"
  validate_managed_cron_block "$current" || die "malformed managed cron block; refusing to modify crontab"

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

  verify_crontab_unchanged "$current" "$original_present" "$verify" "$verify_error" || \
    die "cron installation aborted"
  mkdir -p -- "$(dirname -- "$log_path")"
  crontab "$next" || die "failed to write updated crontab"
  log_info "installed cron schedule: $(configured_cron)"
}

remove_cron() {
  local tmpdir current current_error next verify verify_error original_present
  make_temp_dir
  tmpdir="$LAST_TEMP_DIR"
  current="$tmpdir/current"
  current_error="$tmpdir/current.error"
  next="$tmpdir/next"
  verify="$tmpdir/verify"
  verify_error="$tmpdir/verify.error"

  read_crontab_snapshot "$current" "$current_error" || die "cron removal aborted"
  original_present="$CRONTAB_READ_PRESENT"
  if [[ "$original_present" -eq 0 ]]; then
    log_info "no crontab found"
    return 0
  fi

  validate_managed_cron_block "$current" || die "malformed managed cron block; refusing to modify crontab"
  if ! grep -Fx -- "$MARKER_START" "$current" > /dev/null; then
    log_info "no managed cron block found"
    return 0
  fi
  strip_managed_cron_block "$current" > "$next"
  verify_crontab_unchanged "$current" "$original_present" "$verify" "$verify_error" || \
    die "cron removal aborted"
  crontab "$next" || die "failed to write updated crontab"
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

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  command -v timeout >/dev/null 2>&1 || {
    printf '%s: timeout command is required for tmux and command targets\n' "$APP_NAME" >&2
    return 1
  }

  timeout --foreground --kill-after=2s "${timeout_seconds}s" "$@"
}

target_error() {
  local target="$1"
  shift
  printf '%s: target [%s] failed: %s\n' "$APP_NAME" "$target" "$*" >&2
  return 1
}

send_tmux_target() {
  local target="$1"
  local section="target.$target"
  local message="$2"
  local pane socket submit timeout_seconds pane_id

  pane="$(cfg_get "$section" "pane" "")"
  socket="$(cfg_get "$section" "socket" "")"
  submit=0
  if cfg_bool_is_true "$section" "submit" "true"; then
    submit=1
  fi

  [[ -n "$pane" ]] || target_error "$target" "missing pane" || return 1
  timeout_seconds="$(configured_timeout_seconds "$section")" || return 1

  local tmux_cmd=(tmux)
  if [[ -n "$socket" ]]; then
    tmux_cmd+=(-S "$socket")
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: tmux target=%s pane=%s submit=%s message=%s\n' "$target" "$pane" "$submit" "$message"
    return 0
  fi

  if ! pane_id="$(run_with_timeout "$timeout_seconds" "${tmux_cmd[@]}" display-message -p -t "$pane" '#{pane_id}')"; then
    target_error "$target" "could not resolve tmux pane within ${timeout_seconds}s"
    return 1
  fi
  [[ -n "$pane_id" ]] || target_error "$target" "tmux returned an empty pane identity" || return 1

  local send_cmd=("${tmux_cmd[@]}" send-keys -t "$pane_id" -l "$message")
  if [[ "$submit" -eq 1 ]]; then
    send_cmd+=(';' send-keys -t "$pane_id" Enter)
  fi

  if ! run_with_timeout "$timeout_seconds" "${send_cmd[@]}"; then
    target_error "$target" "tmux send failed or timed out after ${timeout_seconds}s"
    return 1
  fi
}

send_command_target() {
  local target="$1"
  local section="target.$target"
  local message="$2"
  local command timeout_seconds

  command="$(cfg_get "$section" "command" "")"
  [[ -n "$command" ]] || target_error "$target" "missing command" || return 1
  timeout_seconds="$(configured_timeout_seconds "$section")" || return 1

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: command target=%s command=%s message=%s\n' "$target" "$command" "$message"
    return 0
  fi

  if ! run_with_timeout "$timeout_seconds" env \
      AGENT_TARGET="$target" AGENT_MESSAGE="$message" bash -lc "$command"; then
    target_error "$target" "command failed or timed out after ${timeout_seconds}s"
    return 1
  fi
}

send_file_target() {
  local target="$1"
  local section="target.$target"
  local message="$2"
  local path

  path="$(cfg_get "$section" "path" "")"
  [[ -n "$path" ]] || target_error "$target" "missing path" || return 1
  path="$(normalize_path "$path")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: file target=%s path=%s message=%s\n' "$target" "$path" "$message"
    return 0
  fi

  if ! mkdir -p -- "$(dirname -- "$path")"; then
    target_error "$target" "could not create file target directory"
    return 1
  fi
  if ! printf '%s\n' "$message" >> "$path"; then
    target_error "$target" "could not append to file target"
    return 1
  fi
}

send_target() {
  local target="$1"
  local section="target.$target"
  local type message

  type="$(cfg_get "$section" "type" "tmux")"
  type="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"
  message="$(render_message "$target")" || return 1

  case "$type" in
    tmux)
      send_tmux_target "$target" "$message" || return 1
      ;;
    command)
      send_command_target "$target" "$message" || return 1
      ;;
    file)
      send_file_target "$target" "$message" || return 1
      ;;
    *)
      target_error "$target" "unknown target type: $type"
      return 1
      ;;
  esac

  log_info "sent heartbeat to target: $target"
}

acquire_run_lock() {
  local lock_path

  [[ "$DRY_RUN" -eq 0 ]] || return 0
  command -v flock >/dev/null 2>&1 || die "flock command is required to prevent duplicate runs"

  lock_path="$(normalize_path "$(cfg_get "runtime" "lock_path" "$(default_lock_path)")")"
  mkdir -p -- "$(dirname -- "$lock_path")"
  if ! exec {RUN_LOCK_FD}> "$lock_path"; then
    die "unable to open run lock: $lock_path"
  fi
  if ! flock -n "$RUN_LOCK_FD"; then
    die "another agent-heartbeat run is already active"
  fi
}

run_targets() {
  resolve_config_path
  load_config "$CONFIG_PATH"

  [[ "${#TARGETS[@]}" -gt 0 ]] || die "no [target.NAME] sections found in $CONFIG_PATH"
  acquire_run_lock

  local target sent_count=0 skipped_count=0 failed_count=0
  local -a failed_targets=()
  for target in "${TARGETS[@]}"; do
    target_selected "$target" || continue

    if ! cfg_bool_is_true "target.$target" "enabled" "true"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if send_target "$target"; then
      sent_count=$((sent_count + 1))
    else
      failed_count=$((failed_count + 1))
      failed_targets+=("$target")
    fi
  done

  if [[ "$failed_count" -gt 0 ]]; then
    die "heartbeat failed for $failed_count target(s): ${failed_targets[*]}"
  elif [[ "$sent_count" -eq 0 ]]; then
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
