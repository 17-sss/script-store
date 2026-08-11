#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Writer discovery must fail closed when an unrelated same-UID /proc entry is
# unreadable. Run this fixture suite in its own PID namespace when available so
# that the positive case has a complete, isolated /proc view as well.
if [[ "${CSM_SMOKE_PID_NAMESPACE:-}" != "1" ]] && command -v unshare >/dev/null 2>&1; then
  if unshare --user --map-root-user --pid --fork --mount-proc true >/dev/null 2>&1; then
    exec env CSM_SMOKE_PID_NAMESPACE=1 \
      unshare --user --map-root-user --pid --fork --mount-proc "$0" "$@"
  fi
fi

INSTALLER="$SCRIPT_DIR/install-csm.sh"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
ORIGINAL_PATH="$PATH"
REAL_HOME="${HOME:-}"
REAL_CODEX_HOME="${CODEX_HOME:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/csm-test.XXXXXX")"
TEST_HOME="$TMP_DIR/home"
TEST_CODEX_HOME="$TMP_DIR/codex-home"
TEST_BIN="$TMP_DIR/bin"
FAKE_CODEX_LOG="$TMP_DIR/fake-codex.log"
QUARANTINE_ROOT="$TMP_DIR/xdg-data/csm/quarantine"
PATH_WITH_FAKE="$TEST_BIN:$PATH"
PROJECT_CWD="/tmp/csm-project"
WRITER_PIDS=()

