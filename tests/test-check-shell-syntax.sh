#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/script-store-syntax.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

printf ':\n' > "$TMP_ROOT/valid.sh"
printf 'if then\n' > "$TMP_ROOT/invalid.sh"
if bash "$SCRIPT_DIR/check-shell-syntax.sh" "$TMP_ROOT/valid.sh" "$TMP_ROOT/invalid.sh" > "$TMP_ROOT/result" 2>&1; then
  printf 'syntax checker missed an invalid second file\n' >&2
  exit 1
fi
grep -Fq "PASS bash syntax: $TMP_ROOT/valid.sh" "$TMP_ROOT/result"
grep -Fq "FAIL bash syntax: $TMP_ROOT/invalid.sh" "$TMP_ROOT/result"
bash "$SCRIPT_DIR/check-shell-syntax.sh" "$TMP_ROOT/valid.sh"
printf 'shell syntax checker tests passed\n'
