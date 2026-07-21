#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

VERSION="2.1.1"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
HOME_DIR="${HOME:?HOME is not set}"
CODEX_HOME="${CODEX_HOME:-$HOME_DIR/.codex}"
STATE_ROOT="${OMX_GUARD_STATE_HOME:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/omx-guard}"
SNAPSHOT_ROOT="$STATE_ROOT/snapshots"
NPM_PREFIXES="${OMX_GUARD_NPM_PREFIXES:-/usr/local:/opt/homebrew:/home/linuxbrew/.linuxbrew:/usr}"

blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
red()   { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

log()  { printf '\n'; blue "==> $*"; }
ok()   { green "OK: $*"; }
warn() { yellow "WARN: $*"; }
die()  { red "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
OMX Guard — macOS/Linux용 OMX 백업·제거·복구 도구

사용법:
  omx-guard.sh status
  omx-guard.sh snapshot [이름] [--project /path]...
  omx-guard.sh list
  omx-guard.sh remove [--no-snapshot] [--purge-project-state] [--project /path]...
  omx-guard.sh restore <스냅샷-ID|label|latest>
  omx-guard.sh delete-snapshot <스냅샷-ID>
  omx-guard.sh help

권장 흐름:
  # OMX 설치 전
  ./omx-guard.sh snapshot pre-omx

  # OMX 설치·사용 후 설치 전 상태로 복구
  ./omx-guard.sh restore pre-omx

  # 현재 OMX를 완전히 제거
  ./omx-guard.sh snapshot before-omx-uninstall
  omx uninstall --dry-run
  omx uninstall
  ./omx-guard.sh remove --no-snapshot
  ./omx-guard.sh status

  # 제거 전 스냅샷으로 복구
  npm install -g oh-my-codex@<스냅샷에 기록된 버전>
  ./omx-guard.sh restore before-omx-uninstall
  omx doctor

프로젝트별 .omx/.codex까지 백업하려면:
  ./omx-guard.sh snapshot pre-omx --project ~/work/project-a

remove는 기본적으로 프로젝트의 .omx는 삭제하지 않습니다.
프로젝트 상태도 지우려면:
  ./omx-guard.sh remove --purge-project-state --project ~/work/project-a

omx uninstall --dry-run이 실패하면 실제 uninstall과 Guard remove를 진행하지 마세요.
복구 명령의 버전 자리에는 snapshot manifest의 omx.installed_version 값을 사용하세요.
스냅샷은 생성 당시와 같은 HOME 및 CODEX_HOME에서만 복구할 수 있습니다.
EOF
}

require_python() {
  command -v python3 >/dev/null 2>&1 || die "python3가 필요합니다."
  if ! python3 - <<'PY' >/dev/null
import sys
if sys.version_info < (3, 8):
    raise SystemExit(1)
PY
  then
    die "Python 3.8 이상이 필요합니다."
  fi
}

sanitize_label() {
  python3 - "$1" <<'PY'
import re, sys
value = sys.argv[1].strip() or "manual"
value = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
print(value[:60] or "manual")
PY
}

make_project_file() {
  local outfile="$1"
  shift
  : > "$outfile"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ $# -ge 2 ]] || die "--project 뒤에 경로가 필요합니다."
        python3 - "$2" >> "$outfile" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
        shift 2
        ;;
      *)
        die "알 수 없는 옵션: $1"
        ;;
    esac
  done
}

snapshot_from_project_file() {
  local label="$1"
  local project_file="$2"
  local project

  # Positional parameters remain safe when empty under macOS Bash 3.2 + nounset.
  set --
  while IFS= read -r project; do
    [[ -n "$project" ]] || continue
    set -- "$@" --project "$project"
  done < "$project_file"

  snapshot_create "$label" "$@"
}