safe_cleanup() {
  local status=$?
  local writer_pid
  for writer_pid in "${WRITER_PIDS[@]}"; do
    if [[ "$writer_pid" =~ ^[0-9]+$ ]] && kill -0 "$writer_pid" 2>/dev/null; then
      kill -TERM "$writer_pid" 2>/dev/null || true
      wait "$writer_pid" 2>/dev/null || true
    fi
  done
  if [[ -z "${TMP_DIR:-}" || "$TMP_DIR" == "/" ]]; then
    printf 'refusing to clean unsafe tmp path: %s\n' "${TMP_DIR:-}" >&2
    exit 1
  fi
  if [[ -n "$REAL_HOME" && "$TMP_DIR" == "$REAL_HOME" ]]; then
    printf 'refusing to clean real HOME: %s\n' "$TMP_DIR" >&2
    exit 1
  fi
  if [[ -n "$REAL_CODEX_HOME" && "$TMP_DIR" == "$REAL_CODEX_HOME" ]]; then
    printf 'refusing to clean real CODEX_HOME: %s\n' "$TMP_DIR" >&2
    exit 1
  fi
  if [[ "$TMP_DIR" == "$REPO_ROOT" ]]; then
    printf 'refusing to clean repository root: %s\n' "$TMP_DIR" >&2
    exit 1
  fi
  if [[ -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  exit "$status"
}
trap safe_cleanup EXIT

mkdir -p "$TEST_HOME" "$TEST_CODEX_HOME/sessions/2026/07/20" \
  "$TEST_CODEX_HOME/archived_sessions/2026/07/20" \
  "$TMP_DIR/xdg-config" "$TMP_DIR/xdg-data" "$TMP_DIR/xdg-state" "$TMP_DIR/xdg-cache" \
  "$TEST_BIN"
: > "$FAKE_CODEX_LOG"

cat > "$TEST_BIN/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_CODEX_LOG"
if [[ -n "${FAKE_CODEX_MUTATE_FILE:-}" && "$(wc -l < "$FAKE_CODEX_LOG")" -eq 1 ]]; then
  sed "1s/$FAKE_CODEX_OLD_ID/$FAKE_CODEX_NEW_ID/" "$FAKE_CODEX_MUTATE_FILE" > "$FAKE_CODEX_MUTATE_FILE.next"
  mv -- "$FAKE_CODEX_MUTATE_FILE.next" "$FAKE_CODEX_MUTATE_FILE"
fi
FAKE_CODEX
chmod +x "$TEST_BIN/codex"

cat > "$TMP_DIR/fake-codex-writer.js" <<'FAKE_WRITER'
'use strict';

const fs = require('fs');

const [file, readyFile, signalLog, closeTrigger] = process.argv.slice(2);
const fd = fs.openSync(file, 'r+');
let closed = false;

function closeAndExit() {
  if (!closed) {
    fs.closeSync(fd);
    closed = true;
  }
  process.exit(0);
}

fs.writeFileSync(readyFile, 'ready\n');
process.on('SIGTERM', () => {
  fs.writeFileSync(signalLog, 'SIGTERM\n', {flag: 'a'});
  closeAndExit();
});
setInterval(() => {
  if (closeTrigger && fs.existsSync(closeTrigger)) {
    closeAndExit();
  }
}, 20);
FAKE_WRITER

isolated_env() {
  env -u NVM_DIR -u FNM_DIR -u VOLTA_HOME \
    HOME="$TEST_HOME" \
    CODEX_HOME="$TEST_CODEX_HOME" \
    XDG_CONFIG_HOME="$TMP_DIR/xdg-config" \
    XDG_DATA_HOME="$TMP_DIR/xdg-data" \
    XDG_STATE_HOME="$TMP_DIR/xdg-state" \
    XDG_CACHE_HOME="$TMP_DIR/xdg-cache" \
    FAKE_CODEX_LOG="$FAKE_CODEX_LOG" \
    PATH="$PATH_WITH_FAKE" \
    "$@"
}

if [[ "$(isolated_env bash -c 'command -v codex')" != "$TEST_BIN/codex" ]]; then
  printf 'fake codex is not first on PATH\n' >&2
  exit 1
fi

uuid_a="019f1000-0000-7000-8000-000000000001"
uuid_b="019f1000-0000-7000-8000-000000000002"
uuid_c="019f1000-0000-7000-8000-000000000003"
uuid_d="019f1000-0000-7000-8000-000000000004"
uuid_e="019f1000-0000-7000-8000-000000000005"
uuid_f="019f1000-0000-7000-8000-000000000006"
uuid_g="019f1000-0000-7000-8000-000000000007"
uuid_h="019f1000-0000-7000-8000-000000000008"
uuid_i="019f1000-0000-7000-8000-000000000009"
uuid_j="019f1000-0000-7000-8000-000000000010"
uuid_k="019f1000-0000-7000-8000-000000000011"
uuid_l="019f1000-0000-7000-8000-000000000012"
uuid_m="019f1000-0000-7000-8000-000000000013"
uuid_n="019f1000-0000-7000-8000-000000000014"
uuid_o="019f1000-0000-7000-8000-000000000015"
uuid_p="019f1000-0000-7000-8000-000000000016"
uuid_q="019f1000-0000-7000-8000-000000000017"
uuid_r="019f1000-0000-7000-8000-000000000018"
uuid_s="019f1000-0000-7000-8000-000000000019"
uuid_t="019f1000-0000-7000-8000-000000000020"
uuid_u="019f1000-0000-7000-8000-000000000021"
uuid_v="019f1000-0000-7000-8000-000000000022"
uuid_w="019f1000-0000-7000-8000-000000000023"
uuid_x="019f1000-0000-7000-8000-000000000024"
uuid_y="019f1000-0000-7000-8000-000000000025"
uuid_z="019f1000-0000-7000-8000-000000000026"
uuid_aa="019f1000-0000-7000-8000-000000000027"
uuid_ab="019f1000-0000-7000-8000-000000000028"
uuid_ac="019f1000-0000-7000-8000-000000000029"
uuid_ad="019f1000-0000-7000-8000-000000000030"
uuid_ae="019f1000-0000-7000-8000-000000000031"
uuid_af="019f1000-0000-7000-8000-000000000032"
uuid_ag="019f1000-0000-7000-8000-000000000033"
uuid_ah="019f1000-0000-7000-8000-000000000034"
uuid_ai="019f1000-0000-7000-8000-000000000035"
uuid_aj="019f1000-0000-7000-8000-000000000036"
uuid_ak="019f1000-0000-7000-8000-000000000037"
uuid_al="019f1000-0000-7000-8000-000000000038"
uuid_am="019f1000-0000-7000-8000-000000000039"
uuid_an="019f1000-0000-7000-8000-000000000040"
uuid_ao="019f1000-0000-7000-8000-000000000041"
uuid_ap="019f1000-0000-7000-8000-000000000042"
uuid_aq="019f1000-0000-7000-8000-000000000043"
uuid_ar="019f1000-0000-7000-8000-000000000044"
uuid_as="019f1000-0000-7000-8000-000000000045"
uuid_at="019f1000-0000-7000-8000-000000000046"
uuid_au="019f1000-0000-7000-8000-000000000047"
uuid_av="019f1000-0000-7000-8000-000000000048"
uuid_aw="019f1000-0000-7000-8000-000000000049"
uuid_ax="019f1000-0000-7000-8000-000000000050"
uuid_ay="019f1000-0000-7000-8000-000000000051"
uuid_az="019f1000-0000-7000-8000-000000000052"
uuid_ba="019f1000-0000-7000-8000-000000000053"

write_session() {
  local area="$1"
  local file_id="$2"
  local meta_id="$3"
  local timestamp="$4"
  local prompt="$5"
  local file="$TEST_CODEX_HOME/$area/2026/07/20/rollout-${timestamp//:/-}-$file_id.jsonl"
  cat > "$file" <<JSONL
{"timestamp":"$timestamp.000Z","type":"session_meta","payload":{"id":"$meta_id","timestamp":"$timestamp.000Z","cwd":"$PROJECT_CWD","originator":"Codex CLI","source":"cli","thread_source":"user"}}
{"timestamp":"$timestamp.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"$prompt"}]}}
JSONL
  printf '%s\n' "$file"
}

append_parent_meta() {
  local file="$1"
  local parent_id="$2"
  local timestamp="$3"
  cat >> "$file" <<JSONL
{"timestamp":"$timestamp.900Z","type":"session_meta","payload":{"id":"$parent_id","timestamp":"$timestamp.900Z","cwd":"$PROJECT_CWD/parent","originator":"Codex CLI","source":"cli","thread_source":"user"}}
JSONL
}

write_session_missing_payload_id() {
  local file_id="$1"
  local timestamp="$2"
  local prompt="$3"
  local file="$TEST_CODEX_HOME/sessions/2026/07/20/rollout-${timestamp//:/-}-$file_id.jsonl"
  cat > "$file" <<JSONL
{"timestamp":"$timestamp.000Z","type":"session_meta","payload":{"timestamp":"$timestamp.000Z","cwd":"$PROJECT_CWD","originator":"Codex CLI","source":"cli","thread_source":"user"}}
{"timestamp":"$timestamp.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"$prompt"}]}}
JSONL
}

write_no_filename_uuid() {
  local meta_id="$1"
  local timestamp="$2"
  local prompt="$3"
  local file="$TEST_CODEX_HOME/sessions/2026/07/20/rollout-no-valid-uuid.jsonl"
  cat > "$file" <<JSONL
{"timestamp":"$timestamp.000Z","type":"session_meta","payload":{"id":"$meta_id","timestamp":"$timestamp.000Z","cwd":"$PROJECT_CWD","originator":"Codex CLI","source":"cli","thread_source":"user"}}
{"timestamp":"$timestamp.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"$prompt"}]}}
JSONL
}

write_non_rollout_filename() {
  local meta_id="$1"
  local timestamp="$2"
  local prompt="$3"
  local file="$TEST_CODEX_HOME/sessions/2026/07/20/backup-$meta_id.jsonl"
  cat > "$file" <<JSONL
{"timestamp":"$timestamp.000Z","type":"session_meta","payload":{"id":"$meta_id","timestamp":"$timestamp.000Z","cwd":"$PROJECT_CWD","originator":"Codex CLI","source":"cli","thread_source":"user"}}
{"timestamp":"$timestamp.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"$prompt"}]}}
JSONL
}

write_subagent_with_parent_meta() {
  local file_id="$1"
  local parent_id="$2"
  local timestamp="$3"
  local prompt="$4"
  local file="$TEST_CODEX_HOME/sessions/2026/07/20/rollout-${timestamp//:/-}-$file_id.jsonl"
  cat > "$file" <<JSONL
{"timestamp":"$timestamp.000Z","type":"session_meta","payload":{"id":"$file_id","timestamp":"$timestamp.000Z","cwd":"$PROJECT_CWD","agent_role":"code-reviewer","agent_nickname":"Ada","source":{"subagent":{"thread_spawn":{"agent_role":"code-reviewer","agent_nickname":"Ada"}}}}}
{"timestamp":"$timestamp.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"$prompt"}]}}
{"timestamp":"$timestamp.900Z","type":"session_meta","payload":{"id":"$parent_id","timestamp":"$timestamp.900Z","cwd":"$PROJECT_CWD/parent","originator":"Codex CLI","source":"cli","thread_source":"user"}}
JSONL
}

write_session_with_terminal_controls() {
  local file_id="$1"
  local timestamp="$2"
  local file="$TEST_CODEX_HOME/sessions/2026/07/20/rollout-${timestamp//:/-}-$file_id.jsonl"
  cat > "$file" <<JSONL
{"timestamp":"$timestamp.000Z","type":"session_meta","payload":{"id":"$file_id","timestamp":"$timestamp.000Z","cwd":"$PROJECT_CWD","originator":"Codex CLI","source":"cli","thread_source":"user"}}
{"timestamp":"$timestamp.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"case L \\u001b[2J\\u001b]0;forged title\\u0007terminal\\tspoof"}]}}
JSONL
  printf '%s\n' "$file"
}

write_thread_title() {
  local session_id="$1"
  local title="$2"
  local first_user_message="$3"
  SESSION_ID="$session_id" THREAD_TITLE="$title" FIRST_USER_MESSAGE="$first_user_message" DATABASE_PATH="$TEST_CODEX_HOME/state_5.sqlite" node --no-warnings <<'NODE'
const {DatabaseSync} = require('node:sqlite');
const database = new DatabaseSync(process.env.DATABASE_PATH);
database.exec('CREATE TABLE IF NOT EXISTS threads (id TEXT PRIMARY KEY, title TEXT NOT NULL, first_user_message TEXT NOT NULL)');
database.prepare('INSERT OR REPLACE INTO threads (id, title, first_user_message) VALUES (?, ?, ?)')
  .run(process.env.SESSION_ID, process.env.THREAD_TITLE, process.env.FIRST_USER_MESSAGE);
database.close();
NODE
}

assert_json_entry() {
  local json="$1"
  local prompt="$2"
  local expression="$3"
  JSON_INPUT="$json" PROMPT="$prompt" EXPRESSION="$expression" node <<'NODE'
const data = JSON.parse(process.env.JSON_INPUT);
const entries = [...(data.active || []), ...(data.archived || []), ...(data.quarantine || [])];
const entry = entries.find((item) => item.summary === process.env.PROMPT);
if (!entry) {
  throw new Error(`missing entry for prompt: ${process.env.PROMPT}`);
}
if (!Function('entry', `return (${process.env.EXPRESSION});`)(entry)) {
  throw new Error(`assertion failed for ${process.env.PROMPT}: ${process.env.EXPRESSION}\n${JSON.stringify(entry, null, 2)}`);
}
NODE
}

strip_ansi() {
  sed -E $'s/\x1b\\[[0-9;]*[[:alpha:]]//g'
}

clean_log() {
  tr -d '\r' < "$1" | strip_ansi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -F -q -- "$needle" <<< "$haystack"; then
    printf 'missing expected text: %s\n' "$needle" >&2
    exit 1
  fi
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

run_tui() {
  local keys="$1"
  local log="$2"
  local mutate_file="${3:-}"
  local old_id="${4:-}"
  local new_id="${5:-}"
  local manager_args="${6:-}"
  if ! command -v script >/dev/null 2>&1; then
    printf 'script command is required for TUI mutation tests\n' >&2
    exit 1
  fi
  set +o pipefail
  {
    python3 - "$keys" <<'PY'
import os
import sys
import time

data = sys.argv[1].encode('utf-8').decode('unicode_escape')
try:
    for char in data:
        os.write(1, char.encode('utf-8'))
        time.sleep(0.6 if char == 'x' else 0.08)
except BrokenPipeError:
    os._exit(0)
os._exit(0)
PY
  } | script -q -e -O "$log" -c \
    "stty cols 120 rows 28; env -u NVM_DIR -u FNM_DIR -u VOLTA_HOME HOME='$TEST_HOME' CODEX_HOME='$TEST_CODEX_HOME' XDG_CONFIG_HOME='$TMP_DIR/xdg-config' XDG_DATA_HOME='$TMP_DIR/xdg-data' XDG_STATE_HOME='$TMP_DIR/xdg-state' XDG_CACHE_HOME='$TMP_DIR/xdg-cache' FAKE_CODEX_LOG='$FAKE_CODEX_LOG' FAKE_CODEX_MUTATE_FILE='$mutate_file' FAKE_CODEX_OLD_ID='$old_id' FAKE_CODEX_NEW_ID='$new_id' PATH='$PATH_WITH_FAKE' '$SCRIPT_DIR/bin/csm' --cwd '$PROJECT_CWD' $manager_args" \
    >/dev/null
  local script_status="${PIPESTATUS[1]}"
  set -o pipefail
  if [[ "$script_status" -ne 0 ]]; then
    printf 'TUI script run failed with exit %s\n' "$script_status" >&2
    exit "$script_status"
  fi
}

start_fake_writer() {
  local file="$1"
  local process_name="$2"
  local writer_tag="${RANDOM}-${RANDOM}"
  local ready_file="$TMP_DIR/writer-$writer_tag.ready"
  WRITER_SIGNAL_LOG="$TMP_DIR/writer-$writer_tag.signal"
  WRITER_CLOSE_TRIGGER="$TMP_DIR/writer-$writer_tag.close"
  : > "$WRITER_SIGNAL_LOG"

  (
    exec -a "$process_name" node "$TMP_DIR/fake-codex-writer.js" \
      "$file" "$ready_file" "$WRITER_SIGNAL_LOG" "$WRITER_CLOSE_TRIGGER"
  ) &
  WRITER_PID=$!
  WRITER_PIDS+=("$WRITER_PID")

  local attempt
  for attempt in {1..100}; do
    if [[ -s "$ready_file" ]] && kill -0 "$WRITER_PID" 2>/dev/null; then
      return
    fi
    sleep 0.02
  done
  fail "fake writer did not become ready: $WRITER_PID"
}

assert_writer_alive_without_sigterm() {
  local pid="$1"
  local signal_log="$2"
  kill -0 "$pid" 2>/dev/null || fail "writer exited unexpectedly: $pid"
  [[ ! -s "$signal_log" ]] || fail "writer received SIGTERM unexpectedly: $pid"
}

stop_fake_writer() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" || true
  fi
  wait "$pid" 2>/dev/null || true
  forget_fake_writer "$pid"
}

forget_fake_writer() {
  local target_pid="$1"
  local writer_pid
  local remaining=()
  for writer_pid in "${WRITER_PIDS[@]}"; do
    if [[ "$writer_pid" != "$target_pid" ]]; then
      remaining+=("$writer_pid")
    fi
  done
  WRITER_PIDS=("${remaining[@]}")
}

assert_fake_calls() {
  local expected="$1"
  local actual
  actual="$(cat "$FAKE_CODEX_LOG")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'fake codex calls mismatch\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
  : > "$FAKE_CODEX_LOG"
}

assert_no_fake_calls() {
  if [[ -s "$FAKE_CODEX_LOG" ]]; then
    printf 'expected no fake codex calls, got:\n%s\n' "$(cat "$FAKE_CODEX_LOG")" >&2
    exit 1
  fi
}

assert_quarantined_file() {
  local source="$1"
  local id="$2"
  local found
  if [[ -e "$source" ]]; then
    printf 'expected source to be moved to quarantine: %s\n' "$source" >&2
    exit 1
  fi
  found="$(find "$QUARANTINE_ROOT" -type f -name "$(basename -- "$source")" -print)"
  if [[ -z "$found" || "$(wc -l <<< "$found")" -ne 1 ]]; then
    printf 'expected exactly one quarantined copy for %s, got:\n%s\n' "$source" "$found" >&2
    exit 1
  fi
  SOURCE_PATH="$source" QUARANTINED_PATH="$found" SESSION_ID="$id" QUARANTINE_ROOT="$QUARANTINE_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const relative = path.relative(process.env.QUARANTINE_ROOT, process.env.QUARANTINED_PATH);
const batch = relative.split(path.sep)[0];
const manifest = JSON.parse(fs.readFileSync(path.join(process.env.QUARANTINE_ROOT, batch, 'manifest.json'), 'utf8'));
const item = manifest.items.find((candidate) => candidate.id === process.env.SESSION_ID);
if (manifest.status !== 'complete' || !item || item.originalPath !== process.env.SOURCE_PATH) {
  throw new Error(`invalid quarantine manifest for ${process.env.SESSION_ID}`);
}
if (path.join(process.env.QUARANTINE_ROOT, batch, item.storedRelativePath) !== process.env.QUARANTINED_PATH) {
  throw new Error(`storedRelativePath mismatch for ${process.env.SESSION_ID}`);
}
NODE
}

quarantined_path() {
  local source="$1"
  local found
  found="$(find "$QUARANTINE_ROOT" -type f -name "$(basename -- "$source")" -print)"
  if [[ -z "$found" || "$(wc -l <<< "$found")" -ne 1 ]]; then
    printf 'expected exactly one quarantined copy for %s, got:\n%s\n' "$source" "$found" >&2
    exit 1
  fi
  printf '%s\n' "$found"
}

quarantine_batch_dir() {
  local source="$1"
  local stored relative batch
  stored="$(quarantined_path "$source")"
  relative="${stored#"$QUARANTINE_ROOT"/}"
  batch="${relative%%/*}"
  if [[ -z "$batch" || "$batch" == "$relative" ]]; then
    fail "could not derive quarantine batch for $source"
  fi
  printf '%s/%s\n' "$QUARANTINE_ROOT" "$batch"
}

assert_not_quarantined() {
  local source="$1"
  if [[ -d "$QUARANTINE_ROOT" ]] && find "$QUARANTINE_ROOT" -type f -name "$(basename -- "$source")" -print -quit | grep -q .; then
    printf 'file should not exist in quarantine: %s\n' "$source" >&2
    exit 1
  fi
}

start_identity_mutation_during_confirmation() {
  local file="$1"
  local old_id="$2"
  local new_id="$3"
  (
    sleep 3.2
    sed "1s/$old_id/$new_id/" "$file" > "$file.next"
    mv -- "$file.next" "$file"
  ) &
  MUTATOR_PID=$!
}

case_a_file="$(write_session sessions "$uuid_a" "$uuid_a" "2026-07-20T00:00:01" "case A later parent metadata")"
append_parent_meta "$case_a_file" "$uuid_b" "2026-07-20T00:00:01"
write_subagent_with_parent_meta "$uuid_c" "$uuid_d" "2026-07-20T00:00:02" "case B subagent parent metadata"
case_c_file="$(write_session sessions "$uuid_e" "$uuid_f" "2026-07-20T00:00:03" "case C mismatched ids")"
write_no_filename_uuid "$uuid_g" "2026-07-20T00:00:04" "case D missing filename uuid"
write_session_missing_payload_id "$uuid_h" "2026-07-20T00:00:05" "case E missing payload id"
case_f_file="$(write_session sessions "$uuid_i" "$uuid_i" "2026-07-20T00:00:06" "case F malformed later line")"
printf '{bad json\n' >> "$case_f_file"
write_session sessions "${uuid_j^^}" "$uuid_j" "2026-07-20T00:00:07" "case K uppercase filename id" >/dev/null
terminal_control_file="$(write_session_with_terminal_controls "$uuid_u" "2026-07-20T00:00:08")"
write_non_rollout_filename "$uuid_aa" "2026-07-20T00:00:09" "case N non rollout filename"
write_thread_title "$uuid_a" "case A renamed title" "case A later parent metadata"
write_thread_title "$uuid_c" "case B subagent parent metadata" "case B subagent parent metadata"

json_output="$(isolated_env "$SCRIPT_DIR/bin/csm" --cwd "$PROJECT_CWD" --list all --json)"
assert_json_entry "$json_output" "case A later parent metadata" "entry.id === '$uuid_a' && entry.mutationSafe === true"
assert_json_entry "$json_output" "case A later parent metadata" "entry.title === 'case A renamed title'"
assert_json_entry "$json_output" "case B subagent parent metadata" "entry.id === '$uuid_c' && entry.mutationSafe === true"
assert_json_entry "$json_output" "case B subagent parent metadata" "entry.title === ''"
assert_json_entry "$json_output" "case C mismatched ids" "entry.mutationSafe === false && /mismatch/i.test(entry.unsafeReason || '')"
assert_json_entry "$json_output" "case D missing filename uuid" "entry.mutationSafe === false && /filename/i.test(entry.unsafeReason || '')"
assert_json_entry "$json_output" "case E missing payload id" "entry.mutationSafe === false && /session_meta/i.test(entry.unsafeReason || '')"
assert_json_entry "$json_output" "case F malformed later line" "entry.id === '$uuid_i' && entry.mutationSafe === true"
assert_json_entry "$json_output" "case K uppercase filename id" "entry.id === '$uuid_j' && entry.mutationSafe === true"
assert_json_entry "$json_output" "case L terminal spoof" "entry.summary === 'case L terminal spoof' && !/[\\u0000-\\u001f\\u007f-\\u009f]/.test(entry.summary)"
assert_json_entry "$json_output" "case N non rollout filename" "entry.mutationSafe === false && /filename/i.test(entry.unsafeReason || '')"

list_output="$(isolated_env "$SCRIPT_DIR/bin/csm" --cwd "$PROJECT_CWD" --list all)"
assert_contains "$list_output" "unsafe:"
assert_contains "$list_output" "case A renamed title"
if LC_ALL=C grep -q "$(printf '\033')" <<< "$list_output"; then
  printf 'plain list output contains a terminal escape from transcript data\n' >&2
  exit 1
fi

run_tui "/case A renamed title\nq" "$TMP_DIR/renamed-title.log"
renamed_title_log="$(clean_log "$TMP_DIR/renamed-title.log")"
assert_contains "$renamed_title_log" "name: case A renamed title"
assert_contains "$renamed_title_log" "prompt: case A later parent metadata"

run_tui "/case B subagent parent metadata\nq" "$TMP_DIR/unrenamed-title.log"
unrenamed_title_log="$(clean_log "$TMP_DIR/unrenamed-title.log")"
assert_contains "$unrenamed_title_log" "name: case B subagent parent metadata"
assert_contains "$unrenamed_title_log" "prompt: case B subagent parent metadata"

if ! command -v script >/dev/null 2>&1; then
  printf 'script command is required; refusing to skip TUI mutation safety tests\n' >&2
  exit 1
fi

archive_file="$(write_session sessions "$uuid_l" "$uuid_l" "2026-07-20T00:01:01" "case G archive target")"
delete_file="$(write_session sessions "$uuid_m" "$uuid_m" "2026-07-20T00:01:02" "case G delete target")"
unarchive_file="$(write_session archived_sessions "$uuid_n" "$uuid_n" "2026-07-20T00:01:03" "case G unarchive target")"
multi_one_file="$(write_session sessions "$uuid_o" "$uuid_o" "2026-07-20T00:01:04" "case H multi one")"
multi_two_file="$(write_session sessions "$uuid_p" "$uuid_p" "2026-07-20T00:01:05" "case H multi two")"
safe_multi_file="$(write_session sessions "$uuid_t" "$uuid_t" "2026-07-20T00:01:06" "case I active safe")"
unsafe_multi_file="$(write_session sessions "$uuid_q" "$uuid_r" "2026-07-20T00:01:06" "case I active unsafe")"
cancel_file="$(write_session sessions "$uuid_s" "$uuid_s" "2026-07-20T00:01:07" "case J cancel target")"
unsafe_archived_file="$(write_session archived_sessions "$uuid_v" "$uuid_w" "2026-07-20T00:01:08" "case I archived unsafe")"
safe_archived_file="$(write_session archived_sessions "$uuid_x" "$uuid_x" "2026-07-20T00:01:09" "case I archived safe")"
toctou_file="$(write_session sessions "$uuid_y" "$uuid_y" "2026-07-20T00:01:10" "case M changed after confirmation")"
multi_archive_one_file="$(write_session sessions "$uuid_ab" "$uuid_ab" "2026-07-20T00:02:01" "case O multi archive one")"
multi_archive_two_file="$(write_session sessions "$uuid_ac" "$uuid_ac" "2026-07-20T00:02:02" "case O multi archive two")"
multi_unarchive_one_file="$(write_session archived_sessions "$uuid_ad" "$uuid_ad" "2026-07-20T00:02:03" "case P multi unarchive one")"
multi_unarchive_two_file="$(write_session archived_sessions "$uuid_ae" "$uuid_ae" "2026-07-20T00:02:04" "case P multi unarchive two")"
batch_second_file="$(write_session sessions "$uuid_ag" "$uuid_ag" "2026-07-20T00:02:05" "case Q batch recheck second")"
batch_first_file="$(write_session sessions "$uuid_af" "$uuid_af" "2026-07-20T00:02:06" "case Q batch recheck first")"
force_delete_file="$(write_session sessions "$uuid_ai" "$uuid_ai" "2026-07-20T00:02:07" "case R force delete target")"
writer_success_file="$(write_session sessions "$uuid_aj" "$uuid_aj" "2026-07-20T00:03:01" "case Writer recovery success")"
writer_wrong_confirmation_file="$(write_session sessions "$uuid_ak" "$uuid_ak" "2026-07-20T00:03:02" "case Writer wrong confirmation")"
writer_multi_one_file="$(write_session sessions "$uuid_al" "$uuid_al" "2026-07-20T00:03:03" "case Writer multiple selection one")"
writer_multi_two_file="$(write_session sessions "$uuid_am" "$uuid_am" "2026-07-20T00:03:04" "case Writer multiple selection two")"
writer_no_holder_file="$(write_session sessions "$uuid_an" "$uuid_an" "2026-07-20T00:03:05" "case Writer no local holder")"
writer_unrecognized_file="$(write_session sessions "$uuid_ao" "$uuid_ao" "2026-07-20T00:03:06" "case Writer unrecognized holder")"
writer_fd_disappears_file="$(write_session sessions "$uuid_ap" "$uuid_ap" "2026-07-20T00:03:07" "case Writer FD disappears during confirmation")"
writer_identity_changes_file="$(write_session sessions "$uuid_aq" "$uuid_aq" "2026-07-20T00:03:08" "case Writer file identity changes during confirmation")"
writer_archived_file="$(write_session archived_sessions "$uuid_ar" "$uuid_ar" "2026-07-20T00:03:09" "case Writer archived session")"
writer_multiple_holders_file="$(write_session sessions "$uuid_as" "$uuid_as" "2026-07-20T00:03:10" "case Writer multiple Codex holders")"
restore_success_file="$(write_session sessions "$uuid_at" "$uuid_at" "2026-07-20T00:04:01" "case S restore active success")"
restore_wrong_file="$(write_session sessions "$uuid_au" "$uuid_au" "2026-07-20T00:04:02" "case S restore wrong confirmation")"
restore_multi_one_file="$(write_session sessions "$uuid_av" "$uuid_av" "2026-07-20T00:04:03" "case S restore multi one")"
restore_multi_two_file="$(write_session sessions "$uuid_aw" "$uuid_aw" "2026-07-20T00:04:04" "case S restore multi two")"
restore_unsafe_file="$(write_session sessions "$uuid_ax" "$uuid_ax" "2026-07-20T00:04:05" "case S restore unsafe identity")"
restore_collision_file="$(write_session sessions "$uuid_ay" "$uuid_ay" "2026-07-20T00:04:06" "case S restore target collision")"
restore_toctou_file="$(write_session sessions "$uuid_az" "$uuid_az" "2026-07-20T00:04:07" "case S restore TOCTOU identity")"
restore_archived_file="$(write_session archived_sessions "$uuid_ba" "$uuid_ba" "2026-07-20T00:04:08" "case S restore archived success")"

# Writer recovery always uses a same-user fixture process. It never opens the
# user's CODEX_HOME or a real Codex process.
writer_success_digest="$(sha256sum "$writer_success_file")"
start_fake_writer "$writer_success_file" codex
writer_success_pid="$WRITER_PID"
writer_success_signal_log="$WRITER_SIGNAL_LOG"
run_tui "/case Writer recovery success\nxTERMINATE WRITER $uuid_aj $writer_success_pid\nq" "$TMP_DIR/writer-success.log"
for writer_wait_attempt in {1..100}; do
  if ! kill -0 "$writer_success_pid" 2>/dev/null; then
    break
  fi
  sleep 0.02
done
if kill -0 "$writer_success_pid" 2>/dev/null; then
  clean_log "$TMP_DIR/writer-success.log" >&2
  fail 'writer recovery did not terminate the fake Codex writer'
fi
wait "$writer_success_pid"
forget_fake_writer "$writer_success_pid"
assert_contains "$(clean_log "$TMP_DIR/writer-success.log")" "Required input: TERMINATE WRITER $uuid_aj $writer_success_pid"
assert_contains "$(clean_log "$TMP_DIR/writer-success.log")" "Writer recovery succeeded"
assert_contains "$(cat "$writer_success_signal_log")" 'SIGTERM'
[[ -e "$writer_success_file" ]] || fail 'writer recovery changed the transcript file'
[[ "$(sha256sum "$writer_success_file")" == "$writer_success_digest" ]] || \
  fail 'writer recovery modified the transcript content'

start_fake_writer "$writer_wrong_confirmation_file" codex
writer_wrong_pid="$WRITER_PID"
writer_wrong_signal_log="$WRITER_SIGNAL_LOG"
run_tui "/case Writer wrong confirmation\nxWRONG\nq" "$TMP_DIR/writer-wrong-confirmation.log"
assert_writer_alive_without_sigterm "$writer_wrong_pid" "$writer_wrong_signal_log"
assert_contains "$(clean_log "$TMP_DIR/writer-wrong-confirmation.log")" "Writer recovery cancelled"
stop_fake_writer "$writer_wrong_pid"

start_fake_writer "$case_c_file" codex
writer_unsafe_pid="$WRITER_PID"
writer_unsafe_signal_log="$WRITER_SIGNAL_LOG"
run_tui "/case C mismatched ids\nx\nq" "$TMP_DIR/writer-unsafe-identity.log"
assert_writer_alive_without_sigterm "$writer_unsafe_pid" "$writer_unsafe_signal_log"
assert_contains "$(clean_log "$TMP_DIR/writer-unsafe-identity.log")" "Blocked writer recovery"
stop_fake_writer "$writer_unsafe_pid"

start_fake_writer "$writer_multi_one_file" codex
writer_multi_pid="$WRITER_PID"
writer_multi_signal_log="$WRITER_SIGNAL_LOG"
run_tui "/case Writer multiple selection\nAxq" "$TMP_DIR/writer-multiple-selection.log"
assert_writer_alive_without_sigterm "$writer_multi_pid" "$writer_multi_signal_log"
assert_contains "$(clean_log "$TMP_DIR/writer-multiple-selection.log")" "Writer recovery is blocked for multiple selected sessions"
stop_fake_writer "$writer_multi_pid"

start_fake_writer "$writer_multiple_holders_file" codex
writer_holder_one_pid="$WRITER_PID"
writer_holder_one_signal_log="$WRITER_SIGNAL_LOG"
start_fake_writer "$writer_multiple_holders_file" codex
writer_holder_two_pid="$WRITER_PID"
writer_holder_two_signal_log="$WRITER_SIGNAL_LOG"
run_tui "/case Writer multiple Codex holders\nx\nq" "$TMP_DIR/writer-multiple-holders.log"
assert_writer_alive_without_sigterm "$writer_holder_one_pid" "$writer_holder_one_signal_log"
assert_writer_alive_without_sigterm "$writer_holder_two_pid" "$writer_holder_two_signal_log"
assert_contains "$(clean_log "$TMP_DIR/writer-multiple-holders.log")" "2 Codex writer candidates hold this transcript"
stop_fake_writer "$writer_holder_one_pid"
stop_fake_writer "$writer_holder_two_pid"

run_tui "/case Writer no local holder\nxq" "$TMP_DIR/writer-no-holder.log"
assert_contains "$(clean_log "$TMP_DIR/writer-no-holder.log")" "No local writer holds this transcript"
[[ -e "$writer_no_holder_file" ]] || fail 'writer diagnostics changed a no-holder transcript'

run_tui "\t/case Writer archived session\nxq" "$TMP_DIR/writer-archived.log"
assert_contains "$(clean_log "$TMP_DIR/writer-archived.log")" "Writer recovery is available only for active sessions"
[[ -e "$writer_archived_file" ]] || fail 'writer recovery changed an archived transcript'

start_fake_writer "$writer_unrecognized_file" holder
writer_unrecognized_pid="$WRITER_PID"
writer_unrecognized_signal_log="$WRITER_SIGNAL_LOG"
run_tui "/case Writer unrecognized holder\nx\nq" "$TMP_DIR/writer-unrecognized-holder.log"
assert_writer_alive_without_sigterm "$writer_unrecognized_pid" "$writer_unrecognized_signal_log"
assert_contains "$(clean_log "$TMP_DIR/writer-unrecognized-holder.log")" "unrecognized holder (termination blocked)"
stop_fake_writer "$writer_unrecognized_pid"

start_fake_writer "$writer_fd_disappears_file" codex
writer_fd_disappears_pid="$WRITER_PID"
writer_fd_disappears_signal_log="$WRITER_SIGNAL_LOG"
(
  sleep 4
  : > "$WRITER_CLOSE_TRIGGER"
) &
writer_close_mutator_pid=$!
run_tui "/case Writer FD disappears during confirmation\nxTERMINATE WRITER $uuid_ap $writer_fd_disappears_pid\nq" "$TMP_DIR/writer-fd-disappears.log"
wait "$writer_close_mutator_pid"
wait "$writer_fd_disappears_pid"
forget_fake_writer "$writer_fd_disappears_pid"
[[ ! -s "$writer_fd_disappears_signal_log" ]] || fail 'CSM sent SIGTERM after writer FD disappeared'
assert_contains "$(clean_log "$TMP_DIR/writer-fd-disappears.log")" "PID $writer_fd_disappears_pid exited before SIGTERM"

start_fake_writer "$writer_identity_changes_file" codex
writer_identity_changes_pid="$WRITER_PID"
writer_identity_changes_signal_log="$WRITER_SIGNAL_LOG"
(
  sleep 5.3
  cp -- "$writer_identity_changes_file" "$writer_identity_changes_file.next"
  mv -- "$writer_identity_changes_file.next" "$writer_identity_changes_file"
) &
writer_identity_mutator_pid=$!
run_tui "/case Writer file identity changes during confirmation\nxTERMINATE WRITER $uuid_aq $writer_identity_changes_pid\nq" "$TMP_DIR/writer-identity-changes.log"
wait "$writer_identity_mutator_pid"
assert_writer_alive_without_sigterm "$writer_identity_changes_pid" "$writer_identity_changes_signal_log"
assert_contains "$(clean_log "$TMP_DIR/writer-identity-changes.log")" "target dev/inode changed before SIGTERM"
stop_fake_writer "$writer_identity_changes_pid"

run_tui "/case G archive target\nbq" "$TMP_DIR/archive.log"
assert_fake_calls "archive $uuid_l"
assert_contains "$(clean_log "$TMP_DIR/archive.log")" "$uuid_l"

run_tui "/case G delete target\ndQUARANTINE $uuid_m\nq" "$TMP_DIR/delete.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/delete.log")" "Required input: QUARANTINE $uuid_m"
assert_quarantined_file "$delete_file" "$uuid_m"

run_tui "\t/case G unarchive target\nuq" "$TMP_DIR/unarchive.log"
assert_fake_calls "unarchive $uuid_n"
assert_contains "$(clean_log "$TMP_DIR/unarchive.log")" "$uuid_n"

run_tui "/case H multi\nAdQUARANTINE $uuid_p $uuid_o\nq" "$TMP_DIR/multi-delete.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/multi-delete.log")" "$uuid_p"
assert_contains "$(clean_log "$TMP_DIR/multi-delete.log")" "$uuid_o"
assert_quarantined_file "$multi_two_file" "$uuid_p"
assert_quarantined_file "$multi_one_file" "$uuid_o"

# Quarantine browsing and restore use only isolated fixture JSONLs. Restore
# requires every full UUID and never invokes the Codex CLI.
restore_success_digest="$(sha256sum "$restore_success_file")"
restore_archived_digest="$(sha256sum "$restore_archived_file")"
restore_multi_one_digest="$(sha256sum "$restore_multi_one_file")"
restore_multi_two_digest="$(sha256sum "$restore_multi_two_file")"
run_tui "/case S restore\nAdQUARANTINE $uuid_az $uuid_ay $uuid_ax $uuid_aw $uuid_av $uuid_au $uuid_at\nq" "$TMP_DIR/restore-fixture-quarantine.log"
assert_no_fake_calls
assert_quarantined_file "$restore_success_file" "$uuid_at"
assert_quarantined_file "$restore_wrong_file" "$uuid_au"
assert_quarantined_file "$restore_multi_one_file" "$uuid_av"
assert_quarantined_file "$restore_multi_two_file" "$uuid_aw"
assert_quarantined_file "$restore_unsafe_file" "$uuid_ax"
assert_quarantined_file "$restore_collision_file" "$uuid_ay"
assert_quarantined_file "$restore_toctou_file" "$uuid_az"

run_tui "\t/case S restore archived success\ndQUARANTINE $uuid_ba\nq" "$TMP_DIR/restore-archived-quarantine.log"
assert_no_fake_calls
assert_quarantined_file "$restore_archived_file" "$uuid_ba"

malformed_batch="$QUARANTINE_ROOT/malformed-review-fixture"
mkdir -p "$malformed_batch"
printf '{"broken":\n' > "$malformed_batch/manifest.json"

root_error_quarantine="$TMP_DIR/quarantine-root-is-a-file"
printf 'not a directory\n' > "$root_error_quarantine"
root_error_json="$(isolated_env "$SCRIPT_DIR/bin/csm" --cwd "$PROJECT_CWD" --quarantine-dir "$root_error_quarantine" --list quarantine --json)"
JSON_INPUT="$root_error_json" ROOT_PATH="$root_error_quarantine" node <<'NODE'
const data = JSON.parse(process.env.JSON_INPUT);
const diagnostic = (data.quarantine || []).find((entry) => entry.inventoryDiagnostic);
if (!diagnostic || diagnostic.file !== process.env.ROOT_PATH || !/quarantine root could not be read/i.test(diagnostic.unsafeReason || '')) {
  throw new Error(`missing quarantine root diagnostic: ${JSON.stringify(data, null, 2)}`);
}
NODE

quarantine_json="$(isolated_env "$SCRIPT_DIR/bin/csm" --cwd "$PROJECT_CWD" --list quarantine --json)"
assert_json_entry "$quarantine_json" "case S restore active success" \
  "entry.state === 'quarantine' && entry.restoreState === 'active' && entry.originalPath === '$restore_success_file' && entry.mutationSafe === true"
assert_json_entry "$quarantine_json" "case S restore archived success" \
  "entry.state === 'quarantine' && entry.restoreState === 'archived' && entry.originalPath === '$restore_archived_file' && entry.mutationSafe === true"
JSON_INPUT="$quarantine_json" MANIFEST_PATH="$malformed_batch/manifest.json" node <<'NODE'
const data = JSON.parse(process.env.JSON_INPUT);
const diagnostic = (data.quarantine || []).find((entry) => entry.manifestPath === process.env.MANIFEST_PATH);
if (!diagnostic || !diagnostic.inventoryDiagnostic || diagnostic.mutationSafe || !/manifest could not be read/i.test(diagnostic.unsafeReason || '')) {
  throw new Error(`missing malformed manifest diagnostic: ${JSON.stringify(data, null, 2)}`);
}
NODE

all_with_quarantine_json="$(isolated_env "$SCRIPT_DIR/bin/csm" --cwd "$PROJECT_CWD" --list all --json)"
JSON_INPUT="$all_with_quarantine_json" node <<'NODE'
const data = JSON.parse(process.env.JSON_INPUT);
if (!Array.isArray(data.quarantine) || data.quarantine.length === 0) {
  throw new Error('normal --list all did not include quarantined sessions');
}
NODE
force_all_json="$(isolated_env "$SCRIPT_DIR/bin/csm" --cwd "$PROJECT_CWD" --list all --json --force)"
JSON_INPUT="$force_all_json" node <<'NODE'
const data = JSON.parse(process.env.JSON_INPUT);
if ('quarantine' in data) {
  throw new Error('--force unexpectedly exposed a quarantine view');
}
NODE

run_tui "\t\t/case S restore multi\nAuRESTORE $uuid_aw $uuid_av\nq" "$TMP_DIR/restore-multiple-selection.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/restore-multiple-selection.log")" "Required input: RESTORE $uuid_aw $uuid_av"
assert_contains "$(clean_log "$TMP_DIR/restore-multiple-selection.log")" "Restored 2 sessions (2 active)"
[[ -e "$restore_multi_one_file" ]] || fail 'same-batch multi restore did not recreate the first original path'
[[ -e "$restore_multi_two_file" ]] || fail 'same-batch multi restore did not recreate the second original path'
[[ "$(sha256sum "$restore_multi_one_file")" == "$restore_multi_one_digest" ]] || fail 'same-batch multi restore modified the first transcript'
[[ "$(sha256sum "$restore_multi_two_file")" == "$restore_multi_two_digest" ]] || fail 'same-batch multi restore modified the second transcript'
assert_not_quarantined "$restore_multi_one_file"
assert_not_quarantined "$restore_multi_two_file"
if find "$QUARANTINE_ROOT" -type f -name '.restore.lock' -print -quit | grep -q .; then
  fail 'successful same-batch multi restore left a batch lock behind'
fi

run_tui "\t\t/case S restore wrong confirmation\nuWRONG\nq" "$TMP_DIR/restore-wrong-confirmation.log"
assert_contains "$(clean_log "$TMP_DIR/restore-wrong-confirmation.log")" "Restore cancelled"
assert_quarantined_file "$restore_wrong_file" "$uuid_au"

restore_lock_batch="$(quarantine_batch_dir "$restore_wrong_file")"
printf '{"fixture":"active restore"}\n' > "$restore_lock_batch/.restore.lock"
run_tui "\t\t/case S restore wrong confirmation\nuRESTORE $uuid_au\nq" "$TMP_DIR/restore-batch-lock.log"
assert_contains "$(clean_log "$TMP_DIR/restore-batch-lock.log")" "another CSM restore is active for this quarantine batch"
assert_quarantined_file "$restore_wrong_file" "$uuid_au"
rm -f -- "$restore_lock_batch/.restore.lock"

printf 'collision fixture\n' > "$restore_collision_file"
run_tui "\t\t/case S restore target collision\nu\nq" "$TMP_DIR/restore-target-collision.log"
assert_contains "$(clean_log "$TMP_DIR/restore-target-collision.log")" "restore target already exists"
[[ "$(cat "$restore_collision_file")" == 'collision fixture' ]] || fail 'restore overwrote its collision target'
quarantined_path "$restore_collision_file" >/dev/null

restore_unsafe_quarantined="$(quarantined_path "$restore_unsafe_file")"
sed "1s/$uuid_ax/$uuid_a/" "$restore_unsafe_quarantined" > "$restore_unsafe_quarantined.next"
mv -- "$restore_unsafe_quarantined.next" "$restore_unsafe_quarantined"
run_tui "\t\t/case S restore unsafe identity\nu\nq" "$TMP_DIR/restore-unsafe-identity.log"
assert_contains "$(clean_log "$TMP_DIR/restore-unsafe-identity.log")" "Blocked restore"
[[ ! -e "$restore_unsafe_file" ]] || fail 'unsafe quarantined transcript was restored'
assert_quarantined_file "$restore_unsafe_file" "$uuid_ax"

run_tui "\t\t/case S restore\nAu\nq" "$TMP_DIR/restore-multi-unsafe.log"
assert_contains "$(clean_log "$TMP_DIR/restore-multi-unsafe.log")" "Blocked restore"
[[ ! -e "$restore_success_file" ]] || fail 'multi restore partially restored a safe transcript beside an unsafe target'
assert_quarantined_file "$restore_success_file" "$uuid_at"

restore_toctou_quarantined="$(quarantined_path "$restore_toctou_file")"
start_identity_mutation_during_confirmation "$restore_toctou_quarantined" "$uuid_az" "$uuid_b"
run_tui "\t\t/case S restore TOCTOU identity\nuRESTORE $uuid_az\n\nq" "$TMP_DIR/restore-toctou.log"
wait "$MUTATOR_PID"
assert_contains "$(clean_log "$TMP_DIR/restore-toctou.log")" "Blocked restore"
[[ ! -e "$restore_toctou_file" ]] || fail 'changed quarantined transcript was restored'
assert_quarantined_file "$restore_toctou_file" "$uuid_az"

restore_active_batch="$(quarantine_batch_dir "$restore_success_file")"
restore_archived_batch="$(quarantine_batch_dir "$restore_archived_file")"
if [[ "$restore_active_batch" < "$restore_archived_batch" ]]; then
  restore_first_lock_batch="$restore_active_batch"
  restore_blocked_lock_batch="$restore_archived_batch"
else
  restore_first_lock_batch="$restore_archived_batch"
  restore_blocked_lock_batch="$restore_active_batch"
fi
printf '{"fixture":"cross-batch restore"}\n' > "$restore_blocked_lock_batch/.restore.lock"
run_tui "\t\t/case S restore a\nAuRESTORE $uuid_ba $uuid_at\nq" "$TMP_DIR/restore-cross-batch-lock.log"
assert_contains "$(clean_log "$TMP_DIR/restore-cross-batch-lock.log")" "another CSM restore is active for this quarantine batch"
assert_quarantined_file "$restore_success_file" "$uuid_at"
assert_quarantined_file "$restore_archived_file" "$uuid_ba"
[[ ! -e "$restore_first_lock_batch/.restore.lock" ]] || fail 'cross-batch lock contention left the earlier acquired lock behind'
rm -f -- "$restore_blocked_lock_batch/.restore.lock"

run_tui "\t\t/case S restore a\nAuRESTORE $uuid_ba $uuid_at\nq" "$TMP_DIR/restore-cross-batch-success.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/restore-cross-batch-success.log")" "Required input: RESTORE $uuid_ba $uuid_at"
assert_contains "$(clean_log "$TMP_DIR/restore-cross-batch-success.log")" "Restored 2 sessions (1 active, 1 archived)"
[[ -e "$restore_success_file" ]] || fail 'active quarantine restore did not recreate the original path'
[[ "$(sha256sum "$restore_success_file")" == "$restore_success_digest" ]] || fail 'active quarantine restore modified transcript contents'
assert_not_quarantined "$restore_success_file"
[[ -e "$restore_archived_file" ]] || fail 'archived quarantine restore did not recreate the original path'
[[ "$(sha256sum "$restore_archived_file")" == "$restore_archived_digest" ]] || fail 'archived quarantine restore modified transcript contents'
assert_not_quarantined "$restore_archived_file"
if find "$QUARANTINE_ROOT" -type f -name '.restore.lock' -print -quit | grep -q .; then
  fail 'successful cross-batch multi restore left a batch lock behind'
fi

run_tui "/case O multi archive\nAbq" "$TMP_DIR/multi-archive.log"
assert_fake_calls $'archive '"$uuid_ac"$'\narchive '"$uuid_ab"
assert_contains "$(clean_log "$TMP_DIR/multi-archive.log")" "$uuid_ac"
assert_contains "$(clean_log "$TMP_DIR/multi-archive.log")" "$uuid_ab"

run_tui "\t/case P multi unarchive\nAuq" "$TMP_DIR/multi-unarchive.log"
assert_fake_calls $'unarchive '"$uuid_ae"$'\nunarchive '"$uuid_ad"
assert_contains "$(clean_log "$TMP_DIR/multi-unarchive.log")" "$uuid_ae"
assert_contains "$(clean_log "$TMP_DIR/multi-unarchive.log")" "$uuid_ad"

run_tui "/case C mismatched ids\nb\nq" "$TMP_DIR/unsafe-single-archive.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-single-archive.log")" "Blocked archive"

run_tui "/case C mismatched ids\nd\nq" "$TMP_DIR/unsafe-single-delete.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-single-delete.log")" "Blocked quarantine"

run_tui "/case D missing filename uuid\nb\nq" "$TMP_DIR/unsafe-missing-filename.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-missing-filename.log")" "filename UUID is missing or invalid"

run_tui "/case E missing payload id\nd\nq" "$TMP_DIR/unsafe-missing-meta-id.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-missing-meta-id.log")" "first session_meta payload.id is missing"

