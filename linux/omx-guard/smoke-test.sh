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
PYTHON_BIN="${OMX_GUARD_TEST_PYTHON:-$(command_path python3)}"

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

"$LN_BIN" -s "$PYTHON_BIN" "$ISOLATED_BIN/python3"
for command_name in uname mktemp rm mkdir grep basename cat; do
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
  > "$PREEXISTING_NVM/lib/node_modules/oh-my-codex/cli.js"
"$CHMOD_BIN" +x "$PREEXISTING_NVM/lib/node_modules/oh-my-codex/cli.js"
"$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$PREEXISTING_NVM/bin/omx"
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
printf '#!/usr/bin/env bash\nprintf "hidden\\n"\n' \
  > "$UNSEEN_PREFIX/lib/node_modules/oh-my-codex/cli.js"
"$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$UNSEEN_PREFIX/bin/omx"
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

# Only an exact package identity and a binary symlink into that package are owned.
OWNERSHIP_HOME="$TMP_ROOT/ownership-home"
OWNERSHIP_PREFIX="$TMP_ROOT/ownership-prefix"
INVALID_PREFIX="$TMP_ROOT/invalid-prefix"
OWNED_PREFIX="$TMP_ROOT/owned-prefix"
"$MKDIR_BIN" -p \
  "$OWNERSHIP_HOME/.codex" \
  "$OWNERSHIP_PREFIX/lib/node_modules/oh-my-codex" \
  "$OWNERSHIP_PREFIX/bin" \
  "$INVALID_PREFIX/lib/node_modules/oh-my-codex" \
  "$INVALID_PREFIX/bin" \
  "$OWNED_PREFIX/lib/node_modules/oh-my-codex" \
  "$OWNED_PREFIX/bin"
printf '{"name":"oh-my-codex","version":"3.0.0"}\n' \
  > "$OWNERSHIP_PREFIX/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nprintf "foreign-wrapper\\n"\n' \
  > "$OWNERSHIP_PREFIX/bin/omx"
printf '#!/usr/bin/env bash\nprintf "foreign-wrapper\\n"\n' \
  > "$TMP_ROOT/expected-foreign-wrapper"

printf '{"name":"different-package","version":"1.0.0"}\n' \
  > "$INVALID_PREFIX/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nexit 0\n' \
  > "$INVALID_PREFIX/lib/node_modules/oh-my-codex/cli.js"
"$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$INVALID_PREFIX/bin/omx"

printf '{"name":"oh-my-codex","version":"3.0.0"}\n' \
  > "$OWNED_PREFIX/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nexit 0\n' \
  > "$OWNED_PREFIX/lib/node_modules/oh-my-codex/cli.js"
"$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$OWNED_PREFIX/bin/omx"

ownership_output="$(
  HOME="$OWNERSHIP_HOME" \
  CODEX_HOME="$OWNERSHIP_HOME/.codex" \
  OMX_GUARD_STATE_HOME="$TMP_ROOT/ownership-state" \
  OMX_GUARD_NPM_PREFIXES="$OWNERSHIP_PREFIX:$INVALID_PREFIX:$OWNED_PREFIX" \
  XDG_CONFIG_HOME="$OWNERSHIP_HOME/.config" \
  XDG_DATA_HOME="$OWNERSHIP_HOME/.local/share" \
  NVM_DIR="$OWNERSHIP_HOME/.nvm" \
  FNM_DIR="$OWNERSHIP_HOME/.local/share/fnm" \
  VOLTA_HOME="$OWNERSHIP_HOME/.volta" \
    "$BASH_BIN" "$GUARD" remove --no-snapshot 2>&1
)"
if [[ -e "$OWNERSHIP_PREFIX/lib/node_modules/oh-my-codex" ]]; then
  printf 'exact OMX package identity was not removed\n' >&2
  exit 1
fi
"$CMP_BIN" -s "$TMP_ROOT/expected-foreign-wrapper" "$OWNERSHIP_PREFIX/bin/omx"
if [[ ! -d "$INVALID_PREFIX/lib/node_modules/oh-my-codex" \
  || ! -L "$INVALID_PREFIX/bin/omx" ]]; then
  printf 'ambiguous package identity or its binary was removed\n' >&2
  exit 1
fi
if [[ -e "$OWNED_PREFIX/lib/node_modules/oh-my-codex" \
  || -L "$OWNED_PREFIX/bin/omx" ]]; then
  printf 'owned package symlink pair was not removed\n' >&2
  exit 1
fi
if [[ "$ownership_output" != *"소유권을 입증할 수 없어"* ]]; then
  printf 'ambiguous OMX ownership was not reported\n' >&2
  exit 1
fi

