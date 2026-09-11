#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

if [[ "$#" -eq 0 ]]; then
  set -- "$ROOT"/linux/*/*.sh "$ROOT"/linux/cxt/bin/cxt \
    "$ROOT"/linux/cxt/tests/*.sh "$ROOT"/linux/cxt/completions/*.bash \
    "$ROOT"/tests/*.sh
fi

failed=0
for file in "$@"; do
  # bash -n accepts one script; extra paths would only become its arguments.
  if bash -n "$file"; then
    printf 'PASS bash syntax: %s\n' "$file"
  else
    printf 'FAIL bash syntax: %s\n' "$file" >&2
    failed=1
  fi
done
exit "$failed"
