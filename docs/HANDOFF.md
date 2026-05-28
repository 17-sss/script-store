# HANDOFF

## Metadata

- Project: script-store
- Scope: repo
- Repo Root: .
- Branch: main
- Last Updated: 2026-05-28T14:43:56+09:00
- Updated By: Codex

## TL;DR

- Active work is `windows/devtunnel`: a PowerShell installer for a `devtunnel` SSH port-forward helper.
- Direction was simplified: installer manages only the PowerShell function, not SSH config.
- Runtime usage is now centered on `devtunnel <ports> <ssh-host-alias>`.
- Multiple ports remain supported, e.g. `devtunnel 3000,5173,6006 prox-dev-hoyoung`.
- Tunnels are closed with `Ctrl + C` in the running terminal.

## Current Objective

Commit the validated simplified installer/runtime contract.

## Current State

### Completed

- `windows/devtunnel/devtunnel-manager.ps1` was simplified to install/remove only the managed `devtunnel` function block in `$PROFILE`.
- SSH config creation, selection, and managed SSH block removal logic were removed.
- `install` and `reinstall` both write the current function block.
- `remove` and `uninstall` both remove the function block.
- Generated `devtunnel` supports:
  - `devtunnel 3123 prox-dev-hoyoung`
  - `devtunnel 3000,5173,6006 prox-dev-hoyoung`
  - `devtunnel -Ports 3123 -HostAlias prox-dev-hoyoung`
  - `devtunnel -Help`, `devtunnel -h`, and `Get-Help devtunnel -Detailed`
- `windows/devtunnel/smoke-test.ps1` was rewritten for the new contract.
- `windows/devtunnel/README.md` was rewritten to remove SSH config management instructions.
- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp` passed after simplification.
- Latest smoke temp root: `C:\Users\User\AppData\Local\Temp\devtunnel-smoke-c37d74dde87a44179e517c5f078d2c8a`.
- `git diff --check` passed after simplification.

### In Progress

- Commit the simplification.

### Needs Confirmation

- After commit, rerun real install if the user's `$PROFILE` still has the older generated function.

## Recent Changes

- Commit `98f697c`: use PowerShell-native help flags.
- Commit `255aef8`: allowed choosing an existing SSH host alias during install.
- Commit `d32b6b7`: clarified profile loading, added `uninstall`, and positional ports.
- Latest local work: simplified installer so SSH alias and ports are supplied only when running `devtunnel`.

## Known Issues / Watch List

- Existing real `$PROFILE` may still contain an older generated `devtunnel` function until `.\windows\devtunnel\devtunnel-manager.ps1 install` is run again.
- The tool maps each local port to the same remote port. Different local/remote port mapping still requires a manual `ssh -L local:127.0.0.1:remote alias` command.

## Quick Reference

### Files

- `windows/devtunnel/devtunnel-manager.ps1`
- `windows/devtunnel/smoke-test.ps1`
- `windows/devtunnel/README.md`

### Smoke Command

- `powershell -NoProfile -ExecutionPolicy Bypass -File "windows\devtunnel\smoke-test.ps1" -KeepTemp`

### Real Install Command

- `.\windows\devtunnel\devtunnel-manager.ps1 install`
- Then run `. $PROFILE` or restart PowerShell.

### Runtime Examples

- `devtunnel 3123 prox-dev-hoyoung`
- `devtunnel 3000,5173,6006 prox-dev-hoyoung`
- `devtunnel -Ports 3123 -HostAlias prox-dev-hoyoung`

## Validation

### Pending Checks

- None before commit.

## Next Actions

1. Commit the simplification.
2. Tell the user to rerun install and `. $PROFILE` to update the real shell function.

## Resume Checklist

- Run `git status --short`.
- Re-open `windows/devtunnel/devtunnel-manager.ps1` around generated `devtunnel`.
- Re-open `windows/devtunnel/smoke-test.ps1` around runtime argument assertions.
- Re-open `windows/devtunnel/README.md` around install and usage sections.
- Avoid reintroducing SSH config management unless explicitly requested.

## Resume Prompt

Continue the `windows/devtunnel` simplification. Validate that the installer only manages the PowerShell function, that runtime `devtunnel <ports> <alias>` builds the expected SSH arguments, then commit and tell the user how to reinstall the updated function.
