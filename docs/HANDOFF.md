# HANDOFF

## Metadata

- Project: script-store
- Scope: repo
- Repo Root: .
- Branch: main
- Last Updated: 2026-05-28T14:14:52+09:00
- Updated By: Codex

## TL;DR

- Active work is `windows/devtunnel`: a PowerShell installer for a `devtunnel` SSH port-forward helper.
- The Windows smoke test now passes locally.
- GNU-style `devtunnel --help` was removed from docs/tests/help text; supported help paths are `devtunnel -Help`, `devtunnel -h`, and `Get-Help devtunnel -Detailed`.

## Current Objective

Prepare for a real `devtunnel` install against the user's PowerShell profile and SSH config after confirming the desired SSH host settings.

## Current State

### Completed

- `windows/devtunnel/README.md` was anonymized for a personal repository.
- `windows/devtunnel/devtunnel-manager.ps1` supports non-interactive test inputs, temp path overrides via `DEVTUNNEL_PROFILE_PATH` and `DEVTUNNEL_SSH_DIR`, `-Help`, and comment-based `Get-Help`.
- `windows/devtunnel/smoke-test.ps1` was added to exercise install, help, reinstall, and remove against temp files only.
- Empty `Get-Content -Raw` results are normalized through `Get-FileText`, fixing the earlier null regex failure.
- Console-facing manager output is ASCII English to avoid Windows PowerShell encoding garbling.
- Broken `--help` support claims were removed in favor of PowerShell-native `-Help` and `-h`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp` passed on Windows.

### In Progress

- None.

### Needs Confirmation

- Real SSH host settings for `.\devtunnel-manager.ps1 install`.
- Actual manual install against real `$PROFILE` and real `~\.ssh\config`.

## Recent Changes

- Commit `cdb5bd0`: anonymized devtunnel README examples.
- Commit `a65ed6b`: hardened setup flow around identity file, SSH port validation, reinstall behavior, and managed block cleanup.
- Commit `b28ab98`: added smoke coverage and non-interactive manager options.
- Commit `043a297`: fixed empty temp-file reads and ASCII output after the first Windows smoke failure.
- Latest work: removed `--help` references from manager help text, smoke test, and README.

## Known Issues / Watch List

- No current smoke-test failures.
- Real install needs user-specific SSH values and should not be run until those are confirmed.

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

### Pending Checks

- Actual install against real `$PROFILE` and real `~\.ssh\config`.

## Next Actions

1. Confirm real SSH values.
2. Run `cd windows\devtunnel; .\devtunnel-manager.ps1 install`.
3. Restart PowerShell or run `. $PROFILE`, then test `devtunnel -Help` and `devtunnel`.

## Resume Checklist

- Run `git status --short`.
- Re-open `windows/devtunnel/devtunnel-manager.ps1` around the generated `devtunnel` function.
- Re-open `windows/devtunnel/smoke-test.ps1` around the help assertions.
- Re-open `windows/devtunnel/README.md` around the help usage section.
- Avoid unrelated installer behavior changes.

## Resume Prompt

Continue the `windows/devtunnel` install prep. Verify the committed state, confirm the user's real SSH host values, then run `.\devtunnel-manager.ps1 install` only when the user is ready to update the real PowerShell profile and SSH config.
