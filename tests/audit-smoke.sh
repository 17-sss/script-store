#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
MODE="full"

case "${1:-}" in
  "") ;;
  --full) MODE="full" ;;
  --quick) MODE="quick" ;;
  --contracts-only) MODE="contracts" ;;
  *) printf 'usage: %s [--full|--quick|--contracts-only]\n' "$0" >&2; exit 64 ;;
esac

RESULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/script-store-audit.XXXXXX")"
cleanup() {
  rm -f -- "$RESULTS_FILE"
}
trap cleanup EXIT

failures=0

record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS_FILE"
}

run_case() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  if "$@"; then
    record PASS "$name" executed
  else
    local status=$?
    record FAIL "$name" "exit=$status"
    failures=$((failures + 1))
  fi
}

skip_case() {
  record SKIP "$1" "$2"
}

cd -- "$REPO_ROOT"

run_case contracts python3 tests/check-contracts.py
if [[ "$MODE" == "contracts" ]]; then
  printf '\nSTATUS\tCHECK\tDETAIL\n'
  cat "$RESULTS_FILE"
  exit "$failures"
fi

run_case bash-syntax bash -n \
  linux/agent-heartbeat/agent-heartbeat.sh \
  linux/agent-heartbeat/smoke-test.sh \
  linux/csm/install-csm.sh \
  linux/csm/smoke-test.sh \
  linux/cxt/bin/cxt \
  linux/cxt/install-cxt.sh \
  linux/cxt/tests/test-cxt.sh \
  linux/omx-guard/omx-guard.sh \
  linux/omx-guard/smoke-test.sh \
  tests/audit-smoke.sh
run_case csm-node-syntax node --check linux/csm/bin/csm

platform="$(uname -s 2>/dev/null || printf unknown)"
case "$platform" in
  Linux)
    run_case agent-heartbeat linux/agent-heartbeat/smoke-test.sh
    run_case cxt linux/cxt/tests/test-cxt.sh
    run_case omx-guard linux/omx-guard/smoke-test.sh
    if [[ "$MODE" == "full" ]]; then
      run_case csm linux/csm/smoke-test.sh
    else
      skip_case csm "quick mode; full PID-namespace suite not executed"
    fi
    ;;
  Darwin)
    skip_case agent-heartbeat "Linux-only cron/flock suite"
    skip_case csm "Linux /proc and PID-namespace suite"
    run_case cxt linux/cxt/tests/test-cxt.sh
    run_case omx-guard linux/omx-guard/smoke-test.sh
    ;;
  *)
    skip_case linux-suites "unsupported shell-test platform: $platform"
    ;;
esac

if command -v pwsh >/dev/null 2>&1; then
  run_case devtunnel-pwsh pwsh -NoProfile -File windows/devtunnel/smoke-test.ps1
  run_case wsl-portproxy-pwsh pwsh -NoProfile -File windows/wsl-portproxy/smoke-test.ps1
else
  skip_case powershell-smoke "pwsh unavailable; Windows CI must execute it"
fi

printf '\nSTATUS\tCHECK\tDETAIL\n'
cat "$RESULTS_FILE"
if (( failures > 0 )); then
  printf '\n%d verification case(s) failed.\n' "$failures" >&2
  exit 1
fi
printf '\nAll executed verification cases passed; SKIP entries remain unverified here.\n'
