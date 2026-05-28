# HANDOFF

## Metadata

- Project: script-store
- Scope: repo
- Repo Root: .
- Branch: main
- Last Updated: 2026-05-28T14:33:57+09:00
- Updated By: Codex

## TL;DR

- Active work is `windows/devtunnel`: a PowerShell installer for a `devtunnel` SSH port-forward helper.
- The installer now offers a validated new-vs-existing SSH host setup flow.
- Existing SSH host mode installs only the PowerShell `devtunnel` function and leaves SSH config unchanged.
- Installer output now explicitly tells users to run `. $PROFILE` or restart PowerShell before using `devtunnel`.
- `uninstall` is accepted as an alias for `remove`, and generated `devtunnel` accepts positional ports such as `devtunnel 3123`.
- GNU-style `devtunnel --help` was removed from docs/tests/help text; supported help paths are `devtunnel -Help`, `devtunnel -h`, and `Get-Help devtunnel -Detailed`.

## Current Objective

Commit the latest UX fixes for profile loading guidance, `uninstall`, and positional port usage.

## Current State

### Completed

- `windows/devtunnel/README.md` was anonymized for a personal repository.
- `windows/devtunnel/devtunnel-manager.ps1` supports non-interactive test inputs, temp path overrides via `DEVTUNNEL_PROFILE_PATH` and `DEVTUNNEL_SSH_DIR`, `-Help`, and comment-based `Get-Help`.
- `windows/devtunnel/smoke-test.ps1` was added to exercise install, help, reinstall, and remove against temp files only.
- Empty `Get-Content -Raw` results are normalized through `Get-FileText`, fixing the earlier null regex failure.
- Console-facing manager output is ASCII English to avoid Windows PowerShell encoding garbling.
- Broken `--help` support claims were removed in favor of PowerShell-native `-Help` and `-h`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp` passed on Windows.
- `windows/devtunnel/devtunnel-manager.ps1` now has `-SshHostMode prompt|new|existing`.
- Existing SSH host mode parses `Host` aliases from SSH config for interactive selection and skips writing managed SSH blocks.
- `windows/devtunnel/smoke-test.ps1` now covers existing SSH host mode.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp` passed after the existing-host-mode changes.
- `git diff --check` passed after the existing-host-mode changes.
- Install output now prints the selected default ports in the suggested test command.
- `windows/devtunnel/devtunnel-manager.ps1 uninstall` is supported.
- Generated `devtunnel` marks `Ports` as positional, so `devtunnel 3123` works after the function is loaded.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp` passed after the latest UX fixes.

### In Progress

- Run `git diff --check` and commit the latest UX fixes.

### Needs Confirmation

- Actual manual install against real `$PROFILE` and real `~\.ssh\config`.

## Recent Changes

- Commit `cdb5bd0`: anonymized devtunnel README examples.
- Commit `a65ed6b`: hardened setup flow around identity file, SSH port validation, reinstall behavior, and managed block cleanup.
- Commit `b28ab98`: added smoke coverage and non-interactive manager options.
- Commit `043a297`: fixed empty temp-file reads and ASCII output after the first Windows smoke failure.
- Latest work: removed `--help` references from manager help text, smoke test, and README.
- Latest committed work: added install-time choice between new managed SSH host and existing SSH host alias.
- Latest local work: clarified profile loading, added `uninstall`, made ports positional, and printed selected test ports.

## Known Issues / Watch List

- No current smoke-test failures.
- Users must run `. $PROFILE` or restart PowerShell after install before `devtunnel` is available in the current shell.

## Quick Reference

### Files

- `windows/devtunnel/devtunnel-manager.ps1`
- `windows/devtunnel/smoke-test.ps1`
- `windows/devtunnel/README.md`

### Windows Smoke Command

- `cd windows\devtunnel`
- `.\smoke-test.ps1 -KeepTemp`

### Temp Inspection After `-KeepTemp`

- Temp root is printed by `smoke-test.ps1`.
- Inspect generated `profile.ps1`.
- Inspect generated `.ssh\config`.

### Real Install Command

- Run only after smoke passes: `.\devtunnel-manager.ps1 install`

## Validation

### Codex Linux Checks

- `git diff --check`: passed before the last commit.
- `git diff --check`: passed after the latest local changes.
- `commit-helper` commits succeeded through `043a297`.

### Codex Windows Checks

- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp`: passed on 2026-05-28.
- Temp root from the passing run: `C:\Users\User\AppData\Local\Temp\devtunnel-smoke-eb13af288eb8497389303bdcc95fe8a8`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp`: passed again after existing-host-mode changes on 2026-05-28.
- Temp root from the latest passing run: `C:\Users\User\AppData\Local\Temp\devtunnel-smoke-56db98b584dd4e5aa6a3cde870659080`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp`: passed after profile-loading/uninstall/positional-port fixes on 2026-05-28.
- Temp root from the latest passing run: `C:\Users\User\AppData\Local\Temp\devtunnel-smoke-223d869b6d294b95a6168d40cc4ee9ab`.

### Pending Checks

- `git diff --check` after the latest UX fixes.
- Actual install against real `$PROFILE` and real `~\.ssh\config`.

## Next Actions

1. Run `git diff --check`.
2. Commit the latest UX fixes.
3. If the user has already installed, run `. $PROFILE` to load `devtunnel` in the current shell.
4. Rerun install only if the updated positional-port function should be written into the real profile.

## Resume Checklist

- Run `git status --short`.
- Re-open `windows/devtunnel/devtunnel-manager.ps1` around `ValidateSet`, generated `Ports`, `Remove-All`, and `Install-All` output.
- Re-open `windows/devtunnel/smoke-test.ps1` around the generated function and uninstall assertions.
- Re-open `windows/devtunnel/README.md` around the install section.
- Avoid unrelated installer behavior changes.

## Resume Prompt

Continue the `windows/devtunnel` UX fixes. Smoke test already passed after adding profile-loading guidance, `uninstall`, and positional ports; run `git diff --check`, commit if clean, then tell the user to run `. $PROFILE` before using the just-installed `devtunnel` in the current shell.
