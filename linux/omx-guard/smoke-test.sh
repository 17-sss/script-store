#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/omx-guard.sh"

command_path() {
  command -v "$1" || {
    printf 'required command not found: %s\n' "$1" >&2
    exit 1
  }
}

MKDIR_BIN="$(command_path mkdir)"
MKTEMP_BIN="$(command_path mktemp)"
RM_BIN="$(command_path rm)"
LN_BIN="$(command_path ln)"
CMP_BIN="$(command_path cmp)"

TMP_ROOT="$($MKTEMP_BIN -d "${TMPDIR:-/tmp}/omx-guard-smoke.XXXXXX")"
cleanup() {
  "$RM_BIN" -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

export HOME="$TMP_ROOT/home"
export CODEX_HOME="$HOME/.codex"
export OMX_GUARD_STATE_HOME="$TMP_ROOT/state"
export OMX_GUARD_NPM_PREFIXES="$TMP_ROOT/npm-prefixes"
export TMPDIR="$TMP_ROOT/tmp"

PROJECT="$TMP_ROOT/project"
ISOLATED_BIN="$TMP_ROOT/bin"

"$MKDIR_BIN" -p \
  "$CODEX_HOME/skills/personal" \
  "$PROJECT/.codex" \
  "$ISOLATED_BIN" \
  "$TMPDIR"

for command_name in python3 uname mktemp rm mkdir grep basename; do
  command_source="$(command_path "$command_name")"
  "$LN_BIN" -s "$command_source" "$ISOLATED_BIN/$command_name"
done

export PATH="$ISOLATED_BIN"

if command -v npm >/dev/null 2>&1 || command -v omx >/dev/null 2>&1; then
  printf 'isolated PATH unexpectedly exposes npm or omx\n' >&2
  exit 1
fi

printf 'model = "personal"\n\n[mcp_servers.personal]\ncommand = "keep"\n' \
  > "$CODEX_HOME/config.toml"
printf '# Personal agents\n' > "$CODEX_HOME/AGENTS.md"
printf '# Personal skill\n' > "$CODEX_HOME/skills/personal/SKILL.md"
printf 'theme = "original"\n' > "$PROJECT/.codex/settings.toml"

printf 'model = "personal"\n\n[mcp_servers.personal]\ncommand = "keep"\n' \
  > "$TMP_ROOT/expected-config.toml"
printf '# Personal agents\n' > "$TMP_ROOT/expected-AGENTS.md"
printf '# Personal skill\n' > "$TMP_ROOT/expected-SKILL.md"
printf 'theme = "original"\n' > "$TMP_ROOT/expected-project.toml"

/bin/bash "$GUARD" snapshot pre-omx --project "$PROJECT"

SNAPSHOT_ID="$(python3 - "$OMX_GUARD_STATE_HOME" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1]) / "snapshots"
matches = []
for path in root.iterdir():
    manifest = path / "manifest.json"
    if not manifest.is_file():
        continue
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if data.get("label") == "pre-omx":
        matches.append(path.name)

if len(matches) != 1:
    raise SystemExit(f"expected one pre-omx snapshot, found {len(matches)}")
print(matches[0])
PY
)"

printf 'model = "changed"\n\n[mcp_servers.omx_guard]\ncommand = "remove"\n' \
  > "$CODEX_HOME/config.toml"
printf '# Changed agents\n' > "$CODEX_HOME/AGENTS.md"
printf '# Changed skill\n' > "$CODEX_HOME/skills/personal/SKILL.md"
printf 'theme = "changed"\n' > "$PROJECT/.codex/settings.toml"

"$MKDIR_BIN" -p \
  "$HOME/.omx/state" \
  "$CODEX_HOME/plugins/cache/oh-my-codex" \
  "$PROJECT/.omx" \
  "$OMX_GUARD_NPM_PREFIXES/lib/node_modules/oh-my-codex" \
  "$OMX_GUARD_NPM_PREFIXES/bin"
printf 'installed\n' > "$HOME/.omx/state/session"
printf '{}\n' > "$CODEX_HOME/plugins/cache/oh-my-codex/plugin.json"
printf 'project state\n' > "$PROJECT/.omx/state"
printf '{}\n' > "$OMX_GUARD_NPM_PREFIXES/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$OMX_GUARD_NPM_PREFIXES/bin/omx"

/bin/bash "$GUARD" restore pre-omx

"$CMP_BIN" -s "$TMP_ROOT/expected-config.toml" "$CODEX_HOME/config.toml"
"$CMP_BIN" -s "$TMP_ROOT/expected-AGENTS.md" "$CODEX_HOME/AGENTS.md"
"$CMP_BIN" -s "$TMP_ROOT/expected-SKILL.md" "$CODEX_HOME/skills/personal/SKILL.md"
"$CMP_BIN" -s "$TMP_ROOT/expected-project.toml" "$PROJECT/.codex/settings.toml"

for removed_path in \
  "$HOME/.omx" \
  "$CODEX_HOME/plugins" \
  "$PROJECT/.omx" \
  "$OMX_GUARD_NPM_PREFIXES/lib/node_modules/oh-my-codex" \
  "$OMX_GUARD_NPM_PREFIXES/bin/omx"
do
  if [[ -e "$removed_path" || -L "$removed_path" ]]; then
    printf 'expected path to be removed: %s\n' "$removed_path" >&2
    exit 1
  fi
done

OUTSIDE_FILE="$TMP_ROOT/outside.txt"
printf 'must remain\n' > "$OUTSIDE_FILE"

python3 - "$OMX_GUARD_STATE_HOME/snapshots/$SNAPSHOT_ID/manifest.json" "$OUTSIDE_FILE" <<'PY'
from pathlib import Path
import json
import sys

manifest_path = Path(sys.argv[1])
data = json.loads(manifest_path.read_text(encoding="utf-8"))
data["entries"][0]["path"] = sys.argv[2]
manifest_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if /bin/bash "$GUARD" restore "$SNAPSHOT_ID" >/dev/null 2>&1; then
  printf 'tampered manifest restore unexpectedly succeeded\n' >&2
  exit 1
fi

if [[ "$(<"$OUTSIDE_FILE")" != "must remain" ]]; then
  printf 'tampered manifest changed an outside file\n' >&2
  exit 1
fi

printf 'OMX Guard isolated smoke test passed\n'
