#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MANAGER="$SCRIPT_DIR/agent-heartbeat.sh"
TMP_DIR="$(mktemp -d)"
MOCK_BIN="$TMP_DIR/bin"

cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'agent-heartbeat smoke test failed: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value="$1"
  local expected="$2"
  [[ "$value" == *"$expected"* ]] || fail "expected output to contain: $expected"
}

assert_file_line() {
  local file="$1"
  local expected="$2"
  grep -Fx -- "$expected" "$file" > /dev/null || fail "missing exact line in $file: $expected"
}

mkdir -p -- "$MOCK_BIN"

cat > "$MOCK_BIN/crontab" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-l" ]]; then
  count=0
  if [[ -f "$MOCK_CRONTAB_READ_COUNT" ]]; then
    read -r count < "$MOCK_CRONTAB_READ_COUNT"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$MOCK_CRONTAB_READ_COUNT"

  if [[ -n "${MOCK_CRONTAB_MUTATE_ON_READ:-}" && "$count" -eq "$MOCK_CRONTAB_MUTATE_ON_READ" ]]; then
    printf '%s' "${MOCK_CRONTAB_MUTATION:-}" > "$MOCK_CRONTAB_STATE"
  fi

  if [[ -n "${MOCK_CRONTAB_LIST_STATUS:-}" ]]; then
    printf 'mock crontab read failure\n' >&2
    exit "$MOCK_CRONTAB_LIST_STATUS"
  fi

  if [[ -f "$MOCK_CRONTAB_STATE" ]]; then
    cat "$MOCK_CRONTAB_STATE"
    exit 0
  fi

  printf 'no crontab for smoke\n' >&2
  exit 1
fi

