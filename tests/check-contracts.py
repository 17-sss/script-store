#!/usr/bin/env python3
"""Read-only repository safety-contract and local-drift checks."""

from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
failures = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        failures.append(f"missing file: {relative}")
        return ""
    return path.read_text(encoding="utf-8")


def require(relative: str, *fragments: str) -> None:
    text = read(relative)
    for fragment in fragments:
        if fragment not in text:
            failures.append(f"{relative}: missing contract fragment {fragment!r}")


def forbid(relative: str, *fragments: str) -> None:
    text = read(relative)
    for fragment in fragments:
        if fragment in text:
            failures.append(f"{relative}: forbidden legacy fragment remains {fragment!r}")


require(
    "linux/agent-heartbeat/agent-heartbeat.sh",
    "timeout_seconds",
    "flock",
    '# BEGIN agent-heartbeat managed cron block',
    '# END agent-heartbeat managed cron block',
)
require(
    "linux/agent-heartbeat/smoke-test.sh",
    'export HOME="$TMP_DIR/home"',
    "MOCK_CRONTAB_STATE",
    "MOCK_TMUX_ARGS",
)

require(
    "linux/csm/bin/csm",
    "CODEX_SQLITE_HOME",
    "fs.readlinkSync(path.join('/proc', String(pid), 'exe'))",
    "checkedMutationTargets",
)
require(
    "linux/csm/smoke-test.sh",
    "CSM_SMOKE_PID_NAMESPACE",
    'TEST_CODEX_HOME="$TMP_DIR/codex-home"',
    'REAL_CODEX_HOME="${CODEX_HOME:-}"',
)

require(
    "linux/cxt/bin/cxt",
    "read-only + on-request approvals",
    "gpt-5.4 is not list-visible",
    "gpt-5.4-mini is not list-visible",
    'add_model_shortcut "$arg" gpt-6-astra',
    "validate_cxt_session_name",
    "/bin/cat",
)
forbid("linux/cxt/completions/cxt.bash", "--gpt54")
forbid("linux/cxt/completions/cxt.zsh", "--gpt54")
forbid("linux/cxt/completions/cxt.bash", "--mini")
forbid("linux/cxt/completions/cxt.zsh", "--mini")
require("linux/cxt/completions/cxt.bash", "--astra")
require("linux/cxt/completions/cxt.zsh", "--astra")

require(
    "linux/omx-guard/omx-guard.sh",
    '"format_version": 2',
    '"sensitive_data"',
    "manifest.sha256",
    "restore-plans",
    "OMX_GUARD_TEST_RESTORE_FAIL_STAGE_INDEX",
)
require(
    "linux/omx-guard/smoke-test.sh",
    'export HOME="$TMP_ROOT/home"',
    'export PATH="$ISOLATED_BIN"',
    "payload-corrupt",
    "OMX_GUARD_TEST_RESTORE_INTERRUPT_INDEX",
)

require(
    "windows/devtunnel/devtunnel-manager.ps1",
    "[System.IO.File]::Replace",
    "Conflicting devtunnel profile markers",
    'ExitOnForwardFailure=yes',
    '127.0.0.1:{0}:127.0.0.1:{0}',
)
forbid(
    "windows/devtunnel/devtunnel-manager.ps1",
    "Set-Content -Path $profilePath",
    '"{0}:127.0.0.1:{0}"',
)
require(
    "windows/devtunnel/smoke-test.ps1",
    "profile[fixture].ps1",
    "UTF-8 BOM was not preserved",
    "test-only profile replacement failure",
    "MockSshExitCode = 23",
)

for relative in (
    "windows/wsl-portproxy/setup.ps1",
    "windows/wsl-portproxy/uninstall.ps1",
):
    require(
        relative,
        'ValidateSet("Loopback", "Lan")',
        'owner = "script-store/wsl-portproxy"',
        "WSL_PORTPROXY_STATE_HOME",
        "Invoke-NativeChecked",
    )
forbid("windows/wsl-portproxy/uninstall.ps1", '"Vite $Port"')
require(
    "windows/wsl-portproxy/setup.ps1",
    'Profile = "Private"',
    'RemoteAddress = "LocalSubnet"',
    "Expected exactly one usable WSL IPv4 address",
    "Only WSL NAT mode is supported",
)
require(
    "windows/wsl-portproxy/smoke-test.ps1",
    'WSL_PORTPROXY_TEST_MODE = "1"',
    "mock firewall remove failure",
    "ownership state write failure",
)

require(
    "README.md",
    "tests/audit-smoke.sh",
    "windows\\wsl-portproxy\\smoke-test.ps1",
)

maintenance = read("linux/cxt/MAINTENANCE.md")
baseline_match = re.search(r"Codex CLI: `codex-cli ([^`]+)`", maintenance)
baseline = baseline_match.group(1) if baseline_match else "unknown"
codex = shutil.which("codex")
if codex is None:
    print(f"DRIFT codex: unavailable; documented baseline={baseline}")
else:
    try:
        result = subprocess.run(
            [codex, "--version"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
        live = result.stdout.strip() or f"exit {result.returncode}"
    except (OSError, subprocess.TimeoutExpired) as error:
        live = f"unavailable ({error})"
    status = "CURRENT" if baseline in live else "DRIFT"
    print(f"{status} codex: local={live}; documented baseline={baseline}")

for command in ("pwsh", "powershell.exe"):
    path = shutil.which(command)
    state = path if path else "unavailable (Windows smoke not executed here)"
    print(f"RUNTIME {command}: {state}")

if failures:
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    raise SystemExit(1)

print("PASS repository contract checks")