run_tui "/case N non rollout filename\nb\nq" "$TMP_DIR/unsafe-non-rollout.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-non-rollout.log")" "filename UUID is missing or invalid"

run_tui "\t/case I archived unsafe\nu\nq" "$TMP_DIR/unsafe-single-unarchive.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-single-unarchive.log")" "Blocked unarchive"

run_tui "/case I active\nAb\nq" "$TMP_DIR/unsafe-multi-archive.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-multi-archive.log")" "Blocked archive"

run_tui "/case I active\nAd\nq" "$TMP_DIR/unsafe-multi-delete.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-multi-delete.log")" "Blocked quarantine"

run_tui "\t/case I archived\nAu\nq" "$TMP_DIR/unsafe-multi-unarchive.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/unsafe-multi-unarchive.log")" "Blocked unarchive"

run_tui "/case J cancel target\ndWRONG\nq" "$TMP_DIR/cancel-delete.log"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/cancel-delete.log")" "Quarantine cancelled"
[[ -e "$cancel_file" ]]

run_tui "/case L terminal spoof\ndQUARANTINE $uuid_u\nq" "$TMP_DIR/terminal-controls.log"
assert_no_fake_calls
assert_quarantined_file "$terminal_control_file" "$uuid_u"
if LC_ALL=C grep -q "$(printf '\033')\[2J" "$TMP_DIR/terminal-controls.log"; then
  printf 'transcript-provided terminal clear sequence reached TUI output\n' >&2
  exit 1
