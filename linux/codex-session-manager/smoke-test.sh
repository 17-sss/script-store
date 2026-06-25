#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/sessions/2026/06/25"
mkdir -p "$TMP_DIR/archived_sessions/2026/06/25"

cat > "$TMP_DIR/sessions/2026/06/25/rollout-2026-06-25T12-00-00-019f0000-0000-7000-8000-000000000001.jsonl" <<'JSONL'
{"timestamp":"2026-06-25T12:00:00.000Z","type":"session_meta","payload":{"id":"019f0000-0000-7000-8000-000000000001","timestamp":"2026-06-25T12:00:00.000Z","cwd":"/tmp/project","originator":"Codex CLI","source":"cli","thread_source":"user"}}
{"timestamp":"2026-06-25T12:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"active fixture prompt"}]}}
JSONL

cat > "$TMP_DIR/archived_sessions/2026/06/25/rollout-2026-06-25T12-01-00-019f0000-0000-7000-8000-000000000002.jsonl" <<'JSONL'
{"timestamp":"2026-06-25T12:01:00.000Z","type":"session_meta","payload":{"id":"019f0000-0000-7000-8000-000000000002","timestamp":"2026-06-25T12:01:00.000Z","cwd":"/tmp/project/subdir","originator":"Codex Desktop","source":"app","thread_source":"user"}}
{"timestamp":"2026-06-25T12:01:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"archived fixture prompt"}]}}
JSONL

output="$(CODEX_HOME="$TMP_DIR" "$SCRIPT_DIR/codex-session-manager.js" --cwd /tmp/project --list all)"

printf '%s\n' "$output" | grep -q "active sessions (1)"
printf '%s\n' "$output" | grep -q "archived sessions (1)"
printf '%s\n' "$output" | grep -q "active fixture prompt"
printf '%s\n' "$output" | grep -q "archived fixture prompt"

json_output="$(CODEX_HOME="$TMP_DIR" "$SCRIPT_DIR/codex-session-manager.js" --cwd /tmp/project --list all --json)"
printf '%s\n' "$json_output" | grep -q '"active"'
printf '%s\n' "$json_output" | grep -q '"archived"'

printf 'smoke ok\n'
