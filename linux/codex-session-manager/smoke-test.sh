#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
REAL_HOME="${HOME:-}"
REAL_CODEX_HOME="${CODEX_HOME:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-session-manager-test.XXXXXX")"
TEST_HOME="$TMP_DIR/home"
TEST_CODEX_HOME="$TMP_DIR/codex-home"
TEST_BIN="$TMP_DIR/bin"
FAKE_CODEX_LOG="$TMP_DIR/fake-codex.log"
QUARANTINE_ROOT="$TMP_DIR/xdg-data/codex-session-manager/quarantine"
PATH_WITH_FAKE="$TEST_BIN:$PATH"
PROJECT_CWD="/tmp/codex-session-manager-project"

safe_cleanup() {
  local status=$?
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
const entries = [...(data.active || []), ...(data.archived || [])];
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
        time.sleep(0.08)
except BrokenPipeError:
    os._exit(0)
os._exit(0)
PY
  } | script -q -e -O "$log" -c \
    "stty cols 120 rows 28; env -u NVM_DIR -u FNM_DIR -u VOLTA_HOME HOME='$TEST_HOME' CODEX_HOME='$TEST_CODEX_HOME' XDG_CONFIG_HOME='$TMP_DIR/xdg-config' XDG_DATA_HOME='$TMP_DIR/xdg-data' XDG_STATE_HOME='$TMP_DIR/xdg-state' XDG_CACHE_HOME='$TMP_DIR/xdg-cache' FAKE_CODEX_LOG='$FAKE_CODEX_LOG' FAKE_CODEX_MUTATE_FILE='$mutate_file' FAKE_CODEX_OLD_ID='$old_id' FAKE_CODEX_NEW_ID='$new_id' PATH='$PATH_WITH_FAKE' '$SCRIPT_DIR/codex-session-manager.js' --cwd '$PROJECT_CWD' $manager_args" \
    >/dev/null
  local script_status="${PIPESTATUS[1]}"
  set -o pipefail
  if [[ "$script_status" -ne 0 ]]; then
    printf 'TUI script run failed with exit %s\n' "$script_status" >&2
    exit "$script_status"
  fi
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
write_session sessions "$uuid_e" "$uuid_f" "2026-07-20T00:00:03" "case C mismatched ids" >/dev/null
write_no_filename_uuid "$uuid_g" "2026-07-20T00:00:04" "case D missing filename uuid"
write_session_missing_payload_id "$uuid_h" "2026-07-20T00:00:05" "case E missing payload id"
case_f_file="$(write_session sessions "$uuid_i" "$uuid_i" "2026-07-20T00:00:06" "case F malformed later line")"
printf '{bad json\n' >> "$case_f_file"
write_session sessions "${uuid_j^^}" "$uuid_j" "2026-07-20T00:00:07" "case K uppercase filename id" >/dev/null
terminal_control_file="$(write_session_with_terminal_controls "$uuid_u" "2026-07-20T00:00:08")"
write_non_rollout_filename "$uuid_aa" "2026-07-20T00:00:09" "case N non rollout filename"
write_thread_title "$uuid_a" "case A renamed title" "case A later parent metadata"
write_thread_title "$uuid_c" "case B subagent parent metadata" "case B subagent parent metadata"

json_output="$(isolated_env "$SCRIPT_DIR/codex-session-manager.js" --cwd "$PROJECT_CWD" --list all --json)"
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

list_output="$(isolated_env "$SCRIPT_DIR/codex-session-manager.js" --cwd "$PROJECT_CWD" --list all)"
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

printf '%s\n' "$archive_file" "$delete_file" "$unarchive_file" "$multi_one_file" "$multi_two_file" \
  "$safe_multi_file" "$unsafe_multi_file" "$cancel_file" "$unsafe_archived_file" "$safe_archived_file" \
  "$terminal_control_file" "$toctou_file" "$multi_archive_one_file" "$multi_archive_two_file" \
  "$multi_unarchive_one_file" "$multi_unarchive_two_file" "$batch_first_file" "$batch_second_file" \
  "$force_delete_file" >/dev/null

assert_no_fake_calls
printf 'smoke ok\n'
