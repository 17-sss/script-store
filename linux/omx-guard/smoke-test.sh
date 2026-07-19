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
CHMOD_BIN="$(command_path chmod)"
BASH_BIN="${OMX_GUARD_TEST_BASH:-${BASH:-$(command_path bash)}}"

TMP_ROOT="$($MKTEMP_BIN -d "${TMPDIR:-/tmp}/omx-guard-smoke.XXXXXX")"
cleanup() {
  "$RM_BIN" -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

export HOME="$TMP_ROOT/home"
export CODEX_HOME="$HOME/.codex"
export OMX_GUARD_STATE_HOME="$TMP_ROOT/state"
export OMX_GUARD_NPM_PREFIXES="$TMP_ROOT/npm-prefixes:$TMP_ROOT/linuxbrew-prefix"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export NVM_DIR="$TMP_ROOT/custom-nvm"
export FNM_DIR="$TMP_ROOT/custom-fnm"
export VOLTA_HOME="$TMP_ROOT/custom-volta"
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

# Regression coverage for empty project lists under macOS Bash 3.2 + nounset.
"$BASH_BIN" "$GUARD" snapshot no-project
"$BASH_BIN" "$GUARD" restore no-project
"$BASH_BIN" "$GUARD" remove

# An inactive OMX installation that predates the snapshot must survive restore.
PREEXISTING_NVM="$HOME/.nvm/versions/node/v18.0.0"
"$MKDIR_BIN" -p \
  "$PREEXISTING_NVM/lib/node_modules/oh-my-codex" \
  "$PREEXISTING_NVM/bin"
printf '{"name":"oh-my-codex","version":"1.0.0"}\n' \
  > "$PREEXISTING_NVM/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nprintf "preexisting\\n"\n' \
  > "$PREEXISTING_NVM/bin/omx"
"$CHMOD_BIN" +x "$PREEXISTING_NVM/bin/omx"
printf '{"name":"oh-my-codex","version":"1.0.0"}\n' \
  > "$TMP_ROOT/expected-preexisting-package.json"
printf '#!/usr/bin/env bash\nprintf "preexisting\\n"\n' \
  > "$TMP_ROOT/expected-preexisting-omx"

# This package exists before the snapshot but its npm prefix is not yet exposed.
UNSEEN_PREFIX="$TMP_ROOT/unseen-prefix"
"$MKDIR_BIN" -p \
  "$UNSEEN_PREFIX/lib/node_modules/oh-my-codex" \
  "$UNSEEN_PREFIX/bin"
printf '{"name":"oh-my-codex","version":"hidden"}\n' \
  > "$UNSEEN_PREFIX/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nprintf "hidden\\n"\n' > "$UNSEEN_PREFIX/bin/omx"
printf '{"name":"oh-my-codex","version":"hidden"}\n' \
  > "$TMP_ROOT/expected-unseen-package.json"
printf '#!/usr/bin/env bash\nprintf "hidden\\n"\n' \
  > "$TMP_ROOT/expected-unseen-omx"

"$BASH_BIN" "$GUARD" snapshot pre-omx --project "$PROJECT"

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

python3 - \
  "$OMX_GUARD_STATE_HOME/snapshots/$SNAPSHOT_ID/manifest.json" \
  "$PREEXISTING_NVM" \
  "$UNSEEN_PREFIX" <<'PY'
from pathlib import Path
import json
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2])
expected = {
    str(root / "lib" / "node_modules" / "oh-my-codex"),
    str(root / "bin" / "omx"),
}
found = set(manifest["omx"]["discovery"]["removable_paths"])
if not expected.issubset(found):
    raise SystemExit("snapshot did not record the inactive OMX installation")
unseen = Path(sys.argv[3])
if any(str(path).startswith(str(unseen)) for path in found):
    raise SystemExit("snapshot unexpectedly recorded an unexposed npm prefix")
PY

# A local package named oh-my-codex is not a supported global installation root.
LOCAL_PACKAGE="$TMP_ROOT/source/node_modules/oh-my-codex"
"$MKDIR_BIN" -p "$LOCAL_PACKAGE/bin"
printf '{"name":"oh-my-codex","version":"source"}\n' \
  > "$LOCAL_PACKAGE/package.json"
printf '#!/usr/bin/env bash\nprintf "unrelated\\n"\n' > "$LOCAL_PACKAGE/bin/omx"
"$CHMOD_BIN" +x "$LOCAL_PACKAGE/bin/omx"
"$LN_BIN" -s "$LOCAL_PACKAGE/bin/omx" "$ISOLATED_BIN/omx"
printf '{"name":"oh-my-codex","version":"source"}\n' \
  > "$TMP_ROOT/expected-local-package.json"
printf '#!/usr/bin/env bash\nprintf "unrelated\\n"\n' \
  > "$TMP_ROOT/expected-unrelated-omx"

