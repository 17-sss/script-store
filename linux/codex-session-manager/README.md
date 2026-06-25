# codex-session-manager

Small dependency-free TUI for browsing local Codex sessions and archived sessions.

The Codex CLI currently provides `resume`, `archive`, `delete`, and `unarchive`, but it does not provide a local-session `list` command that prints both active and archived sessions for scripting. This tool fills that gap by reading local transcript files and delegating mutations back to the official `codex` CLI.

## Requirements

- Node.js
- Codex CLI on `PATH`

No `fzf`, npm package, or install step is required.

## Usage

```bash
./codex-session-manager.js
```

By default, the TUI filters sessions to the current working directory and its children. Press `a` to toggle all local sessions.

## Keys

```txt
Up/Down or j/k   Move selection
Tab              Switch active/archived list
a                Toggle current-cwd/all-cwd filtering
Space            Toggle selected row
A                Toggle all visible rows
C                Clear selection
/                Search
r                Resume active session
b                Archive selected or cursor session
u                Unarchive selected or cursor session
d                Delete selected or cursor session
R                Refresh
q                Quit
```

The title bar shows the current selected count. If one or more rows are selected, `b`, `u`, and `d` operate on the selected rows in the current visible list. If nothing is selected, those actions use the cursor row.

Deleting one session requires typing `DELETE <id-prefix>` in the prompt. Deleting multiple selected sessions requires typing `DELETE <count>` before the tool runs `codex delete <SESSION_UUID> --force` for each selected row.

## Non-interactive list mode

```bash
./codex-session-manager.js --list active
./codex-session-manager.js --list archived
./codex-session-manager.js --list all --all
./codex-session-manager.js --list all --json --all
```

Override the Codex home directory for tests or alternate installations:

```bash
CODEX_HOME=/tmp/example-codex ./codex-session-manager.js --list all --all
```

## Data sources

The tool reads:

```txt
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
```

The default `CODEX_HOME` is `~/.codex`.

Mutating actions call:

```bash
codex archive <SESSION_UUID>
codex delete <SESSION_UUID> --force
codex unarchive <SESSION_UUID>
```