# A native uninstall may leave or replace a wrapper; an unowned regular file stays.
printf '#!/usr/bin/env bash\nprintf "changed-wrapper\\n"\n' \
  > "$OWNERSHIP_PREFIX/bin/omx"
printf '#!/usr/bin/env bash\nprintf "changed-wrapper\\n"\n' \
  > "$TMP_ROOT/expected-changed-wrapper"
HOME="$OWNERSHIP_HOME" \
CODEX_HOME="$OWNERSHIP_HOME/.codex" \
OMX_GUARD_STATE_HOME="$TMP_ROOT/ownership-state" \
OMX_GUARD_NPM_PREFIXES="$OWNERSHIP_PREFIX" \
XDG_CONFIG_HOME="$OWNERSHIP_HOME/.config" \
XDG_DATA_HOME="$OWNERSHIP_HOME/.local/share" \
NVM_DIR="$OWNERSHIP_HOME/.nvm" \
FNM_DIR="$OWNERSHIP_HOME/.local/share/fnm" \
VOLTA_HOME="$OWNERSHIP_HOME/.volta" \
  "$BASH_BIN" "$GUARD" remove --no-snapshot > /dev/null
"$CMP_BIN" -s "$TMP_ROOT/expected-changed-wrapper" "$OWNERSHIP_PREFIX/bin/omx"

# TOML cleanup removes only proven managed tables and preserves all other bytes.
TOML_HOME="$TMP_ROOT/toml-home"
"$MKDIR_BIN" -p "$TOML_HOME/.codex"
cat > "$TOML_HOME/.codex/config.toml" <<'EOF'
model = "personal"
notes = """
/node_modules/oh-my-codex/example
[mcp_servers.omx_inside_multiline]
"""
# Personal OMX note must stay byte-for-byte.
plugin_ref = "oh-my-codex@oh-my-codex-local"

[mcp_servers.omx_guard]
command = "remove"

["mcp_servers"."omx_quoted"] # proven managed table
command = "remove-quoted"

[personal]
command = "/node_modules/oh-my-codex/personal"
EOF
cat > "$TMP_ROOT/expected-clean-config.toml" <<'EOF'
model = "personal"
notes = """
/node_modules/oh-my-codex/example
[mcp_servers.omx_inside_multiline]
"""
# Personal OMX note must stay byte-for-byte.
plugin_ref = "oh-my-codex@oh-my-codex-local"

[personal]
command = "/node_modules/oh-my-codex/personal"
EOF
HOME="$TOML_HOME" \
CODEX_HOME="$TOML_HOME/.codex" \
OMX_GUARD_STATE_HOME="$TMP_ROOT/toml-state" \
OMX_GUARD_NPM_PREFIXES="$TMP_ROOT/toml-prefix" \
XDG_CONFIG_HOME="$TOML_HOME/.config" \
XDG_DATA_HOME="$TOML_HOME/.local/share" \
NVM_DIR="$TOML_HOME/.nvm" \
FNM_DIR="$TOML_HOME/.local/share/fnm" \
VOLTA_HOME="$TOML_HOME/.volta" \
  "$BASH_BIN" "$GUARD" remove --no-snapshot > /dev/null
"$CMP_BIN" -s "$TMP_ROOT/expected-clean-config.toml" "$TOML_HOME/.codex/config.toml"

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
  printf '{"name":"oh-my-codex","version":"2.0.0"}\n' \
    > "$node_install/lib/node_modules/oh-my-codex/package.json"
  printf '#!/usr/bin/env bash\nexit 0\n' \
    > "$node_install/lib/node_modules/oh-my-codex/cli.js"
  "$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$node_install/bin/omx"
done

for volta_home in "$HOME/.volta" "$VOLTA_HOME"; do
  "$MKDIR_BIN" -p \
    "$volta_home/tools/image/packages/oh-my-codex/lib/node_modules/oh-my-codex" \
    "$volta_home/bin"
  printf '{"name":"oh-my-codex","version":"2.0.0"}\n' \
    > "$volta_home/tools/image/packages/oh-my-codex/lib/node_modules/oh-my-codex/package.json"
  printf '#!/usr/bin/env bash\nexit 0\n' \
    > "$volta_home/tools/image/packages/oh-my-codex/lib/node_modules/oh-my-codex/cli.js"
  "$LN_BIN" -s \
    ../tools/image/packages/oh-my-codex/lib/node_modules/oh-my-codex/cli.js \
    "$volta_home/bin/omx"
done

for npm_prefix in \
  "$HOME/.npm-global" \
  "$TMP_ROOT/npm-prefixes" \
  "$TMP_ROOT/linuxbrew-prefix"