fi

start_identity_mutation_during_confirmation "$toctou_file" "$uuid_y" "$uuid_z"
run_tui "/case M changed after confirmation\ndQUARANTINE $uuid_y\n\nq" "$TMP_DIR/toctou.log"
wait "$MUTATOR_PID"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/toctou.log")" "Required input: QUARANTINE $uuid_y"
assert_contains "$(clean_log "$TMP_DIR/toctou.log")" "Blocked quarantine"

run_tui "/case Q batch recheck\nAbq" "$TMP_DIR/batch-recheck.log" "$batch_second_file" "$uuid_ag" "$uuid_ah"
assert_fake_calls "archive $uuid_af"
assert_contains "$(clean_log "$TMP_DIR/batch-recheck.log")" "Blocked archive"

run_tui "/case R force delete target\ndFORCE DELETE $uuid_ai\nq" "$TMP_DIR/force-delete.log" "" "" "" "--force"
assert_no_fake_calls
assert_contains "$(clean_log "$TMP_DIR/force-delete.log")" "Required input: FORCE DELETE $uuid_ai"
if [[ -e "$force_delete_file" ]]; then
  printf 'force delete left source in place: %s\n' "$force_delete_file" >&2
  exit 1
fi
assert_not_quarantined "$force_delete_file"