[[ $# -eq 1 ]] || exit 64
printf 'write\n' >> "$MOCK_CRONTAB_LOG"
cp -- "$1" "$MOCK_CRONTAB_STATE"
EOF

cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${MOCK_TMUX_DELAY:-0}" != "0" ]]; then
  sleep "$MOCK_TMUX_DELAY"
fi

if [[ "${1:-}" == "display-message" ]]; then
  printf '%%42\n'
  exit 0
fi

printf '%s\0' "$@" > "$MOCK_TMUX_ARGS"
EOF

chmod +x "$MOCK_BIN/crontab" "$MOCK_BIN/tmux"

export PATH="$MOCK_BIN:$PATH"
export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$TMP_DIR/config-home"
export XDG_STATE_HOME="$TMP_DIR/state-home"
export XDG_RUNTIME_DIR="$TMP_DIR/runtime"
export MOCK_CRONTAB_STATE="$TMP_DIR/crontab.state"
export MOCK_CRONTAB_LOG="$TMP_DIR/crontab.log"
export MOCK_CRONTAB_READ_COUNT="$TMP_DIR/crontab.read-count"
export MOCK_TMUX_ARGS="$TMP_DIR/tmux.args"
mkdir -p -- "$HOME" "$XDG_RUNTIME_DIR"

CONFIG="$TMP_DIR/agent-heartbeat.ini"
OUTPUT="$TMP_DIR/messages.log"
LOCK_PATH="$TMP_DIR/heartbeat.lock"

cat > "$CONFIG" <<EOF
[schedule]
cron=5 8,13,18,23 * * *
log_path=$TMP_DIR/cron.log

[runtime]
timeout_seconds=2
lock_path=$LOCK_PATH

[message]
text=smoke heartbeat
prefix_timestamp=false

[target.file-test]
enabled=true
type=file
path=$OUTPUT
EOF

bash -n "$MANAGER"

"$MANAGER" run --config "$CONFIG"
assert_file_line "$OUTPUT" "smoke heartbeat"

SPECIAL_MESSAGE='spaces $dollar "double" '\''single'\'' ; semicolon \\ backslash [brackets]'
"$MANAGER" run --config "$CONFIG" --target file-test --message "$SPECIAL_MESSAGE"
[[ "$(tail -n 1 "$OUTPUT")" == "$SPECIAL_MESSAGE" ]] || fail "file target changed special characters"

dry_run_output="$("$MANAGER" run --config "$CONFIG" --target file-test --dry-run)"
assert_contains "$dry_run_output" "dry-run: file target=file-test"

cron_output="$("$MANAGER" cron --config "$CONFIG")"
assert_contains "$cron_output" "5 8,13,18,23 * * *"

TMUX_CONFIG="$TMP_DIR/tmux.ini"
cat > "$TMUX_CONFIG" <<EOF
[runtime]
timeout_seconds=2
lock_path=$TMP_DIR/tmux.lock

[message]
prefix_timestamp=false

[target.tmux-test]
enabled=true
type=tmux
pane=demo:0.0
submit=true
message=unused
EOF

"$MANAGER" run --config "$TMUX_CONFIG" --message "$SPECIAL_MESSAGE"
mapfile -d '' -t tmux_args < "$MOCK_TMUX_ARGS"
[[ "${#tmux_args[@]}" -eq 10 ]] || fail "unexpected tmux argument count: ${#tmux_args[@]}"
[[ "${tmux_args[0]}" == "send-keys" && "${tmux_args[2]}" == "%42" ]] || fail "tmux pane identity was not pinned"
[[ "${tmux_args[4]}" == "$SPECIAL_MESSAGE" ]] || fail "tmux target changed special characters"
[[ "${tmux_args[5]}" == ";" && "${tmux_args[9]}" == "Enter" ]] || fail "tmux submit was not sent in the same invocation"

export MOCK_TMUX_DELAY=2
TMUX_TIMEOUT_CONFIG="$TMP_DIR/tmux-timeout.ini"
cat > "$TMUX_TIMEOUT_CONFIG" <<EOF
[runtime]
timeout_seconds=1
lock_path=$TMP_DIR/tmux-timeout.lock

[message]
prefix_timestamp=false

[target.tmux-timeout]
enabled=true
type=tmux
pane=demo:0.0
EOF
if timeout_output="$("$MANAGER" run --config "$TMUX_TIMEOUT_CONFIG" 2>&1)"; then
  fail "tmux timeout unexpectedly succeeded"
fi
assert_contains "$timeout_output" "tmux-timeout"
unset MOCK_TMUX_DELAY

AGGREGATE_CONFIG="$TMP_DIR/aggregate.ini"
AGGREGATE_OUTPUT="$TMP_DIR/aggregate.log"
cat > "$AGGREGATE_CONFIG" <<EOF
[runtime]
timeout_seconds=2
lock_path=$TMP_DIR/aggregate.lock

[message]
prefix_timestamp=false

[target.command-fails]
enabled=true
type=command
command=exit 7

[target.file-after-failure]
enabled=true
type=file
path=$AGGREGATE_OUTPUT
message=later target ran
EOF
if aggregate_output="$("$MANAGER" run --config "$AGGREGATE_CONFIG" 2>&1)"; then
  fail "failed command target unexpectedly succeeded"
fi
assert_contains "$aggregate_output" "command-fails"
assert_file_line "$AGGREGATE_OUTPUT" "later target ran"

COMMAND_TIMEOUT_CONFIG="$TMP_DIR/command-timeout.ini"
cat > "$COMMAND_TIMEOUT_CONFIG" <<EOF
[runtime]
timeout_seconds=1
lock_path=$TMP_DIR/command-timeout.lock

[message]
prefix_timestamp=false

[target.command-timeout]
enabled=true
type=command
command=sleep 2
EOF
if command_timeout_output="$("$MANAGER" run --config "$COMMAND_TIMEOUT_CONFIG" 2>&1)"; then
  fail "command timeout unexpectedly succeeded"
fi
assert_contains "$command_timeout_output" "command-timeout"

LOCK_OUTPUT="$TMP_DIR/locked-run.log"
LOCK_CONFIG="$TMP_DIR/locked-run.ini"
cat > "$LOCK_CONFIG" <<EOF
[runtime]
lock_path=$LOCK_PATH

[message]
prefix_timestamp=false

[target.locked-file]
enabled=true
type=file
path=$LOCK_OUTPUT
EOF
(
  exec 9> "$LOCK_PATH"
  flock 9
  if lock_output="$("$MANAGER" run --config "$LOCK_CONFIG" 2>&1)"; then
    fail "duplicate run unexpectedly succeeded"
  fi
  assert_contains "$lock_output" "already active"
)
[[ ! -e "$LOCK_OUTPUT" ]] || fail "duplicate run sent a target"

INVALID_CRON_CONFIG="$TMP_DIR/invalid-cron.ini"
cat > "$INVALID_CRON_CONFIG" <<EOF
[schedule]
cron=0 8 * * * extra
EOF
if invalid_cron_output="$("$MANAGER" cron --config "$INVALID_CRON_CONFIG" 2>&1)"; then
  fail "six-field cron unexpectedly succeeded"
fi
assert_contains "$invalid_cron_output" "exactly five fields"

PERCENT_CRON_CONFIG="$TMP_DIR/percent-cron.ini"
cat > "$PERCENT_CRON_CONFIG" <<EOF
[schedule]
cron=0 8 * * %
EOF
if percent_cron_output="$("$MANAGER" cron --config "$PERCENT_CRON_CONFIG" 2>&1)"; then
  fail "percent cron unexpectedly succeeded"
fi
assert_contains "$percent_cron_output" "must not contain %"

SPECIAL_DIR="$TMP_DIR/config dir"
SPECIAL_CONFIG="$SPECIAL_DIR/config's.ini"
mkdir -p -- "$SPECIAL_DIR"
cat > "$SPECIAL_CONFIG" <<EOF
[schedule]
cron=0 8 * * *
log_path=$SPECIAL_DIR/log file.log
EOF
special_cron_output="$("$MANAGER" cron --config "$SPECIAL_CONFIG")"
assert_contains "$special_cron_output" "config'\\''s.ini"
assert_contains "$special_cron_output" "log file.log"

PERCENT_PATH_CONFIG="$TMP_DIR/percent%config.ini"
cat > "$PERCENT_PATH_CONFIG" <<EOF
[schedule]
cron=0 8 * * *
EOF
if percent_path_output="$("$MANAGER" cron --config "$PERCENT_PATH_CONFIG" 2>&1)"; then
  fail "percent config path unexpectedly succeeded"
fi
assert_contains "$percent_path_output" "config path must not contain %"

INSTALL_CONFIG="$TMP_DIR/install.ini"
cat > "$INSTALL_CONFIG" <<EOF
[schedule]
cron=0 8 * * *
log_path=$TMP_DIR/install.log
EOF

reset_crontab_mock() {
  : > "$MOCK_CRONTAB_LOG"
  printf '0\n' > "$MOCK_CRONTAB_READ_COUNT"
  unset MOCK_CRONTAB_LIST_STATUS MOCK_CRONTAB_MUTATE_ON_READ MOCK_CRONTAB_MUTATION
}

reset_crontab_mock
printf 'MAILTO=user@example.test\n# user job\n15 4 * * * /usr/bin/user-job\n' > "$MOCK_CRONTAB_STATE"
"$MANAGER" install --config "$INSTALL_CONFIG"
assert_file_line "$MOCK_CRONTAB_STATE" "MAILTO=user@example.test"
assert_file_line "$MOCK_CRONTAB_STATE" "15 4 * * * /usr/bin/user-job"
assert_file_line "$MOCK_CRONTAB_STATE" "# BEGIN agent-heartbeat managed cron block"
[[ "$(wc -l < "$MOCK_CRONTAB_LOG")" -eq 1 ]] || fail "install did not perform exactly one write"

reset_crontab_mock
cat > "$MOCK_CRONTAB_STATE" <<'EOF'
# user job
# BEGIN agent-heartbeat managed cron block
old managed line without an end marker
EOF
cp -- "$MOCK_CRONTAB_STATE" "$TMP_DIR/malformed.before"
if malformed_output="$("$MANAGER" install --config "$INSTALL_CONFIG" 2>&1)"; then
  fail "malformed marker unexpectedly installed"
fi
assert_contains "$malformed_output" "malformed managed cron block"
cmp -s -- "$TMP_DIR/malformed.before" "$MOCK_CRONTAB_STATE" || fail "malformed marker changed crontab"
[[ ! -s "$MOCK_CRONTAB_LOG" ]] || fail "malformed marker wrote crontab"

reset_crontab_mock
cat > "$MOCK_CRONTAB_STATE" <<'EOF'
# BEGIN agent-heartbeat managed cron block
old managed line
# BEGIN agent-heartbeat managed cron block
# END agent-heartbeat managed cron block
EOF
cp -- "$MOCK_CRONTAB_STATE" "$TMP_DIR/duplicate.before"
if duplicate_output="$("$MANAGER" remove 2>&1)"; then
  fail "duplicate marker unexpectedly removed"
fi
assert_contains "$duplicate_output" "malformed managed cron block"
cmp -s -- "$TMP_DIR/duplicate.before" "$MOCK_CRONTAB_STATE" || fail "duplicate marker changed crontab"
[[ ! -s "$MOCK_CRONTAB_LOG" ]] || fail "duplicate marker wrote crontab"

reset_crontab_mock
printf '# user job\n' > "$MOCK_CRONTAB_STATE"
export MOCK_CRONTAB_LIST_STATUS=2
if read_error_output="$("$MANAGER" install --config "$INSTALL_CONFIG" 2>&1)"; then
  fail "crontab read error unexpectedly installed"
fi
assert_contains "$read_error_output" "unable to read crontab"
[[ "$(cat "$MOCK_CRONTAB_STATE")" == "# user job" ]] || fail "read error changed crontab"
[[ ! -s "$MOCK_CRONTAB_LOG" ]] || fail "read error wrote crontab"
unset MOCK_CRONTAB_LIST_STATUS

reset_crontab_mock
printf '# user-only crontab\n' > "$MOCK_CRONTAB_STATE"
"$MANAGER" remove
[[ "$(cat "$MOCK_CRONTAB_STATE")" == "# user-only crontab" ]] || fail "no-op remove changed user crontab"
[[ ! -s "$MOCK_CRONTAB_LOG" ]] || fail "no-op remove wrote crontab"

reset_crontab_mock
printf '# user-only crontab\n' > "$MOCK_CRONTAB_STATE"
export MOCK_CRONTAB_LIST_STATUS=2
if remove_read_error_output="$("$MANAGER" remove 2>&1)"; then
  fail "remove ignored a crontab read error"
fi
assert_contains "$remove_read_error_output" "unable to read crontab"
[[ "$(cat "$MOCK_CRONTAB_STATE")" == "# user-only crontab" ]] || fail "remove read error changed crontab"
[[ ! -s "$MOCK_CRONTAB_LOG" ]] || fail "remove read error wrote crontab"
unset MOCK_CRONTAB_LIST_STATUS

reset_crontab_mock
printf '# original user job\n' > "$MOCK_CRONTAB_STATE"
export MOCK_CRONTAB_MUTATE_ON_READ=2
export MOCK_CRONTAB_MUTATION=$'# concurrent user change\n'
if concurrent_output="$("$MANAGER" install --config "$INSTALL_CONFIG" 2>&1)"; then
  fail "concurrent crontab change unexpectedly installed"
fi
assert_contains "$concurrent_output" "changed while preparing"
[[ "$(cat "$MOCK_CRONTAB_STATE")" == "# concurrent user change" ]] || fail "concurrent user change was overwritten"
[[ ! -s "$MOCK_CRONTAB_LOG" ]] || fail "concurrent change wrote crontab"

reset_crontab_mock
cat > "$MOCK_CRONTAB_STATE" <<'EOF'
MAILTO=user@example.test
# BEGIN agent-heartbeat managed cron block
0 8 * * * managed-command
# END agent-heartbeat managed cron block
15 4 * * * /usr/bin/user-job
EOF
"$MANAGER" remove
assert_file_line "$MOCK_CRONTAB_STATE" "MAILTO=user@example.test"
assert_file_line "$MOCK_CRONTAB_STATE" "15 4 * * * /usr/bin/user-job"
if grep -F -- "agent-heartbeat managed cron block" "$MOCK_CRONTAB_STATE" > /dev/null; then
  fail "remove left the managed cron block"
fi

reset_crontab_mock
rm -f -- "$MOCK_CRONTAB_STATE"
"$MANAGER" install --config "$INSTALL_CONFIG"
assert_file_line "$MOCK_CRONTAB_STATE" "# BEGIN agent-heartbeat managed cron block"

printf 'agent-heartbeat smoke test passed\n'
