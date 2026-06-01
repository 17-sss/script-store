#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MANAGER="$SCRIPT_DIR/agent-heartbeat.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

CONFIG="$TMP_DIR/agent-heartbeat.ini"
OUTPUT="$TMP_DIR/messages.log"

cat > "$CONFIG" <<EOF
[schedule]
cron=5 8,13,18,23 * * *
log_path=$TMP_DIR/cron.log

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
grep -Fxq "smoke heartbeat" "$OUTPUT"

"$MANAGER" run --config "$CONFIG" --target file-test --message "override heartbeat"
tail -n 1 "$OUTPUT" | grep -Fxq "override heartbeat"

"$MANAGER" run --config "$CONFIG" --target file-test --dry-run | grep -Fq "dry-run: file target=file-test"
"$MANAGER" cron --config "$CONFIG" | grep -Fq "5 8,13,18,23 * * *"

printf 'agent-heartbeat smoke test passed\n'