BOUNDARY_HOME="$TMP_ROOT/boundary-home"
HOME="$BOUNDARY_HOME" \
CODEX_HOME="$BOUNDARY_HOME/.codex" \
OMX_GUARD_STATE_HOME="$TMP_ROOT/boundary-state" \
OMX_GUARD_NPM_PREFIXES="$TMP_ROOT/boundary-prefix" \
XDG_CONFIG_HOME="$BOUNDARY_HOME/.config" \
XDG_DATA_HOME="$BOUNDARY_HOME/.local/share" \
NVM_DIR="$BOUNDARY_HOME/.nvm" \
FNM_DIR="$BOUNDARY_HOME/.local/share/fnm" \
VOLTA_HOME="$BOUNDARY_HOME/.volta" \
  "$BASH_BIN" "$GUARD" remove --no-snapshot
"$CMP_BIN" -s "$TMP_ROOT/expected-local-package.json" "$LOCAL_PACKAGE/package.json"
"$CMP_BIN" -s "$TMP_ROOT/expected-unrelated-omx" "$LOCAL_PACKAGE/bin/omx"

printf 'model = "changed"\n\n[mcp_servers.omx_guard]\ncommand = "remove"\n' \
  > "$CODEX_HOME/config.toml"
printf '# Changed agents\n' > "$CODEX_HOME/AGENTS.md"
printf '# Changed skill\n' > "$CODEX_HOME/skills/personal/SKILL.md"
printf 'theme = "changed"\n' > "$PROJECT/.codex/settings.toml"

"$MKDIR_BIN" -p \
  "$HOME/.omx/state" \
  "$CODEX_HOME/plugins/cache/oh-my-codex" \
  "$PROJECT/.omx" \
  "$TMP_ROOT/npm-prefixes/lib/node_modules/oh-my-codex" \
  "$TMP_ROOT/npm-prefixes/bin" \
  "$TMP_ROOT/linuxbrew-prefix/lib/node_modules/oh-my-codex" \
  "$TMP_ROOT/linuxbrew-prefix/bin"
printf 'installed\n' > "$HOME/.omx/state/session"
printf '{}\n' > "$CODEX_HOME/plugins/cache/oh-my-codex/plugin.json"
printf 'project state\n' > "$PROJECT/.omx/state"

for node_install in \
  "$HOME/.nvm/versions/node/v19.0.0" \
  "$NVM_DIR/versions/node/v20.0.0" \
  "$XDG_CONFIG_HOME/nvm/versions/node/v21.0.0" \
  "$FNM_DIR/node-versions/v20.0.0/installation" \
  "$XDG_DATA_HOME/fnm/node-versions/v21.0.0/installation" \
  "$HOME/Library/Application Support/fnm/node-versions/v22.0.0/installation"
do
  "$MKDIR_BIN" -p \
    "$node_install/lib/node_modules/oh-my-codex" \
    "$node_install/bin"
  printf '{}\n' > "$node_install/lib/node_modules/oh-my-codex/package.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$node_install/bin/omx"
done

for volta_home in "$HOME/.volta" "$VOLTA_HOME"; do
  "$MKDIR_BIN" -p \
    "$volta_home/tools/image/packages/oh-my-codex/lib/node_modules/oh-my-codex" \
    "$volta_home/bin"
  printf '{"name":"oh-my-codex","version":"2.0.0"}\n' \
    > "$volta_home/tools/image/packages/oh-my-codex/lib/node_modules/oh-my-codex/package.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$volta_home/bin/omx"
done

for npm_prefix in \
  "$HOME/.npm-global" \
  "$TMP_ROOT/npm-prefixes" \
  "$TMP_ROOT/linuxbrew-prefix"
do
  "$MKDIR_BIN" -p \
    "$npm_prefix/lib/node_modules/oh-my-codex" \
    "$npm_prefix/bin"
  printf '{}\n' > "$npm_prefix/lib/node_modules/oh-my-codex/package.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$npm_prefix/bin/omx"
done

OMX_GUARD_NPM_PREFIXES="$OMX_GUARD_NPM_PREFIXES:$UNSEEN_PREFIX" \
  "$BASH_BIN" "$GUARD" restore pre-omx

"$CMP_BIN" -s "$TMP_ROOT/expected-config.toml" "$CODEX_HOME/config.toml"
"$CMP_BIN" -s "$TMP_ROOT/expected-AGENTS.md" "$CODEX_HOME/AGENTS.md"
"$CMP_BIN" -s "$TMP_ROOT/expected-SKILL.md" "$CODEX_HOME/skills/personal/SKILL.md"
"$CMP_BIN" -s "$TMP_ROOT/expected-project.toml" "$PROJECT/.codex/settings.toml"
"$CMP_BIN" -s \
  "$TMP_ROOT/expected-preexisting-package.json" \
  "$PREEXISTING_NVM/lib/node_modules/oh-my-codex/package.json"