do
  "$MKDIR_BIN" -p \
    "$npm_prefix/lib/node_modules/oh-my-codex" \
    "$npm_prefix/bin"
  printf '{"name":"oh-my-codex","version":"2.0.0"}\n' \
    > "$npm_prefix/lib/node_modules/oh-my-codex/package.json"
  printf '#!/usr/bin/env bash\nexit 0\n' \
    > "$npm_prefix/lib/node_modules/oh-my-codex/cli.js"
  "$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$npm_prefix/bin/omx"
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
manifest["format_version"] = 1
manifest["snapshot_id"] = target.name
manifest["label"] = target.name
manifest["omx"].pop("discovery", None)
manifest.pop("sensitive_data", None)
for entry in manifest["entries"]:
    entry.pop("sha256", None)
    entry.pop("size_bytes", None)
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
(target / "manifest.sha256").unlink()
PY

LEGACY_NEW_PREFIX="$TMP_ROOT/legacy-new-prefix"
"$MKDIR_BIN" -p \
  "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex" \
  "$LEGACY_NEW_PREFIX/bin"
printf '{}\n' > "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex/package.json"
printf '#!/usr/bin/env bash\nexit 0\n' \
  > "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex/cli.js"
"$LN_BIN" -s ../lib/node_modules/oh-my-codex/cli.js "$LEGACY_NEW_PREFIX/bin/omx"
OMX_GUARD_NPM_PREFIXES="$LEGACY_NEW_PREFIX" \
  "$BASH_BIN" "$GUARD" restore legacy-format
if [[ ! -d "$LEGACY_NEW_PREFIX/lib/node_modules/oh-my-codex" \
  || ! -f "$LEGACY_NEW_PREFIX/bin/omx" ]]; then
  printf 'legacy snapshot unexpectedly removed an OMX installation\n' >&2
  exit 1
fi

# Snapshot creation rejects canonical duplicates, aliases, and nested/protected roots.
PROJECT_ALIAS="$TMP_ROOT/project-alias"
"$LN_BIN" -s "$PROJECT" "$PROJECT_ALIAS"
if "$BASH_BIN" "$GUARD" snapshot duplicate \
  --project "$PROJECT" --project "$PROJECT" >/dev/null 2>&1; then
  printf 'duplicate project snapshot unexpectedly succeeded\n' >&2
  exit 1
fi
if "$BASH_BIN" "$GUARD" snapshot alias \
  --project "$PROJECT" --project "$PROJECT_ALIAS" >/dev/null 2>&1; then
  printf 'symlink-alias project snapshot unexpectedly succeeded\n' >&2
  exit 1
fi
"$MKDIR_BIN" -p "$PROJECT/nested"
if "$BASH_BIN" "$GUARD" snapshot nested \
  --project "$PROJECT" --project "$PROJECT/nested" >/dev/null 2>&1; then
  printf 'nested project snapshot unexpectedly succeeded\n' >&2
  exit 1
fi
for protected_project in "$HOME" "$CODEX_HOME" "$OMX_GUARD_STATE_HOME"; do
  if "$BASH_BIN" "$GUARD" snapshot protected \
    --project "$protected_project" >/dev/null 2>&1; then
    printf 'protected project snapshot unexpectedly succeeded: %s\n' \
      "$protected_project" >&2
    exit 1
  fi
done

# Snapshots explicitly classify project-local auth/runtime payload as sensitive.
SENSITIVE_PROJECT="$TMP_ROOT/sensitive-project"
"$MKDIR_BIN" -p "$SENSITIVE_PROJECT/.codex"
printf '{"token":"fixture-only"}\n' > "$SENSITIVE_PROJECT/.codex/auth.json"
"$BASH_BIN" "$GUARD" snapshot sensitive --project "$SENSITIVE_PROJECT" >/dev/null
python3 - "$OMX_GUARD_STATE_HOME" "$SENSITIVE_PROJECT" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]) / "snapshots"
project = Path(sys.argv[2])
snapshots = []
for path in root.iterdir():
    manifest = path / "manifest.json"
    if manifest.is_file():
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if data.get("label") == "sensitive":
            snapshots.append((path, data))
if len(snapshots) != 1:
    raise SystemExit("expected one sensitive snapshot")
path, data = snapshots[0]
if data.get("format_version") != 2:
    raise SystemExit("new snapshot did not use format 2")
if data.get("sensitive_data", {}).get("contains_sensitive_data") is not True:
    raise SystemExit("sensitive snapshot policy is missing")
manifest_bytes = (path / "manifest.json").read_bytes()
if hashlib.sha256(manifest_bytes).hexdigest() != (path / "manifest.sha256").read_text().strip():
    raise SystemExit("manifest checksum does not verify")
