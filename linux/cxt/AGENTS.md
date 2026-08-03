# cxt maintenance guidance

This file applies only to `linux/cxt/`.

## Before changing cxt

- Read `README.md` and `MAINTENANCE.md` completely.
- Inspect the current Git status and preserve unrelated or user-owned changes.
- Treat hard-coded model aliases, reasoning levels, permission presets, and CLI flags as drift-prone Codex product data. Verify them from current sources instead of memory.
- Prefer the current local `codex --version`, `codex --help`, `codex exec --help`, and list-visible entries in `${CODEX_HOME:-$HOME/.codex}/models_cache.json`.
- For broader Codex behavior, refresh the official Codex manual through the system `openai-docs` skill when available.

## Compatibility contract

- Preserve transparent pass-through for every non-cxt argument.
- Interpret cxt shortcuts only before `--`; everything after `--` must retain its original argument boundary and value.
- Keep model, reasoning, and permission shortcuts independently composable, with at most one cxt shortcut from each group.
- Whenever a shortcut contract changes, update every exposed surface together: `bin/cxt`, its `--cxt-help` output, both files under `completions/`, `README.md`, and `tests/test-cxt.sh`.
- Keep Bash/Zsh completion aligned with the session-management contract. Session arguments for attach and single-session kill may complete only valid live `codex-*` tmux session names; never expose general tmux sessions.
- Whenever completion behavior changes, update `completions/cxt.bash`, `completions/cxt.zsh`, `install-cxt.sh`, `README.md`, and `tests/test-cxt.sh` together.
- Keep `bin/cxt` and `install-cxt.sh` compatible with Bash 3.2 where practical. Do not introduce associative arrays or unsafe empty-array expansion under nounset.
- Do not add npm or Node.js as a runtime dependency. A maintenance-only documentation helper may use Node when it is already provided by Codex.
- Do not replace the absolute symlink installation model or edit a user's real shell rc files during tests.
- Preserve the safe `cx` to `cxt` migration: remove only the exact legacy link managed by this repo and its exact marker block; never overwrite or remove a user-owned `cx` path.
- Do not guess unreleased, hidden, or account-inaccessible model slugs. A cached model is eligible for a convenience alias only when its current catalog entry is user-visible and the alias provides durable value.

## Verification

Run from `linux/cxt/`:

```bash
bash -n bin/cxt
bash -n install-cxt.sh
bash -n completions/cxt.bash
zsh -n completions/cxt.zsh
bash -n tests/test-cxt.sh
./tests/test-cxt.sh
git diff --check
```

- Run ShellCheck when it is installed; report an explicit skip otherwise.
- Keep mock Codex/tmux tests isolated under a temporary directory and use temporary homes for installer tests.
- Validate new model and reasoning values with a non-agent local Codex command such as `codex ... features list`; do not start a real task merely to probe option parsing.
- Inspect the final diff after all checks. Do not commit or push unless the user explicitly asks.