installer_home="$TMP_DIR/installer-home"
mkdir -p "$installer_home"
printf '%s\n' \
  '# keep installer fixture' \
  'export BACKUP_PATH="$HOME/.local/bin"' > "$installer_home/.bashrc"
HOME="$installer_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$installer_home/install.out"
[ -L "$installer_home/.local/bin/csm" ] || \
  fail 'installer did not create the csm symlink'
[ "$(readlink "$installer_home/.local/bin/csm")" = "$SCRIPT_DIR/bin/csm" ] || \
  fail 'installer created a link to the wrong executable'
assert_contains "$(cat "$installer_home/.bashrc")" '# >>> script-store csm >>>'
HOME="$installer_home" CODEX_HOME="$TEST_CODEX_HOME" PATH="$installer_home/.local/bin:$PATH_WITH_FAKE" \
  csm --cwd "$PROJECT_CWD" --list active >/dev/null

HOME="$installer_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$installer_home/reinstall.out"
if [ "$(grep -F -c '# >>> script-store csm >>>' "$installer_home/.bashrc")" -ne 1 ]; then
  fail 'installer duplicated its managed PATH block'
fi

HOME="$installer_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall \
  > "$installer_home/uninstall.out"
[ ! -e "$installer_home/.local/bin/csm" ] && \
  [ ! -L "$installer_home/.local/bin/csm" ] || \
  fail 'uninstall left the managed csm link behind'