entry = next(item for item in data["entries"] if item["path"] == str(project / ".codex"))
auth_payload = path / "payload" / entry["archive_name"] / "auth.json"
if json.loads(auth_payload.read_text(encoding="utf-8"))["token"] != "fixture-only":
    raise SystemExit("project auth fixture was not captured")
PY

# A payload mutation is rejected before any destination is changed.
python3 - "$OMX_GUARD_STATE_HOME/snapshots/$SNAPSHOT_ID" <<'PY'
from pathlib import Path
import hashlib
import json
import shutil
import sys

source = Path(sys.argv[1])
target = source.parent / "payload-corrupt"
shutil.copytree(source, target, symlinks=True)
manifest_path = target / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["snapshot_id"] = target.name
manifest["label"] = target.name
manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
manifest_path.write_bytes(manifest_bytes)
(target / "manifest.sha256").write_text(hashlib.sha256(manifest_bytes).hexdigest() + "\n")
entry = next(item for item in manifest["entries"] if item.get("kind") == "file")
with (target / "payload" / entry["archive_name"]).open("ab") as handle:
    handle.write(b"corrupt\n")
PY
printf 'destination before corrupt restore\n' > "$CODEX_HOME/config.toml"
printf 'destination before corrupt restore\n' > "$TMP_ROOT/expected-before-corrupt.toml"
if "$BASH_BIN" "$GUARD" restore payload-corrupt >/dev/null 2>&1; then
  printf 'corrupt payload restore unexpectedly succeeded\n' >&2
  exit 1
fi
"$CMP_BIN" -s "$TMP_ROOT/expected-before-corrupt.toml" "$CODEX_HOME/config.toml"

# Staging ENOSPC and an interruption both preserve the old destination and a plan.
printf 'destination before ENOSPC\n' > "$CODEX_HOME/config.toml"
printf 'destination before ENOSPC\n' > "$TMP_ROOT/expected-before-enospc.toml"
if OMX_GUARD_TEST_RESTORE_FAIL_STAGE_INDEX=0 \
  "$BASH_BIN" "$GUARD" restore "$SNAPSHOT_ID" >/dev/null 2>&1; then
  printf 'staging ENOSPC restore unexpectedly succeeded\n' >&2
  exit 1
fi
"$CMP_BIN" -s "$TMP_ROOT/expected-before-enospc.toml" "$CODEX_HOME/config.toml"
python3 - "$OMX_GUARD_STATE_HOME" "ENOSPC" <<'PY'
from pathlib import Path
import json
import sys

plans = list((Path(sys.argv[1]) / "restore-plans").glob("*.json"))
plan_path = max(plans, key=lambda path: path.stat().st_mtime_ns)
plan = json.loads(plan_path.read_text(encoding="utf-8"))
if plan.get("status") != "rolled-back" or sys.argv[2] not in (plan.get("error") or ""):
    raise SystemExit("ENOSPC failure did not retain a rolled-back recovery plan")
if not plan.get("pre_restore_snapshot"):
    raise SystemExit("ENOSPC recovery plan did not retain pre-restore snapshot ID")
PY

printf 'destination before interrupt\n' > "$CODEX_HOME/config.toml"
printf 'destination before interrupt\n' > "$TMP_ROOT/expected-before-interrupt.toml"
if OMX_GUARD_TEST_RESTORE_INTERRUPT_INDEX=0 \
  "$BASH_BIN" "$GUARD" restore "$SNAPSHOT_ID" >/dev/null 2>&1; then
  printf 'interrupted restore unexpectedly succeeded\n' >&2
  exit 1
fi
"$CMP_BIN" -s "$TMP_ROOT/expected-before-interrupt.toml" "$CODEX_HOME/config.toml"
python3 - "$OMX_GUARD_STATE_HOME" <<'PY'
from pathlib import Path
import json
import sys

plans = list((Path(sys.argv[1]) / "restore-plans").glob("*.json"))
plan_path = max(plans, key=lambda path: path.stat().st_mtime_ns)
plan = json.loads(plan_path.read_text(encoding="utf-8"))
if plan.get("status") != "rolled-back" or "KeyboardInterrupt" not in (plan.get("error") or ""):
    raise SystemExit("interruption did not retain a rolled-back recovery plan")
if not plan.get("pre_restore_snapshot"):
    raise SystemExit("interruption plan did not retain pre-restore snapshot ID")
artifact = plan["entries"][0].get("failed_artifact")
if not artifact or not (Path(artifact).exists() or Path(artifact).is_symlink()):
    raise SystemExit("interrupted restored payload was not preserved as a recovery artifact")
PY

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