discover_omx_installations() {
  HOME_DIR="$HOME_DIR" NPM_PREFIXES="$NPM_PREFIXES" python3 <<'PY'
from pathlib import Path
import json
import os
import shutil
import subprocess

home = Path(os.environ["HOME_DIR"]).expanduser().resolve()
package_candidates = {}
candidate_roots = {}
scan_roots = set()

def normalize(path):
    return Path(os.path.abspath(str(path.expanduser())))

def add_scan_root(path):
    path = normalize(path)
    scan_roots.add(path)
    return path

def add_candidate(package, *bins, scan_root):
    package = normalize(package)
    root = normalize(scan_root)
    normalized_bins = {normalize(binary) for binary in bins}
    package_candidates.setdefault(package, set()).update(normalized_bins)
    candidate_roots.setdefault(package, set()).add(root)
    for binary in normalized_bins:
        candidate_roots.setdefault(binary, set()).add(root)

def unique_paths(*paths):
    result = []
    seen = set()
    for path in paths:
        if path is None:
            continue
        path = normalize(path)
        key = str(path)
        if key in seen:
            continue
        seen.add(key)
        result.append(path)
    return result

def env_path(name):
    raw = os.environ.get(name)
    return Path(raw) if raw else None

xdg_config_home = env_path("XDG_CONFIG_HOME")
for nvm_root in unique_paths(
    home / ".nvm",
    xdg_config_home / "nvm" if xdg_config_home else None,
    env_path("NVM_DIR"),
):
    add_scan_root(nvm_root)
    for node_dir in (nvm_root / "versions" / "node").glob("*"):
        add_candidate(
            node_dir / "lib" / "node_modules" / "oh-my-codex",
            node_dir / "bin" / "omx",
            scan_root=nvm_root,
        )

xdg_data_home = env_path("XDG_DATA_HOME")
for fnm_root in unique_paths(
    home / ".local" / "share" / "fnm",
    home / "Library" / "Application Support" / "fnm",
    xdg_data_home / "fnm" if xdg_data_home else None,
    env_path("FNM_DIR"),
):
    add_scan_root(fnm_root)
    for install in (fnm_root / "node-versions").glob("*/installation"):
        add_candidate(
            install / "lib" / "node_modules" / "oh-my-codex",
            install / "bin" / "omx",
            scan_root=fnm_root,
        )

for volta_root in unique_paths(home / ".volta", env_path("VOLTA_HOME")):
    add_scan_root(volta_root)
    add_candidate(
        volta_root / "tools" / "image" / "packages" / "oh-my-codex",
        volta_root / "bin" / "omx",
        scan_root=volta_root,
    )

prefixes = [home / ".npm-global"]
prefixes.extend(
    Path(raw)
    for raw in os.environ["NPM_PREFIXES"].split(os.pathsep)
    if raw
)
for prefix in unique_paths(*prefixes):
    add_scan_root(prefix)
    add_candidate(
        prefix / "lib" / "node_modules" / "oh-my-codex",
        prefix / "bin" / "omx",
        scan_root=prefix,
    )

# Ask npm for its active global layout, but never let a broken npm block guard.
for command in (["npm", "prefix", "-g"], ["npm", "root", "-g"]):
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        continue
    value = result.stdout.strip()
    if not value:
        continue
    path = normalize(Path(value))
    if command[1] == "root":
        prefix = add_scan_root(path.parent.parent)
        add_candidate(
            path / "oh-my-codex",
            prefix / "bin" / "omx",
            scan_root=prefix,
        )
    else:
        add_scan_root(path)
        add_candidate(
            path / "lib" / "node_modules" / "oh-my-codex",
            path / "bin" / "omx",
            scan_root=path,
        )

active_command = shutil.which("omx")
active_path = normalize(Path(active_command)) if active_command else None
if active_path is not None:
    try:
        resolved = active_path.resolve()
        for parent in [resolved, *resolved.parents]:
            package_json = parent / "package.json"
            if not package_json.is_file():
                continue
            try:
                data = json.loads(package_json.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            is_package_boundary = (
                parent.name == "oh-my-codex"
                and parent.parent.name == "node_modules"
            )
            if (
                data.get("name") == "oh-my-codex"
                and is_package_boundary
                and parent in package_candidates
            ):
                package_candidates[parent].add(active_path)
                candidate_roots.setdefault(active_path, set()).update(
                    candidate_roots[parent]
                )
                break
    except OSError:
        pass

packages = []
removable_paths = set()
paired_binary_paths = set()
installed_version = None
npm_prefix = None

for package, bins in sorted(package_candidates.items(), key=lambda item: str(item[0])):
    if not (package.exists() or package.is_symlink()):
        continue
    version = None
    package_json_candidates = [
        package / "package.json",
        package / "lib" / "node_modules" / "oh-my-codex" / "package.json",
    ]
    for package_json in package_json_candidates:
        if not package_json.is_file():
            continue
        try:
            data = json.loads(package_json.read_text(encoding="utf-8"))
            if data.get("name") in {None, "oh-my-codex"}:
                version = data.get("version")
        except (OSError, json.JSONDecodeError):
            pass
        if version is not None:
            break
    present_bins = sorted(
        str(binary)
        for binary in bins
        if binary.exists() or binary.is_symlink()
    )
    packages.append({
        "path": str(package),
        "binary_paths": present_bins,
        "version": version,
    })
    removable_paths.add(str(package))
    removable_paths.update(present_bins)
    paired_binary_paths.update(present_bins)
    if installed_version is None and version is not None:
        installed_version = version
    parts = package.parts
    if npm_prefix is None and len(parts) >= 4 and parts[-3:-1] == ("lib", "node_modules"):
        npm_prefix = str(package.parents[2])

binary_only = []
all_binary_candidates = {
    binary
    for bins in package_candidates.values()
    for binary in bins
}

for binary in sorted(all_binary_candidates, key=str):
    binary_text = str(binary)
    if binary_text in paired_binary_paths:
        continue
    if not (binary.exists() or binary.is_symlink()):
        continue
    try:
        resolved = binary.resolve()
        belongs_to_omx = "oh-my-codex" in resolved.parts
    except OSError:
        belongs_to_omx = False
    if belongs_to_omx:
        binary_only.append(binary_text)
        removable_paths.add(binary_text)

result = {
    "schema_version": 1,
    "active_command": str(active_path) if active_path is not None else None,
    "installed": bool(packages or binary_only),
    "installed_version": installed_version,
    "npm_prefix": npm_prefix,
    "packages": packages,
    "binary_only": binary_only,
    "removable_paths": sorted(removable_paths),
    "scan_roots": sorted(str(root) for root in scan_roots),
    "path_roots": {
        path: sorted(str(root) for root in candidate_roots[Path(path)])
        for path in sorted(removable_paths)
    },
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

snapshot_create() {
  require_python

  local label="${1:-manual}"
  if [[ $# -gt 0 ]]; then shift; fi

  local project_file discovery_file
  project_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-projects.XXXXXX")"
  discovery_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-discovery.XXXXXX")"
  make_project_file "$project_file" "$@"
  discover_omx_installations > "$discovery_file"

  label="$(sanitize_label "$label")"
  mkdir -p "$SNAPSHOT_ROOT"

  log "스냅샷 생성: $label"

  HOME_DIR="$HOME_DIR" \
  CODEX_HOME="$CODEX_HOME" \
  SNAPSHOT_ROOT="$SNAPSHOT_ROOT" \
  SNAPSHOT_LABEL="$label" \
  PROJECT_FILE="$project_file" \
  OMX_DISCOVERY_FILE="$discovery_file" \
  OS_NAME="$OS_NAME" \
  python3 <<'PY'
from __future__ import annotations

from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import platform
import shutil
import sys

home = Path(os.environ["HOME_DIR"]).expanduser().resolve()
codex_home = Path(os.environ["CODEX_HOME"]).expanduser().resolve()
snapshot_root = Path(os.environ["SNAPSHOT_ROOT"]).expanduser().resolve()
label = os.environ["SNAPSHOT_LABEL"]
project_file = Path(os.environ["PROJECT_FILE"])
discovery_file = Path(os.environ["OMX_DISCOVERY_FILE"])

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
snapshot_id = f"{stamp}-{label}"
snapshot_dir = snapshot_root / snapshot_id
suffix = 1
while snapshot_dir.exists():
    snapshot_dir = snapshot_root / f"{snapshot_id}-{suffix}"
    suffix += 1

payload_dir = snapshot_dir / "payload"
payload_dir.mkdir(parents=True)

tracked = [
    codex_home / "config.toml",
    codex_home / "AGENTS.md",
    codex_home / "hooks.json",
    codex_home / "agents",
    codex_home / "prompts",
    codex_home / "skills",
    codex_home / "plugins",
    codex_home / "commands",
    codex_home / "rules",
    home / ".omx",
    home / ".agents" / "skills",
    home / ".config" / "omx",
    home / ".config" / "oh-my-codex",
]

projects = []
if project_file.exists():
    for raw in project_file.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        root = Path(raw).expanduser().resolve()
        projects.append(str(root))
        tracked.extend([
            root / ".omx",
            root / ".codex",
        ])

# Preserve order while removing duplicates.
seen = set()
unique_tracked = []
for path in tracked:
    key = str(path)
    if key in seen:
        continue
    seen.add(key)
    unique_tracked.append(path)

def copy_item(src: Path, dst: Path) -> str:
    if src.is_symlink():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.symlink_to(os.readlink(src))
        return "symlink"
    if src.is_dir():
        shutil.copytree(src, dst, symlinks=True)
        return "directory"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst, follow_symlinks=False)
    return "file"

entries = []
for index, path in enumerate(unique_tracked):
    exists = path.exists() or path.is_symlink()
    entry = {
        "path": str(path),
        "existed": exists,
        "archive_name": None,
        "kind": None,
    }
    if exists:
        archive_name = f"entry-{index:03d}"
        kind = copy_item(path, payload_dir / archive_name)
        entry["archive_name"] = archive_name
        entry["kind"] = kind
    entries.append(entry)

omx_discovery = json.loads(discovery_file.read_text(encoding="utf-8"))
if omx_discovery.get("schema_version") != 1:
    raise RuntimeError("unsupported OMX discovery schema")

manifest = {
    "format_version": 1,
    "snapshot_id": snapshot_dir.name,
    "created_at": datetime.now().astimezone().isoformat(),
    "label": label,
    "platform": {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python": platform.python_version(),
    },
    "home": str(home),
    "codex_home": str(codex_home),
    "projects": projects,
    "omx": {
        "command_path": omx_discovery.get("active_command"),
        "installed": bool(omx_discovery.get("installed")),
        "installed_version": omx_discovery.get("installed_version"),
        "npm_prefix": omx_discovery.get("npm_prefix"),
        "discovery": omx_discovery,
    },
    "entries": entries,
}

(snapshot_dir / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

print(snapshot_dir.name)
PY

  rm -f "$project_file" "$discovery_file"
}

snapshot_list() {
  require_python
  mkdir -p "$SNAPSHOT_ROOT"

  SNAPSHOT_ROOT="$SNAPSHOT_ROOT" python3 <<'PY'
from pathlib import Path
import json
import os

root = Path(os.environ["SNAPSHOT_ROOT"])
items = []

for path in sorted(root.iterdir(), reverse=True):
    manifest = path / "manifest.json"
    if not manifest.is_file():
        continue
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except Exception:
        continue
    items.append(data)

if not items:
    print("스냅샷 없음")
    raise SystemExit(0)

print(f"{'SNAPSHOT ID':<38} {'OMX':<7} {'CREATED'}")
print("-" * 90)
for item in items:
    omx = "yes" if item.get("omx", {}).get("installed") else "no"
    print(f"{item.get('snapshot_id',''):<38} {omx:<7} {item.get('created_at','')}")
PY
}

resolve_snapshot() {
  require_python
  local requested="$1"

  SNAPSHOT_ROOT="$SNAPSHOT_ROOT" REQUESTED="$requested" python3 <<'PY'
from pathlib import Path
import json
import os
import sys

root = Path(os.environ["SNAPSHOT_ROOT"]).expanduser().resolve()
requested = os.environ["REQUESTED"]

if "/" in requested or "\\" in requested or requested in {".", ".."}:
    raise SystemExit("스냅샷 ID 또는 label만 사용할 수 있습니다.")

def snapshot_directories():
    if not root.exists():
        return []
    return [
        path for path in root.iterdir()
        if not path.is_symlink() and path.is_dir()
        and not (path / "manifest.json").is_symlink()
        and (path / "manifest.json").is_file()
    ]

if requested == "latest":
    candidates = sorted(snapshot_directories(), reverse=True)
    if not candidates:
        raise SystemExit("스냅샷이 없습니다.")
    print(candidates[0].resolve())
    raise SystemExit(0)

candidate = root / requested
if (
    not candidate.is_symlink()
    and candidate.is_dir()
    and candidate.parent == root
    and (candidate / "manifest.json").is_file()
):
    print(candidate.resolve())
    raise SystemExit(0)

# Exact label match: choose most recent.
matches = []
if root.exists():
    for path in snapshot_directories():
        manifest = path / "manifest.json"
        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("label") == requested:
            matches.append(path)

if matches:
    print(sorted(matches, reverse=True)[0].resolve())
    raise SystemExit(0)

raise SystemExit(f"스냅샷을 찾을 수 없습니다: {requested}")
PY
}

remove_npm_installations() {
  local snapshot_manifest="${1:-}"
  local discovery_file
  discovery_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-discovery.XXXXXX")"
  discover_omx_installations > "$discovery_file"

  if [[ -n "$snapshot_manifest" ]]; then
    log "스냅샷 이후 추가된 OMX npm/실행 파일 제거"
  else
    log "OMX npm/실행 파일 제거"
  fi

  OMX_DISCOVERY_FILE="$discovery_file" \
  SNAPSHOT_MANIFEST="$snapshot_manifest" \
  python3 <<'PY'
from pathlib import Path
import json
import os
import shutil
import sys

discovery_path = Path(os.environ["OMX_DISCOVERY_FILE"])
current = json.loads(discovery_path.read_text(encoding="utf-8"))

def path_list(value, label):
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise SystemExit(f"{label} 경로 목록이 올바르지 않습니다.")
    paths = {Path(item) for item in value}
    if not all(path.is_absolute() for path in paths):
        raise SystemExit(f"{label} 경로는 절대 경로여야 합니다.")
    return paths

def path_root_map(value, paths, roots, label):
    if not isinstance(value, dict):
        raise SystemExit(f"{label} 경로 출처 형식이 올바르지 않습니다.")
    result = {}
    for raw_path, raw_roots in value.items():
        if not isinstance(raw_path, str):
            raise SystemExit(f"{label} 경로 출처 키가 올바르지 않습니다.")
        path = Path(raw_path)
        path_roots = path_list(raw_roots, f"{label} 경로 출처")
        if path not in paths or not path_roots or not path_roots.issubset(roots):
            raise SystemExit(f"{label} 경로 출처가 탐색 결과와 일치하지 않습니다.")
        result[path] = path_roots
    if set(result) != paths:
        raise SystemExit(f"{label} 경로 출처가 누락되었습니다.")
    return result

if current.get("schema_version") != 1:
    raise SystemExit("현재 OMX 탐색 결과 형식을 지원하지 않습니다.")

current_paths = path_list(current.get("removable_paths"), "현재 OMX")
current_roots = path_list(current.get("scan_roots"), "현재 OMX 탐색 루트")
current_path_roots = path_root_map(
    current.get("path_roots"),
    current_paths,
    current_roots,
    "현재 OMX",
)
snapshot_manifest = os.environ.get("SNAPSHOT_MANIFEST")
preserved_paths = set()
eligible_roots = current_roots

if snapshot_manifest:
    manifest = json.loads(Path(snapshot_manifest).read_text(encoding="utf-8"))
    saved = manifest.get("omx", {}).get("discovery")
    if (
        not isinstance(saved, dict)
        or saved.get("schema_version") != 1
        or not isinstance(saved.get("removable_paths"), list)
        or not isinstance(saved.get("scan_roots"), list)
        or not isinstance(saved.get("path_roots"), dict)
    ):
        print(
            "WARN: 이전 형식 스냅샷에는 정확한 설치 경로가 없어 "
            "npm 패키지/실행 파일 제거를 건너뜁니다.",
            file=sys.stderr,
        )
        raise SystemExit(0)
    preserved_paths = path_list(saved.get("removable_paths"), "스냅샷 OMX")
    saved_roots = path_list(saved.get("scan_roots"), "스냅샷 OMX 탐색 루트")
    path_root_map(
        saved.get("path_roots"),
        preserved_paths,
        saved_roots,
        "스냅샷 OMX",
    )
    eligible_roots = saved_roots

new_paths = current_paths - preserved_paths
targets = sorted(
    (
        path
        for path in new_paths
        if current_path_roots[path] & eligible_roots
    ),
    key=lambda path: (len(path.parts), str(path)),
    reverse=True,
)
skipped = sorted(new_paths - set(targets), key=str)

for target in skipped:
    print(
        "WARN: 스냅샷 당시 탐색하지 않은 루트의 OMX 경로를 보존합니다: "
        f"{target}",
        file=sys.stderr,
    )

for target in targets:
    if target.is_symlink() or target.is_file():
        target.unlink(missing_ok=True)
        print(f"removed: {target}")
    elif target.is_dir():
        shutil.rmtree(target)
        print(f"removed: {target}")
PY

  rm -f "$discovery_file"
  hash -r 2>/dev/null || true
}

clean_codex_config() {
  local config_file="$CODEX_HOME/config.toml"

  log "Codex 설정의 OMX 등록 제거"
  if [[ ! -f "$config_file" ]]; then
    ok "config.toml 없음"
    return
  fi

  CONFIG_FILE="$config_file" python3 <<'PY'
from pathlib import Path
import os
import re
import stat
import tempfile

path = Path(os.environ["CONFIG_FILE"])
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

header_re = re.compile(r'^\s*\[([^\]]+)\]\s*(?:#.*)?$')

def is_omx_section(name: str) -> bool:
    name = name.strip()
    return (
        name.startswith("mcp_servers.omx_")
        or name == "marketplaces.oh-my-codex-local"
        or name.startswith("marketplaces.oh-my-codex-local.")
        or name == 'plugins."oh-my-codex@oh-my-codex-local"'
        or name.startswith('plugins."oh-my-codex@oh-my-codex-local".')
    )

out = []
skip = False

for line in lines:
    match = header_re.match(line.rstrip("\n"))
    if match:
        skip = is_omx_section(match.group(1))
        if skip:
            continue

    if skip:
        continue

    if re.match(r'^\s*#.*(?:OMX|oh-my-codex)', line, re.IGNORECASE):
        continue

    if "oh-my-codex@oh-my-codex-local" in line:
        continue

    if re.search(r'/node_modules/oh-my-codex/', line):
        continue

    out.append(line)

cleaned = "".join(out)
cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip() + "\n"

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None

if tomllib is not None:
    tomllib.loads(cleaned)

mode = stat.S_IMODE(path.stat().st_mode)
temp_path = None
try:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as handle:
        temp_path = Path(handle.name)
        handle.write(cleaned)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temp_path, mode)
    os.replace(temp_path, path)
finally:
    if temp_path is not None and temp_path.exists():
        temp_path.unlink()

print(f"cleaned: {path}")
PY

  validate_toml "$config_file"
}

validate_toml() {
  local config_file="$1"
  [[ -f "$config_file" ]] || return 0

  CONFIG_FILE="$config_file" python3 <<'PY'
from pathlib import Path
import os
import sys

path = Path(os.environ["CONFIG_FILE"])
try:
    import tomllib
except ModuleNotFoundError:
    print("WARN: Python 3.11 미만이라 TOML 문법 검사를 건너뜁니다.")
    raise SystemExit(0)

with path.open("rb") as fp:
    tomllib.load(fp)

print("OK: config.toml TOML 문법 정상")
PY
}

remove_state() {
  log "OMX 상태/캐시 제거"

  HOME_DIR="$HOME_DIR" CODEX_HOME="$CODEX_HOME" python3 <<'PY'
from pathlib import Path
import os
import shutil

home = Path(os.environ["HOME_DIR"]).expanduser().resolve()
codex_home = Path(os.environ["CODEX_HOME"]).expanduser().resolve()

targets = [
    home / ".omx",
    home / ".config" / "omx",
    home / ".config" / "oh-my-codex",
]

for target in targets:
    if target.is_symlink() or target.is_file():
        target.unlink(missing_ok=True)
        print(f"removed: {target}")
    elif target.is_dir():
        shutil.rmtree(target)
        print(f"removed: {target}")

cache_root = codex_home / "plugins" / "cache"
if cache_root.is_dir():
    matches = sorted(
        [
            path for path in cache_root.rglob("*")
            if path.is_dir() and path.name in {"oh-my-codex", "oh-my-codex-local"}
        ],
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for path in matches:
        if path.exists():
            shutil.rmtree(path)
            print(f"removed: {path}")
PY
}

remove_projects() {
  local project_file="$1"

  [[ -s "$project_file" ]] || {
    warn "--purge-project-state가 지정됐지만 --project 경로가 없습니다."
    return
  }

  log "지정한 프로젝트의 OMX 상태 제거"
  PROJECT_FILE="$project_file" python3 <<'PY'
from pathlib import Path
import os
import shutil

project_file = Path(os.environ["PROJECT_FILE"])

for raw in project_file.read_text(encoding="utf-8").splitlines():
    raw = raw.strip()
    if not raw:
        continue

    root = Path(raw).expanduser().resolve()
    target = root / ".omx"

    if target.is_symlink() or target.is_file():
        target.unlink(missing_ok=True)
        print(f"removed: {target}")
    elif target.is_dir():
        shutil.rmtree(target)
        print(f"removed: {target}")
PY
}

status_report() {
  require_python

  log "환경"
  echo "OS=$OS_NAME"
  echo "HOME=$HOME_DIR"
  echo "CODEX_HOME=$CODEX_HOME"
  echo "STATE_ROOT=$STATE_ROOT"

  log "OMX 명령"
  if command -v omx >/dev/null 2>&1; then
    command -v omx
  else
    ok "omx not found"
  fi

  log "전역 패키지/바이너리 흔적"
  local discovery_file
  discovery_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-discovery.XXXXXX")"
  discover_omx_installations > "$discovery_file"
  OMX_DISCOVERY_FILE="$discovery_file" python3 <<'PY'
from pathlib import Path
import json
import os

data = json.loads(
    Path(os.environ["OMX_DISCOVERY_FILE"]).read_text(encoding="utf-8")
)
found = data.get("removable_paths", [])
if found:
    for path in found:
        print(path)
else:
    print("OK: 알려진 Node 관리 경로에 OMX 없음")
PY
  rm -f "$discovery_file"

  log "주요 Codex 설정의 OMX 흔적"
  local found_config=false
  local file
  for file in \
    "$CODEX_HOME/config.toml" \
    "$CODEX_HOME/AGENTS.md" \
    "$CODEX_HOME/hooks.json"
  do
    [[ -f "$file" ]] || continue
    if grep -nEi \
      'OMX|oh-my-codex|oh-my-codex-local|mcp_servers\.omx_' \
      "$file" 2>/dev/null
    then
      found_config=true
    fi
  done

  if [[ "$found_config" == false ]]; then
    ok "주요 Codex 설정에 OMX 문자열 없음"
  fi

  log "OMX가 남겼을 수 있지만 Codex 자체 설정일 수도 있는 항목"
  if [[ -f "$CODEX_HOME/config.toml" ]]; then
    if grep -nE       '^[[:space:]]*(multi_agent|max_threads|max_depth)[[:space:]]*='       "$CODEX_HOME/config.toml" 2>/dev/null
    then
      warn "위 항목은 사용자 설정일 수도 있어 remove가 자동 삭제하지 않습니다."
      warn "OMX 설치 전 스냅샷을 restore하면 설치 전 상태로 정확히 돌아갑니다."
    else
      ok "검토가 필요한 legacy agent 설정 없음"
    fi
  else
    ok "config.toml 없음"
  fi

  log "스냅샷"
  snapshot_list
}

remove_command() {
  require_python

  local purge_projects=false
  local no_snapshot=false
  local project_file
  project_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-projects.XXXXXX")"
  : > "$project_file"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge-project-state)
        purge_projects=true
        shift
        ;;
      --no-snapshot)
        no_snapshot=true
        shift
        ;;
      --project)
        [[ $# -ge 2 ]] || die "--project 뒤에 경로가 필요합니다."
        python3 - "$2" >> "$project_file" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
        shift 2
        ;;
      *)
        die "알 수 없는 옵션: $1"
        ;;
    esac
  done

  if [[ "$no_snapshot" == false ]]; then
    snapshot_from_project_file "pre-remove" "$project_file"
  fi

  remove_npm_installations
  clean_codex_config
  remove_state

  if [[ "$purge_projects" == true ]]; then
    remove_projects "$project_file"
  fi

  rm -f "$project_file"

  log "제거 후 상태"
  status_report
}

restore_command() {
  require_python
  [[ $# -ge 1 ]] || die "복구할 스냅샷 ID 또는 label이 필요합니다."

  local requested="$1"
  local snapshot_dir
  snapshot_dir="$(resolve_snapshot "$requested")"
  local manifest="$snapshot_dir/manifest.json"

  [[ -f "$manifest" ]] || die "manifest.json이 없습니다: $snapshot_dir"

  log "스냅샷 경로/환경 검증"
  HOME_DIR="$HOME_DIR" CODEX_HOME="$CODEX_HOME" MANIFEST="$manifest" python3 <<'PY'
from pathlib import Path
import json
import os

manifest_path = Path(os.environ["MANIFEST"]).resolve()
snapshot_dir = manifest_path.parent
payload = snapshot_dir / "payload"
data = json.loads(manifest_path.read_text(encoding="utf-8"))
current_home = str(Path(os.environ["HOME_DIR"]).expanduser().resolve())
current_codex = str(Path(os.environ["CODEX_HOME"]).expanduser().resolve())

if data.get("format_version") != 1:
    raise SystemExit("지원하지 않는 스냅샷 manifest 형식입니다.")

if data.get("snapshot_id") != snapshot_dir.name:
    raise SystemExit("스냅샷 ID와 디렉터리 이름이 일치하지 않습니다.")

if data.get("home") != current_home:
    raise SystemExit(
        "스냅샷 HOME과 현재 HOME이 다릅니다. "
        f"snapshot={data.get('home')} current={current_home}"
    )

if data.get("codex_home") != current_codex:
    raise SystemExit(
        "스냅샷 CODEX_HOME과 현재 CODEX_HOME이 다릅니다. "
        f"snapshot={data.get('codex_home')} current={current_codex}"
    )

project_values = data.get("projects", [])
if not isinstance(project_values, list) or not all(
    isinstance(project, str) for project in project_values
):
    raise SystemExit("스냅샷 projects 형식이 올바르지 않습니다.")

projects = [Path(project).expanduser().resolve() for project in project_values]
if [str(project) for project in projects] != project_values:
    raise SystemExit("스냅샷 project 경로가 정규화되어 있지 않습니다.")

if len(set(project_values)) != len(project_values):
    raise SystemExit("스냅샷 project 경로가 중복되었습니다.")

home = Path(current_home)
codex_home = Path(current_codex)
tracked = [
    codex_home / "config.toml",
    codex_home / "AGENTS.md",
    codex_home / "hooks.json",
    codex_home / "agents",
    codex_home / "prompts",
    codex_home / "skills",
    codex_home / "plugins",
    codex_home / "commands",
    codex_home / "rules",
    home / ".omx",
    home / ".agents" / "skills",
    home / ".config" / "omx",
    home / ".config" / "oh-my-codex",
]
for project in projects:
    tracked.extend([project / ".omx", project / ".codex"])

expected_paths = []
seen = set()
for path in tracked:
    key = str(path)
    if key in seen:
        continue
    seen.add(key)
    expected_paths.append(path)

entries = data.get("entries")
if not isinstance(entries, list) or len(entries) != len(expected_paths):
    raise SystemExit("스냅샷 entries 개수가 추적 경로와 일치하지 않습니다.")

if not payload.is_dir() or payload.is_symlink():
    raise SystemExit("스냅샷 payload 디렉터리가 없거나 안전하지 않습니다.")

for index, (entry, expected_path) in enumerate(zip(entries, expected_paths)):
    if not isinstance(entry, dict):
        raise SystemExit(f"스냅샷 entry 형식이 올바르지 않습니다: {index}")
    if entry.get("path") != str(expected_path):
        raise SystemExit(f"허용되지 않은 복구 경로입니다: {entry.get('path')}")

    existed = entry.get("existed")
    if not isinstance(existed, bool):
        raise SystemExit(f"스냅샷 existed 값이 올바르지 않습니다: {expected_path}")

    if not existed:
        if entry.get("archive_name") is not None or entry.get("kind") is not None:
            raise SystemExit(f"존재하지 않은 경로의 payload 정보가 올바르지 않습니다: {expected_path}")
        continue

    archive_name = f"entry-{index:03d}"
    kind = entry.get("kind")
    if entry.get("archive_name") != archive_name:
        raise SystemExit(f"스냅샷 archive 이름이 올바르지 않습니다: {expected_path}")
    if kind not in {"file", "directory", "symlink"}:
        raise SystemExit(f"스냅샷 payload 종류가 올바르지 않습니다: {expected_path}")

    source = payload / archive_name
    if kind == "symlink" and not source.is_symlink():
        raise SystemExit(f"스냅샷 symlink payload가 없습니다: {expected_path}")
    if kind == "directory" and (source.is_symlink() or not source.is_dir()):
        raise SystemExit(f"스냅샷 directory payload가 없습니다: {expected_path}")
    if kind == "file" and (source.is_symlink() or not source.is_file()):
        raise SystemExit(f"스냅샷 file payload가 없습니다: {expected_path}")

print("OK: 현재 환경, 복구 경로, payload 검증 완료")
PY

  log "현재 상태 안전 백업"
  local restore_project_file
  restore_project_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-restore-projects.XXXXXX")"

  MANIFEST="$manifest" python3 <<'PY' > "$restore_project_file"
from pathlib import Path
import json
import os

data = json.loads(Path(os.environ["MANIFEST"]).read_text(encoding="utf-8"))
for project in data.get("projects", []):
    print(project)
PY

  snapshot_from_project_file "pre-restore" "$restore_project_file"
  rm -f "$restore_project_file"

  remove_npm_installations "$manifest"

  log "스냅샷 복구: $(basename "$snapshot_dir")"
  SNAPSHOT_DIR="$snapshot_dir" python3 <<'PY'
from __future__ import annotations

from pathlib import Path
import json
import os
import shutil

snapshot_dir = Path(os.environ["SNAPSHOT_DIR"])
manifest = json.loads(
    (snapshot_dir / "manifest.json").read_text(encoding="utf-8")
)
payload = snapshot_dir / "payload"

def remove_item(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path)

def restore_item(src: Path, dst: Path, kind: str | None) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if kind == "symlink":
        dst.symlink_to(os.readlink(src))
    elif kind == "directory":
        shutil.copytree(src, dst, symlinks=True)
    else:
        shutil.copy2(src, dst, follow_symlinks=False)

for entry in manifest.get("entries", []):
    destination = Path(entry["path"])
    remove_item(destination)

    if entry.get("existed"):
        archive_name = entry.get("archive_name")
        if not archive_name:
            raise RuntimeError(f"archive_name missing: {destination}")
        restore_item(
            payload / archive_name,
            destination,
            entry.get("kind"),
        )
        print(f"restored: {destination}")
    else:
        print(f"restored-absent: {destination}")
PY

  validate_toml "$CODEX_HOME/config.toml"

  log "복구 후 상태"
  status_report
}

delete_snapshot() {
  require_python
  [[ $# -ge 1 ]] || die "삭제할 스냅샷 ID가 필요합니다."

  local snapshot_dir
  snapshot_dir="$(resolve_snapshot "$1")"

  case "$snapshot_dir" in
    "$SNAPSHOT_ROOT"/*)
      rm -rf "$snapshot_dir"
      ok "스냅샷 삭제: $(basename "$snapshot_dir")"
      ;;
    *)
      die "안전하지 않은 스냅샷 경로입니다: $snapshot_dir"
      ;;
  esac
}

main() {
  local command="${1:-help}"
  if [[ $# -gt 0 ]]; then shift; fi

  case "$command" in
    status)
      status_report "$@"
      ;;
    snapshot)
      snapshot_create "$@"
      ;;
    list)
      snapshot_list
      ;;
    remove)
      remove_command "$@"
      ;;
    restore)
      restore_command "$@"
      ;;
    delete-snapshot)
      delete_snapshot "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    version|--version)
      echo "$VERSION"
      ;;
    *)
      usage
      die "알 수 없는 명령: $command"
      ;;
  esac
}

main "$@"