assert_contains "$(cat "$installer_home/.bashrc")" '# keep installer fixture'
if grep -F -q '# >>> script-store csm >>>' "$installer_home/.bashrc"; then
  fail 'uninstall left the managed PATH block behind'
fi

collision_home="$TMP_DIR/installer-collision-home"
mkdir -p "$collision_home/.local/bin"
printf 'user-owned executable\n' > "$collision_home/.local/bin/csm"
set +e
HOME="$collision_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$collision_home/stdout" 2> "$collision_home/stderr"
collision_status=$?
set -e
[ "$collision_status" -ne 0 ] || fail 'installer accepted a conflicting executable'
[ "$(cat "$collision_home/.local/bin/csm")" = 'user-owned executable' ] || \
  fail 'installer overwrote a conflicting executable'
assert_contains "$(cat "$collision_home/stderr")" 'refusing to overwrite'

modified_home="$TMP_DIR/installer-modified-home"
mkdir -p "$modified_home/.local/bin"
ln -s "$SCRIPT_DIR/bin/csm" "$modified_home/.local/bin/csm"
printf '%s\n' \
  '# >>> script-store csm >>>' \
  'export PATH="$HOME/.local/bin:$PATH"' \
  'export KEEP_USER_LINE=1' \
  '# <<< script-store csm <<<' > "$modified_home/.zshrc"