"$CMP_BIN" -s "$TMP_ROOT/expected-preexisting-omx" "$PREEXISTING_NVM/bin/omx"
"$CMP_BIN" -s "$TMP_ROOT/expected-local-package.json" "$LOCAL_PACKAGE/package.json"
"$CMP_BIN" -s "$TMP_ROOT/expected-unrelated-omx" "$LOCAL_PACKAGE/bin/omx"
if [[ ! -L "$ISOLATED_BIN/omx" ]]; then
  printf 'local omx command symlink was unexpectedly removed\n' >&2
  exit 1
fi
"$CMP_BIN" -s "$TMP_ROOT/expected-unrelated-omx" "$ISOLATED_BIN/omx"
"$CMP_BIN" -s \
  "$TMP_ROOT/expected-unseen-package.json" \
  "$UNSEEN_PREFIX/lib/node_modules/oh-my-codex/package.json"
"$CMP_BIN" -s "$TMP_ROOT/expected-unseen-omx" "$UNSEEN_PREFIX/bin/omx"

for removed_path in \
  "$HOME/.omx" \
  "$CODEX_HOME/plugins" \
  "$PROJECT/.omx" \
  "$HOME/.nvm/versions/node/v19.0.0/lib/node_modules/oh-my-codex" \
  "$HOME/.nvm/versions/node/v19.0.0/bin/omx" \
  "$NVM_DIR/versions/node/v20.0.0/lib/node_modules/oh-my-codex" \
  "$NVM_DIR/versions/node/v20.0.0/bin/omx" \
  "$XDG_CONFIG_HOME/nvm/versions/node/v21.0.0/lib/node_modules/oh-my-codex" \
  "$XDG_CONFIG_HOME/nvm/versions/node/v21.0.0/bin/omx" \
  "$FNM_DIR/node-versions/v20.0.0/installation/lib/node_modules/oh-my-codex" \
  "$FNM_DIR/node-versions/v20.0.0/installation/bin/omx" \
  "$XDG_DATA_HOME/fnm/node-versions/v21.0.0/installation/lib/node_modules/oh-my-codex" \
  "$XDG_DATA_HOME/fnm/node-versions/v21.0.0/installation/bin/omx" \
  "$HOME/Library/Application Support/fnm/node-versions/v22.0.0/installation/lib/node_modules/oh-my-codex" \
  "$HOME/Library/Application Support/fnm/node-versions/v22.0.0/installation/bin/omx" \
  "$HOME/.volta/tools/image/packages/oh-my-codex" \
  "$HOME/.volta/bin/omx" \
  "$VOLTA_HOME/tools/image/packages/oh-my-codex" \
  "$VOLTA_HOME/bin/omx" \
  "$HOME/.npm-global/lib/node_modules/oh-my-codex" \
  "$HOME/.npm-global/bin/omx" \
  "$TMP_ROOT/npm-prefixes/lib/node_modules/oh-my-codex" \
  "$TMP_ROOT/npm-prefixes/bin/omx" \
  "$TMP_ROOT/linuxbrew-prefix/lib/node_modules/oh-my-codex" \
  "$TMP_ROOT/linuxbrew-prefix/bin/omx"
do
  if [[ -e "$removed_path" || -L "$removed_path" ]]; then
    printf 'expected path to be removed: %s\n' "$removed_path" >&2
    exit 1
  fi
done

# Older manifests did not record exact package paths; restore must skip npm deletion.
python3 - "$OMX_GUARD_STATE_HOME/snapshots/$SNAPSHOT_ID" <<'PY'
from pathlib import Path
import json
import shutil
import sys

source = Path(sys.argv[1])
target = source.parent / "legacy-format"
shutil.copytree(source, target, symlinks=True)
manifest_path = target / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["snapshot_id"] = target.name
manifest["label"] = target.name
manifest["omx"].pop("discovery", None)
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

LEGACY_NEW_PREFIX="$TMP_ROOT/legacy-new-prefix"
"$MKDIR_BIN" -p \
  "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex" \
  "$LEGACY_NEW_PREFIX/bin"
printf '{}\n' > "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$LEGACY_NEW_PREFIX/bin/omx"
OMX_GUARD_NPM_PREFIXES="$LEGACY_NEW_PREFIX" \
  "$BASH_BIN" "$GUARD" restore legacy-format
if [[ ! -d "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex" \
  || ! -f "$LEGACY_NEW_PREFIX/bin/omx" ]]; then
  printf 'legacy snapshot unexpectedly removed an OMX installation\n' >&2
  exit 1
fi

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

if "$BASH_BIN" "$GUARD" restore "$SNAPSHOT_ID" >/dev/null 2>&1; then
  printf 'tampered manifest restore unexpectedly succeeded\n' >&2
  exit 1
fi

if [[ "$(<"$OUTSIDE_FILE")" != "must remain" ]]; then
  printf 'tampered manifest changed an outside file\n' >&2
  exit 1
fi

printf 'OMX Guard isolated smoke test passed\n'
