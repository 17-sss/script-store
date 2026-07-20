# cx maintenance guidance

This file applies only to `linux/cx/`.

## Before changing cx

- Read `README.md` and `MAINTENANCE.md` completely.
- Inspect the current Git status and preserve unrelated or user-owned changes.
- Treat hard-coded model aliases, reasoning levels, permission presets, and CLI flags as drift-prone Codex product data. Verify them from current sources instead of memory.
- Prefer the current local `codex --version`, `codex --help`, `codex exec --help`, and list-visible entries in `${CODEX_HOME:-$HOME/.codex}/models_cache.json`.
- For broader Codex behavior, refresh the official Codex manual through the system `openai-docs` skill when available.

## Compatibility contract

- Preserve transparent pass-through for every non-cx argument.
- Interpret cx shortcuts only before `--`; everything after `--` must retain its original argument boundary and value.
- Keep model, reasoning, and permission shortcuts independently composable, with at most one cx shortcut from each group.
- Whenever a shortcut contract changes, update all four surfaces together: `bin/cx`, its `--cx-help` output, `README.md`, and `tests/test-cx.sh`.
- Keep `bin/cx` and `install-cx.sh` compatible with Bash 3.2 where practical. Do not introduce associative arrays or unsafe empty-array expansion under nounset.
- Do not add npm or Node.js as a runtime dependency. A maintenance-only documentation helper may use Node when it is already provided by Codex.
- Do not replace the absolute symlink installation model or edit a user's real shell rc files during tests.
- Do not guess unreleased, hidden, or account-inaccessible model slugs. A cached model is eligible for a convenience alias only when its current catalog entry is user-visible and the alias provides durable value.

## Verification

Run from `linux/cx/`:

```bash
bash -n bin/cx
bash -n install-cx.sh
bash -n tests/test-cx.sh
./tests/test-cx.sh
git diff --check
```

- Run ShellCheck when it is installed; report an explicit skip otherwise.
- Keep mock Codex/tmux tests isolated under a temporary directory and use temporary homes for installer tests.
- Validate new model and reasoning values with a non-agent local Codex command such as `codex ... features list`; do not start a real task merely to probe option parsing.
- Inspect the final diff after all checks. Do not commit or push unless the user explicitly asks.