cp "$modified_home/.zshrc" "$modified_home/.zshrc.before"
set +e
HOME="$modified_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall \
  > "$modified_home/stdout" 2> "$modified_home/stderr"
modified_status=$?
set -e
[ "$modified_status" -ne 0 ] || fail 'uninstaller accepted a modified managed block'
[ -L "$modified_home/.local/bin/csm" ] || \
  fail 'uninstaller removed the link before marker preflight'
cmp -s "$modified_home/.zshrc.before" "$modified_home/.zshrc" || \
  fail 'uninstaller changed a modified managed block'

dry_home="$TMP_DIR/installer-dry-home"
HOME="$dry_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --dry-run \
  > "$TMP_DIR/installer-dry-run.out"
[ ! -e "$dry_home" ] || fail 'installer dry-run changed the temporary HOME'
assert_contains "$(cat "$TMP_DIR/installer-dry-run.out")" 'Would create link'
assert_contains "$(cat "$TMP_DIR/installer-dry-run.out")" 'Would add the managed PATH block'

printf '%s\n' "$archive_file" "$delete_file" "$unarchive_file" "$multi_one_file" "$multi_two_file" \
  "$safe_multi_file" "$unsafe_multi_file" "$cancel_file" "$unsafe_archived_file" "$safe_archived_file" \
  "$terminal_control_file" "$toctou_file" "$multi_archive_one_file" "$multi_archive_two_file" \
  "$multi_unarchive_one_file" "$multi_unarchive_two_file" "$batch_first_file" "$batch_second_file" \
  "$force_delete_file" >/dev/null

assert_no_fake_calls
printf 'smoke ok\n'
