# HANDOFF

## Metadata

- Project: script-store
- Scope: repo
- Repo Root: .
- Branch: main
- Last Updated: 2026-05-28T13:55:32+09:00
- Updated By: Codex

## TL;DR

- Active work is `windows/devtunnel`: a PowerShell installer for a `devtunnel` SSH port-forward helper.
- The smoke test now reaches installed-function help checks on Windows, but fails at `devtunnel --help`.
- Recommended next step: simplify to PowerShell-native help only (`devtunnel -Help`, `devtunnel -h`, `Get-Help devtunnel -Detailed`) and remove `--help` from smoke test/docs/help text.

## Current Objective

Make `windows/devtunnel/smoke-test.ps1` pass on local Windows before running the installer against the real PowerShell profile and SSH config.

## Current State

### Completed

- `windows/devtunnel/README.md` was anonymized for a personal repository.
- `windows/devtunnel/devtunnel-manager.ps1` supports non-interactive test inputs, temp path overrides via `DEVTUNNEL_PROFILE_PATH` and `DEVTUNNEL_SSH_DIR`, `-Help`, and comment-based `Get-Help`.
- `windows/devtunnel/smoke-test.ps1` was added to exercise install, help, reinstall, and remove against temp files only.
- Empty `Get-Content -Raw` results are normalized through `Get-FileText`, fixing the earlier null regex failure.
- Console-facing manager output is ASCII English to avoid Windows PowerShell encoding garbling.

### In Progress

- Windows smoke test still needs one follow-up change around GNU-style `--help`.

### Needs Confirmation

- A passing Windows run of `.\smoke-test.ps1 -KeepTemp`.
- Actual manual install only after smoke passes.

## Recent Changes

- Commit `cdb5bd0`: anonymized devtunnel README examples.
- Commit `a65ed6b`: hardened setup flow around identity file, SSH port validation, reinstall behavior, and managed block cleanup.
- Commit `b28ab98`: added smoke coverage and non-interactive manager options.
- Commit `043a297`: fixed empty temp-file reads and ASCII output after the first Windows smoke failure.

## Known Issues / Watch List

- Issue: `.\smoke-test.ps1 -KeepTemp` fails at `devtunnel --help`.
- Evidence: Windows PowerShell reports it cannot convert `"--help"` to `System.Int32[]` for the `Ports` parameter.
- Cause: `--help` is being treated as a positional argument, not as the `[Alias("-help")] [switch]$Help` parameter.
- Recommendation: Do not fight PowerShell parsing unless GNU-style compatibility is truly required. Keep `-Help`, `-h`, and `Get-Help`; remove `--help` from:
  - `windows/devtunnel/devtunnel-manager.ps1` generated help text
  - `windows/devtunnel/smoke-test.ps1`
  - `windows/devtunnel/README.md`
- Risk: Leaving `--help` documented makes the smoke test fail and gives users a broken command.

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
- `commit-helper` commits succeeded through `043a297`.

### User Windows Checks

- `.\smoke-test.ps1 -KeepTemp`: advanced past install and earlier null-file issue.
- Current failure is isolated to `devtunnel --help`.

### Pending Checks

- Passing Windows smoke test after removing or reworking `--help`.
- Actual install against real `$PROFILE` and real `~\.ssh\config`.

## Next Actions

1. Remove `--help` support claims and smoke assertion; keep `devtunnel -Help`, `devtunnel -h`, and `Get-Help devtunnel -Detailed`.
2. Commit that fix, then ask the user to rerun `cd windows\devtunnel; .\smoke-test.ps1 -KeepTemp` on Windows.
3. If smoke passes, review the temp `profile.ps1` and `.ssh\config`, then run the real install.

## Resume Checklist

- Run `git status --short` and confirm only this handoff doc is new/modified unless new work has happened.
- Re-open `windows/devtunnel/devtunnel-manager.ps1` around the generated `devtunnel` function.
- Re-open `windows/devtunnel/smoke-test.ps1` around the `devtunnel --help` assertion.
- Re-open `windows/devtunnel/README.md` around the help usage section.
- Apply the first next action before changing unrelated installer behavior.

## Resume Prompt

Continue the `windows/devtunnel` smoke-test hardening work. First verify the repo still matches `docs/HANDOFF.md`, then remove the broken `--help` path in favor of PowerShell-native `-Help` / `-h` / `Get-Help`, update README and smoke test consistently, validate with `git diff --check`, and prepare the user to rerun the Windows smoke test.
