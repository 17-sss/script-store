#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

VERSION="2.2.0"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
HOME_DIR="${HOME:?HOME is not set}"
CODEX_HOME="${CODEX_HOME:-$HOME_DIR/.codex}"
STATE_ROOT="${OMX_GUARD_STATE_HOME:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/omx-guard}"
SNAPSHOT_ROOT="$STATE_ROOT/snapshots"
NPM_PREFIXES="${OMX_GUARD_NPM_PREFIXES:-/usr/local:/opt/homebrew:/home/linuxbrew/.linuxbrew:/usr}"
LAST_SNAPSHOT_ID=""

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
ambiguous_paths = set()
valid_packages = set()
installed_version = None
npm_prefix = None

def package_identity(package):
    package_json_candidates = [
        package / "package.json",
        package / "lib" / "node_modules" / "oh-my-codex" / "package.json",
    ]
    for package_json in package_json_candidates:
        if not package_json.is_file():
            continue
        try:
            data = json.loads(package_json.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and data.get("name") == "oh-my-codex":
            return True, data.get("version")
    return False, None

def binary_points_to_package(binary, package):
    if not binary.is_symlink():
        return False
    try:
        resolved_binary = binary.resolve(strict=False)
        resolved_package = package.resolve(strict=False)
    except OSError:
        return False
    return resolved_binary == resolved_package or resolved_package in resolved_binary.parents

for package, bins in sorted(package_candidates.items(), key=lambda item: str(item[0])):
    if not (package.exists() or package.is_symlink()):
        continue

    identity_matches, version = package_identity(package)
    if not identity_matches:
        ambiguous_paths.add(str(package))
        ambiguous_paths.update(
            str(binary)
            for binary in bins
            if binary.exists() or binary.is_symlink()
        )
        continue

    valid_packages.add(package)
    present_bins = sorted(
        str(binary)
        for binary in bins
        if (binary.exists() or binary.is_symlink())
        and binary_points_to_package(binary, package)
    )
    ambiguous_paths.update(
        str(binary)
        for binary in bins
        if (binary.exists() or binary.is_symlink())
        and str(binary) not in present_bins
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

    matching_packages = [
        package
        for package in package_candidates
        if (
            package in valid_packages
            or not (package.exists() or package.is_symlink())
        )
        and binary_points_to_package(binary, package)
    ]
    if matching_packages:
        binary_only.append(binary_text)
        removable_paths.add(binary_text)
    else:
        ambiguous_paths.add(binary_text)

result = {
    "schema_version": 1,
    "active_command": str(active_path) if active_path is not None else None,
    "installed": bool(packages or binary_only),
    "installed_version": installed_version,
    "npm_prefix": npm_prefix,
    "packages": packages,
    "binary_only": binary_only,
    "ambiguous_paths": sorted(ambiguous_paths - removable_paths),
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

  local created_snapshot
  created_snapshot="$(
    HOME_DIR="$HOME_DIR" \
    CODEX_HOME="$CODEX_HOME" \
    STATE_ROOT="$STATE_ROOT" \
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
import tempfile

home = Path(os.environ["HOME_DIR"]).expanduser().resolve()
codex_home = Path(os.environ["CODEX_HOME"]).expanduser().resolve()
snapshot_root = Path(os.environ["SNAPSHOT_ROOT"]).expanduser().resolve()
state_root = Path(os.environ["STATE_ROOT"]).expanduser().resolve()
label = os.environ["SNAPSHOT_LABEL"]
project_file = Path(os.environ["PROJECT_FILE"])
discovery_file = Path(os.environ["OMX_DISCOVERY_FILE"])

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
project_paths = []
if project_file.exists():
    for raw in project_file.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        root = Path(raw).expanduser().resolve()
        project_paths.append(root)
        projects.append(str(root))
        tracked.extend([
            root / ".omx",
            root / ".codex",
        ])

def contains(parent: Path, child: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False

if len(set(projects)) != len(projects):
    raise SystemExit("동일한 project 경로를 중복 지정할 수 없습니다.")

for index, project in enumerate(project_paths):
    if contains(project, home):
        raise SystemExit(f"project가 HOME과 같거나 HOME의 상위 경로입니다: {project}")
    for protected_name, protected in (
        ("CODEX_HOME", codex_home),
        ("OMX Guard state root", state_root),
        ("snapshot root", snapshot_root),
    ):
        if contains(project, protected) or contains(protected, project):
            raise SystemExit(f"project가 {protected_name}과 중첩됩니다: {project}")
    for other in project_paths[index + 1:]:
        if contains(project, other) or contains(other, project):
            raise SystemExit(f"project 경로가 서로 중첩됩니다: {project} / {other}")

for index, path in enumerate(tracked):
    for other in tracked[index + 1:]:
        if contains(path, other) or contains(other, path):
            raise SystemExit(f"백업 대상 경로가 중복 또는 중첩됩니다: {path} / {other}")

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
snapshot_id = f"{stamp}-{label}"
snapshot_dir = snapshot_root / snapshot_id
suffix = 1
while snapshot_dir.exists():
    snapshot_dir = snapshot_root / f"{snapshot_id}-{suffix}"
    suffix += 1

partial_dir = Path(tempfile.mkdtemp(
    prefix=f".partial-{snapshot_dir.name}-",
    dir=str(snapshot_root),
))
payload_dir = partial_dir / "payload"
payload_dir.mkdir()

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

def payload_digest(path: Path, kind: str):
    digest = hashlib.sha256()
    size = 0

    def add_record(record_kind: str, relative: str, value: bytes = b""):
        nonlocal size
        header = (
            record_kind.encode("ascii") + b"\0"
            + relative.encode("utf-8", "surrogateescape") + b"\0"
        )
        digest.update(header)
        digest.update(value)
        digest.update(b"\0")
        size += len(value)

    if kind == "symlink":
        add_record("symlink", ".", os.fsencode(os.readlink(path)))
    elif kind == "file":
        add_record("file", ".")
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                size += len(chunk)
    else:
        add_record("directory", ".")
        for root, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
            root_path = Path(root)
            names = sorted(dirnames + filenames)
            dirnames[:] = sorted(dirnames)
            for name in names:
                item = root_path / name
                relative = str(item.relative_to(path))
                if item.is_symlink():
                    add_record("symlink", relative, os.fsencode(os.readlink(item)))
                    if name in dirnames:
                        dirnames.remove(name)
                elif item.is_dir():
                    add_record("directory", relative)
                elif item.is_file():
                    add_record("file", relative)
                    with item.open("rb") as handle:
                        while True:
                            chunk = handle.read(1024 * 1024)
                            if not chunk:
                                break
                            digest.update(chunk)
                            size += len(chunk)
                else:
                    raise RuntimeError(f"지원하지 않는 payload 항목입니다: {item}")
    return digest.hexdigest(), size

entries = []
try:
    for index, path in enumerate(tracked):
        exists = path.exists() or path.is_symlink()
        entry = {
            "path": str(path),
            "existed": exists,
            "archive_name": None,
            "kind": None,
            "sha256": None,
            "size_bytes": None,
        }
        if exists:
            archive_name = f"entry-{index:03d}"
            archived = payload_dir / archive_name
            kind = copy_item(path, archived)
            digest, size = payload_digest(archived, kind)
            entry.update({
                "archive_name": archive_name,
                "kind": kind,
                "sha256": digest,
                "size_bytes": size,
            })
        entries.append(entry)

    omx_discovery = json.loads(discovery_file.read_text(encoding="utf-8"))
    if omx_discovery.get("schema_version") != 1:
        raise RuntimeError("unsupported OMX discovery schema")

    manifest = {
        "format_version": 2,
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
        "sensitive_data": {
            "classification": "private-local-recovery",
            "contains_sensitive_data": True,
            "may_include": [
                "$HOME/.omx authentication and runtime state",
                "selected project .omx and .codex authentication or runtime state",
                "Codex configuration, prompts, skills, plugins, commands, and rules",
            ],
            "sharing": "do-not-share-without-review",
        },
        "omx": {
            "command_path": omx_discovery.get("active_command"),
            "installed": bool(omx_discovery.get("installed")),
            "installed_version": omx_discovery.get("installed_version"),
            "npm_prefix": omx_discovery.get("npm_prefix"),
            "discovery": omx_discovery,
        },
        "entries": entries,
    }

    manifest_bytes = (
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    ).encode("utf-8")
    (partial_dir / "manifest.json").write_bytes(manifest_bytes)
    manifest_digest = hashlib.sha256(manifest_bytes).hexdigest()
    (partial_dir / "manifest.sha256").write_text(
        manifest_digest + "\n",
        encoding="ascii",
    )

    for entry in entries:
        if not entry["existed"]:
            continue
        archived = payload_dir / entry["archive_name"]
        actual_digest, actual_size = payload_digest(archived, entry["kind"])
        if actual_digest != entry["sha256"] or actual_size != entry["size_bytes"]:
            raise RuntimeError(f"snapshot payload self-check failed: {entry['path']}")

    partial_dir.rename(snapshot_dir)
except BaseException:
    if partial_dir.exists():
        shutil.rmtree(partial_dir)
    raise

print(snapshot_dir.name)
PY
  )"

  rm -f "$project_file" "$discovery_file"
  LAST_SNAPSHOT_ID="$created_snapshot"
  printf '%s\n' "$created_snapshot"
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
    and not (candidate / "manifest.json").is_symlink()
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
  local restore_plan="${2:-}"
  local discovery_file
  discovery_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-discovery.XXXXXX")"
  discover_omx_installations > "$discovery_file"

  if [[ -n "$snapshot_manifest" || -n "$restore_plan" ]]; then
    log "스냅샷 이후 추가된 OMX npm/실행 파일 제거"
  else
    log "OMX npm/실행 파일 제거"
  fi

  OMX_DISCOVERY_FILE="$discovery_file" \
  SNAPSHOT_MANIFEST="$snapshot_manifest" \
  RESTORE_PLAN="$restore_plan" \
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
ambiguous_paths = path_list(current.get("ambiguous_paths", []), "소유권 불명 OMX")
current_path_roots = path_root_map(
    current.get("path_roots"),
    current_paths,
    current_roots,
    "현재 OMX",
)
snapshot_manifest = os.environ.get("SNAPSHOT_MANIFEST")
restore_plan = os.environ.get("RESTORE_PLAN")
preserved_paths = set()
eligible_roots = current_roots

if restore_plan:
    plan = json.loads(Path(restore_plan).read_text(encoding="utf-8"))
    saved = plan.get("omx", {}).get("discovery")
elif snapshot_manifest:
    manifest = json.loads(Path(snapshot_manifest).read_text(encoding="utf-8"))
    saved = manifest.get("omx", {}).get("discovery")
else:
    saved = None

if restore_plan or snapshot_manifest:
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

for target in sorted(ambiguous_paths, key=str):
    print(
        "WARN: OMX 소유권을 입증할 수 없어 경로를 보존합니다: "
        f"{target}",
        file=sys.stderr,
    )

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
import json
import os
import re
import stat
import tempfile

path = Path(os.environ["CONFIG_FILE"])
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

try:
    import tomllib as toml_parser
except ModuleNotFoundError:
    try:
        import tomli as toml_parser
    except ModuleNotFoundError:
        toml_parser = None

if toml_parser is not None:
    toml_parser.loads(text)

def parse_dotted_key(raw):
    parts = []
    index = 0
    length = len(raw)
    while True:
        while index < length and raw[index].isspace():
            index += 1
        if index >= length:
            return None

        quote = raw[index] if raw[index] in {'"', "'"} else None
        if quote is not None:
            index += 1
            start = index
            escaped = False
            while index < length:
                char = raw[index]
                if quote == '"' and char == "\\":
                    escaped = True
                    index += 2
                    continue
                if char == quote:
                    break
                index += 1
            if index >= length:
                return None
            token = raw[start:index]
            index += 1
            if escaped:
                try:
                    token = json.loads(f'"{token}"')
                except (TypeError, ValueError):
                    return None
        else:
            match = re.match(r"[A-Za-z0-9_-]+", raw[index:])
            if match is None:
                return None
            token = match.group(0)
            index += len(token)

        parts.append(token)
        while index < length and raw[index].isspace():
            index += 1
        if index == length:
            return parts
        if raw[index] != ".":
            return None
        index += 1

def table_header_parts(line):
    stripped = line.lstrip().rstrip("\r\n")
    if not stripped.startswith("[") or stripped.startswith("[["):
        return None

    quote = None
    escaped = False
    for index in range(1, len(stripped)):
        char = stripped[index]
        if quote == '"':
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if quote == "'":
            if char == quote:
                quote = None
            continue
        if char in {'"', "'"}:
            quote = char
            continue
        if char == "]":
            tail = stripped[index + 1:].strip()
            if tail and not tail.startswith("#"):
                return None
            return parse_dotted_key(stripped[1:index])
    return None

def advance_multiline_state(line, state):
    index = 0
    length = len(line)
    while index < length:
        if state is not None:
            found = line.find(state, index)
            if found < 0:
                return state
            if state == '\"\"\"':
                backslashes = 0
                cursor = found - 1
                while cursor >= 0 and line[cursor] == "\\":
                    backslashes += 1
                    cursor -= 1
                if backslashes % 2 == 1:
                    index = found + 3
                    continue
            state = None
            index = found + 3
            continue

        if line[index] == "#":
            return state
        if line.startswith('\"\"\"', index) or line.startswith("'''", index):
            state = line[index:index + 3]
            index += 3
            continue
        if line[index] == '"':
            index += 1
            while index < length:
                if line[index] == "\\":
                    index += 2
                elif line[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            continue
        if line[index] == "'":
            closing = line.find("'", index + 1)
            index = length if closing < 0 else closing + 1
            continue
        index += 1
    return state

def is_owned_omx_section(parts):
    if not parts or len(parts) < 2:
        return False
    return (
        (parts[0] == "mcp_servers" and parts[1].startswith("omx_"))
        or (parts[0] == "marketplaces" and parts[1] == "oh-my-codex-local")
        or (parts[0] == "plugins" and parts[1] == "oh-my-codex@oh-my-codex-local")
    )

out = []
skip = False
multiline_state = None
removed_sections = []

for line in lines:
    parts = table_header_parts(line) if multiline_state is None else None
    if parts is not None:
        skip = is_owned_omx_section(parts)
        if skip:
            removed_sections.append(".".join(parts))
    if not skip:
        out.append(line)
    multiline_state = advance_multiline_state(line, multiline_state)

if not removed_sections:
    print(f"unchanged: {path} (입증된 OMX table 없음)")
    raise SystemExit(0)

cleaned = "".join(out)
if toml_parser is not None:
    toml_parser.loads(cleaned)

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

print(f"cleaned: {path} ({len(removed_sections)}개 OMX table 제거)")
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
    import tomllib as toml_parser
except ModuleNotFoundError:
    try:
        import tomli as toml_parser
    except ModuleNotFoundError:
        print(
            "WARN: tomllib/tomli가 없어 TOML 전체 문법 검사는 생략했습니다. "
            "remove는 입증된 table 경계만 byte-preserving 방식으로 수정합니다."
        )
        raise SystemExit(0)

with path.open("rb") as fp:
    toml_parser.load(fp)

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
ambiguous = data.get("ambiguous_paths", [])
if found:
    for path in found:
        print(path)
elif not ambiguous:
    print("OK: 알려진 Node 관리 경로에 OMX 없음")
for path in ambiguous:
    print(f"WARN: OMX 소유권 불명, 자동 제거하지 않음: {path}")
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

  local restore_project_file restore_plan_file restore_plan
  restore_project_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-restore-projects.XXXXXX")"
  restore_plan_file="$(mktemp "${TMPDIR:-/tmp}/omx-guard-restore-plan.XXXXXX")"

  log "스냅샷 무결성/경로 검증 및 복구 계획 생성"
  HOME_DIR="$HOME_DIR" \
  CODEX_HOME="$CODEX_HOME" \
  STATE_ROOT="$STATE_ROOT" \
  SNAPSHOT_ROOT="$SNAPSHOT_ROOT" \
  SNAPSHOT_DIR="$snapshot_dir" \
  PROJECT_OUTPUT="$restore_project_file" \
  PLAN_OUTPUT="$restore_plan_file" \
  python3 <<'PY'
from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import re
import stat
import tempfile
import uuid

home = Path(os.environ["HOME_DIR"]).expanduser().resolve()
codex_home = Path(os.environ["CODEX_HOME"]).expanduser().resolve()
state_root = Path(os.environ["STATE_ROOT"]).expanduser().resolve()
snapshot_root = Path(os.environ["SNAPSHOT_ROOT"]).expanduser().resolve()
raw_snapshot_dir = Path(os.environ["SNAPSHOT_DIR"])
project_output = Path(os.environ["PROJECT_OUTPUT"])
plan_output = Path(os.environ["PLAN_OUTPUT"])

if raw_snapshot_dir.is_symlink():
    raise SystemExit("symlink 스냅샷 디렉터리는 복구할 수 없습니다.")
snapshot_dir = raw_snapshot_dir.resolve()
if snapshot_dir.parent != snapshot_root:
    raise SystemExit("스냅샷 루트 밖의 경로는 복구할 수 없습니다.")

manifest_path = snapshot_dir / "manifest.json"
if manifest_path.is_symlink() or not manifest_path.is_file():
    raise SystemExit("manifest.json이 없거나 안전하지 않습니다.")
manifest_bytes = manifest_path.read_bytes()
manifest_sha256 = hashlib.sha256(manifest_bytes).hexdigest()
try:
    data = json.loads(manifest_bytes.decode("utf-8"))
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"manifest.json을 읽을 수 없습니다: {error}")

format_version = data.get("format_version")
if format_version not in {1, 2}:
    raise SystemExit("지원하지 않는 스냅샷 manifest 형식입니다.")

legacy_limited = format_version == 1
if legacy_limited:
    print(
        "WARN: format 1 스냅샷은 payload checksum이 없는 제한 모드로 복구합니다.",
        file=os.sys.stderr,
    )
else:
    checksum_path = snapshot_dir / "manifest.sha256"
    if checksum_path.is_symlink() or not checksum_path.is_file():
        raise SystemExit("manifest.sha256이 없거나 안전하지 않습니다.")
    expected_manifest_sha = checksum_path.read_text(encoding="ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_manifest_sha):
        raise SystemExit("manifest.sha256 형식이 올바르지 않습니다.")
    if expected_manifest_sha != manifest_sha256:
        raise SystemExit("manifest.json checksum이 일치하지 않습니다.")
    sensitive = data.get("sensitive_data")
    if not isinstance(sensitive, dict) or sensitive.get("contains_sensitive_data") is not True:
        raise SystemExit("민감 데이터 취급 정책이 manifest에 명시되지 않았습니다.")

if data.get("snapshot_id") != snapshot_dir.name:
    raise SystemExit("스냅샷 ID와 디렉터리 이름이 일치하지 않습니다.")
if data.get("home") != str(home):
    raise SystemExit(
        "스냅샷 HOME과 현재 HOME이 다릅니다. "
        f"snapshot={data.get('home')} current={home}"
    )
if data.get("codex_home") != str(codex_home):
    raise SystemExit(
        "스냅샷 CODEX_HOME과 현재 CODEX_HOME이 다릅니다. "
        f"snapshot={data.get('codex_home')} current={codex_home}"
    )

def contains(parent, child):
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False

project_values = data.get("projects", [])
if not isinstance(project_values, list) or not all(isinstance(value, str) for value in project_values):
    raise SystemExit("스냅샷 projects 형식이 올바르지 않습니다.")
projects = [Path(value).expanduser().resolve() for value in project_values]
if [str(project) for project in projects] != project_values:
    raise SystemExit("스냅샷 project 경로가 정규화되어 있지 않습니다.")
if len(set(project_values)) != len(project_values):
    raise SystemExit("스냅샷 project 경로가 중복되었습니다.")
for index, project in enumerate(projects):
    if contains(project, home):
        raise SystemExit(f"project가 HOME과 같거나 HOME의 상위 경로입니다: {project}")
    for protected_name, protected in (
        ("CODEX_HOME", codex_home),
        ("OMX Guard state root", state_root),
        ("snapshot root", snapshot_root),
    ):
        if contains(project, protected) or contains(protected, project):
            raise SystemExit(f"project가 {protected_name}과 중첩됩니다: {project}")
    for other in projects[index + 1:]:
        if contains(project, other) or contains(other, project):
            raise SystemExit(f"project 경로가 서로 중첩됩니다: {project} / {other}")

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

if legacy_limited:
    expected_paths = []
    seen = set()
    for path in tracked:
        if str(path) not in seen:
            seen.add(str(path))
            expected_paths.append(path)
else:
    expected_paths = tracked
    for index, path in enumerate(expected_paths):
        for other in expected_paths[index + 1:]:
            if contains(path, other) or contains(other, path):
                raise SystemExit(f"복구 경로가 중복 또는 중첩됩니다: {path} / {other}")

payload = snapshot_dir / "payload"
if payload.is_symlink() or not payload.is_dir():
    raise SystemExit("스냅샷 payload 디렉터리가 없거나 안전하지 않습니다.")

def payload_digest(path, kind):
    digest = hashlib.sha256()
    size = 0

    def add_record(record_kind, relative, value=b""):
        nonlocal size
        digest.update(record_kind.encode("ascii") + b"\0")
        digest.update(relative.encode("utf-8", "surrogateescape") + b"\0")
        digest.update(value)
        digest.update(b"\0")
        size += len(value)

    if kind == "symlink":
        add_record("symlink", ".", os.fsencode(os.readlink(path)))
    elif kind == "file":
        add_record("file", ".")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
                size += len(chunk)
    else:
        add_record("directory", ".")
        for root, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
            root_path = Path(root)
            names = sorted(dirnames + filenames)
            dirnames[:] = sorted(dirnames)
            for name in names:
                item = root_path / name
                relative = str(item.relative_to(path))
                if item.is_symlink():
                    add_record("symlink", relative, os.fsencode(os.readlink(item)))
                    if name in dirnames:
                        dirnames.remove(name)
                elif item.is_dir():
                    add_record("directory", relative)
                elif item.is_file():
                    add_record("file", relative)
                    with item.open("rb") as handle:
                        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                            digest.update(chunk)
                            size += len(chunk)
                else:
                    raise SystemExit(f"지원하지 않는 payload 항목입니다: {item}")
    return digest.hexdigest(), size

entries = data.get("entries")
if not isinstance(entries, list) or len(entries) != len(expected_paths):
    raise SystemExit("스냅샷 entries 개수가 추적 경로와 일치하지 않습니다.")

plan_entries = []
for index, (entry, expected_path) in enumerate(zip(entries, expected_paths)):
    if not isinstance(entry, dict) or entry.get("path") != str(expected_path):
        raise SystemExit(f"허용되지 않은 복구 경로입니다: {entry.get('path') if isinstance(entry, dict) else entry}")
    existed = entry.get("existed")
    if not isinstance(existed, bool):
        raise SystemExit(f"스냅샷 existed 값이 올바르지 않습니다: {expected_path}")

    planned = {
        "index": index,
        "destination": str(expected_path),
        "existed": existed,
        "source": None,
        "kind": None,
        "sha256": None,
        "size_bytes": None,
        "stage": None,
        "backup": None,
        "state": "validated",
    }
    if not existed:
        absent_fields = ["archive_name", "kind"]
        if not legacy_limited:
            absent_fields.extend(["sha256", "size_bytes"])
        if any(entry.get(field) is not None for field in absent_fields):
            raise SystemExit(f"존재하지 않은 경로의 payload 정보가 올바르지 않습니다: {expected_path}")
        plan_entries.append(planned)
        continue

    archive_name = f"entry-{index:03d}"
    kind = entry.get("kind")
    if entry.get("archive_name") != archive_name or kind not in {"file", "directory", "symlink"}:
        raise SystemExit(f"스냅샷 payload 메타데이터가 올바르지 않습니다: {expected_path}")
    source = payload / archive_name
    if kind == "symlink" and not source.is_symlink():
        raise SystemExit(f"스냅샷 symlink payload가 없습니다: {expected_path}")
    if kind == "directory" and (source.is_symlink() or not source.is_dir()):
        raise SystemExit(f"스냅샷 directory payload가 없습니다: {expected_path}")
    if kind == "file" and (source.is_symlink() or not source.is_file()):
        raise SystemExit(f"스냅샷 file payload가 없습니다: {expected_path}")
    digest, size = payload_digest(source, kind)
    if not legacy_limited:
        if entry.get("sha256") != digest or entry.get("size_bytes") != size:
            raise SystemExit(f"스냅샷 payload checksum이 일치하지 않습니다: {expected_path}")
    planned.update({
        "source": str(source),
        "kind": kind,
        "sha256": digest if legacy_limited else entry.get("sha256"),
        "size_bytes": size if legacy_limited else entry.get("size_bytes"),
    })
    plan_entries.append(planned)

operation_id = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:12]
plan_root = state_root / "restore-plans"
plan_root.mkdir(parents=True, exist_ok=True)
os.chmod(plan_root, 0o700)
plan_path = plan_root / f"{operation_id}.json"
plan = {
    "plan_version": 1,
    "operation_id": operation_id,
    "created_at": datetime.now().astimezone().isoformat(),
    "updated_at": datetime.now().astimezone().isoformat(),
    "status": "validated",
    "snapshot_id": snapshot_dir.name,
    "snapshot_dir": str(snapshot_dir),
    "manifest_path": str(manifest_path),
    "manifest_sha256": manifest_sha256,
    "format_version": format_version,
    "legacy_integrity_limited": legacy_limited,
    "home": str(home),
    "codex_home": str(codex_home),
    "projects": project_values,
    "pre_restore_snapshot": None,
    "omx": data.get("omx", {}),
    "entries": plan_entries,
    "error": None,
    "rollback_errors": [],
}
with tempfile.NamedTemporaryFile(
    mode="w", encoding="utf-8", dir=str(plan_root), prefix=".plan-", delete=False
) as handle:
    temporary = Path(handle.name)
    json.dump(plan, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temporary, 0o600)
os.replace(temporary, plan_path)

project_output.write_text("".join(value + "\n" for value in project_values), encoding="utf-8")
plan_output.write_text(str(plan_path) + "\n", encoding="utf-8")
print("OK: 현재 환경, 복구 경로, manifest 및 payload 검증 완료")
print(f"복구 계획: {plan_path}")
PY

  restore_plan="$(<"$restore_plan_file")"
  rm -f "$restore_plan_file"

  log "현재 상태 안전 백업"
  snapshot_from_project_file "pre-restore" "$restore_project_file"
  local pre_restore_snapshot="$LAST_SNAPSHOT_ID"
  rm -f "$restore_project_file"

  RESTORE_PLAN="$restore_plan" PRE_RESTORE_SNAPSHOT="$pre_restore_snapshot" python3 <<'PY'
from pathlib import Path
from datetime import datetime
import json
import os
import tempfile

path = Path(os.environ["RESTORE_PLAN"])
data = json.loads(path.read_text(encoding="utf-8"))
data["pre_restore_snapshot"] = os.environ["PRE_RESTORE_SNAPSHOT"]
data["status"] = "ready"
data["updated_at"] = datetime.now().astimezone().isoformat()
with tempfile.NamedTemporaryFile(
    mode="w", encoding="utf-8", dir=str(path.parent), prefix=".plan-", delete=False
) as handle:
    temporary = Path(handle.name)
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY

  log "스냅샷 복구: $(basename "$snapshot_dir")"
  RESTORE_PLAN="$restore_plan" \
  TEST_FAIL_STAGE_INDEX="${OMX_GUARD_TEST_RESTORE_FAIL_STAGE_INDEX:-}" \
  TEST_INTERRUPT_INDEX="${OMX_GUARD_TEST_RESTORE_INTERRUPT_INDEX:-}" \
  python3 <<'PY'
from pathlib import Path
from datetime import datetime
import errno
import hashlib
import json
import os
import shutil
import tempfile

plan_path = Path(os.environ["RESTORE_PLAN"])
if plan_path.is_symlink() or not plan_path.is_file():
    raise SystemExit("복구 계획 파일이 없거나 안전하지 않습니다.")
plan = json.loads(plan_path.read_text(encoding="utf-8"))
operation_id = plan.get("operation_id")
if not isinstance(operation_id, str) or not operation_id:
    raise SystemExit("복구 계획 operation ID가 올바르지 않습니다.")

def exists(path):
    return path.exists() or path.is_symlink()

def persist():
    plan["updated_at"] = datetime.now().astimezone().isoformat()
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=str(plan_path.parent), prefix=".plan-", delete=False
    ) as handle:
        temporary = Path(handle.name)
        json.dump(plan, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, plan_path)

def payload_digest(path, kind):
    digest = hashlib.sha256()
    size = 0

    def add_record(record_kind, relative, value=b""):
        nonlocal size
        digest.update(record_kind.encode("ascii") + b"\0")
        digest.update(relative.encode("utf-8", "surrogateescape") + b"\0")
        digest.update(value)
        digest.update(b"\0")
        size += len(value)

    if kind == "symlink":
        add_record("symlink", ".", os.fsencode(os.readlink(path)))
    elif kind == "file":
        add_record("file", ".")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
                size += len(chunk)
    else:
        add_record("directory", ".")
        for root, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
            root_path = Path(root)
            names = sorted(dirnames + filenames)
            dirnames[:] = sorted(dirnames)
            for name in names:
                item = root_path / name
                relative = str(item.relative_to(path))
                if item.is_symlink():
                    add_record("symlink", relative, os.fsencode(os.readlink(item)))
                    if name in dirnames:
                        dirnames.remove(name)
                elif item.is_dir():
                    add_record("directory", relative)
                elif item.is_file():
                    add_record("file", relative)
                    with item.open("rb") as handle:
                        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                            digest.update(chunk)
                            size += len(chunk)
                else:
                    raise RuntimeError(f"지원하지 않는 파일 종류입니다: {item}")
    return digest.hexdigest(), size

def item_kind(path):
    if path.is_symlink():
        return "symlink"
    if path.is_dir():
        return "directory"
    if path.is_file():
        return "file"
    if not path.exists():
        return "absent"
    raise RuntimeError(f"지원하지 않는 목적지 파일 종류입니다: {path}")

def fingerprint(path):
    kind = item_kind(path)
    if kind == "absent":
        return {"kind": "absent", "sha256": None, "size_bytes": None}
    digest, size = payload_digest(path, kind)
    return {"kind": kind, "sha256": digest, "size_bytes": size}

def copy_item(source, destination, kind):
    if kind == "symlink":
        destination.symlink_to(os.readlink(source))
    elif kind == "directory":
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination, follow_symlinks=False)

def move_to_destination(stage, destination, kind, entry):
    if kind == "file":
        os.link(stage, destination, follow_symlinks=False)
        stage.unlink()
    elif kind == "symlink":
        destination.symlink_to(os.readlink(stage))
        stage.unlink()
    else:
        destination.mkdir(mode=0o700)
        entry["reservation_inode"] = destination.lstat().st_ino
        persist()
        os.rename(stage, destination)
        entry["reservation_inode"] = None

def validate_snapshot_again():
    manifest_path = Path(plan["manifest_path"])
    manifest_bytes = manifest_path.read_bytes()
    actual_manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()
    if actual_manifest_sha != plan.get("manifest_sha256"):
        raise RuntimeError("복구 실행 직전 manifest.json이 변경되었습니다.")
    if plan.get("format_version") == 2:
        checksum_path = Path(plan["snapshot_dir"]) / "manifest.sha256"
        if checksum_path.is_symlink() or checksum_path.read_text(encoding="ascii").strip() != actual_manifest_sha:
            raise RuntimeError("복구 실행 직전 manifest checksum이 변경되었습니다.")
    for entry in plan.get("entries", []):
        if not entry.get("existed"):
            continue
        source = Path(entry["source"])
        actual_kind = item_kind(source)
        if actual_kind != entry.get("kind"):
            raise RuntimeError(f"복구 실행 직전 payload 종류가 변경되었습니다: {source}")
        digest, size = payload_digest(source, actual_kind)
        if digest != entry.get("sha256") or size != entry.get("size_bytes"):
            raise RuntimeError(f"복구 실행 직전 payload가 변경되었습니다: {source}")

def rollback():
    errors = []
    for entry in reversed(plan.get("entries", [])):
        destination = Path(entry["destination"])
        backup = Path(entry["backup"]) if entry.get("backup") else None
        try:
            if backup is not None and exists(backup):
                if exists(destination):
                    conflict = destination.parent / (
                        f".{destination.name}.omx-guard-failed-{operation_id}-{entry['index']:03d}"
                    )
                    if exists(conflict):
                        raise RuntimeError(f"rollback 보존 경로가 이미 존재합니다: {conflict}")
                    os.rename(destination, conflict)
                    entry["failed_artifact"] = str(conflict)
                os.rename(backup, destination)
                entry["state"] = "rolled_back"
            elif entry.get("state") in {"installed", "applied-absent", "backup-moved"}:
                if exists(destination):
                    conflict = destination.parent / (
                        f".{destination.name}.omx-guard-failed-{operation_id}-{entry['index']:03d}"
                    )
                    if exists(conflict):
                        raise RuntimeError(f"rollback 보존 경로가 이미 존재합니다: {conflict}")
                    os.rename(destination, conflict)
                    entry["failed_artifact"] = str(conflict)
                entry["state"] = "rolled_back"
            reservation_inode = entry.get("reservation_inode")
            if reservation_inode is not None and destination.is_dir() and not destination.is_symlink():
                if destination.lstat().st_ino == reservation_inode:
                    destination.rmdir()
                    entry["reservation_inode"] = None
        except BaseException as error:
            errors.append(f"{destination}: {error}")
    plan["rollback_errors"] = errors
    return errors

try:
    validate_snapshot_again()
    plan["status"] = "staging"
    persist()

    fail_stage = os.environ.get("TEST_FAIL_STAGE_INDEX", "")
    interrupt_index = os.environ.get("TEST_INTERRUPT_INDEX", "")
    fail_stage_index = int(fail_stage) if fail_stage else None
    interrupt_at = int(interrupt_index) if interrupt_index else None

    for entry in plan["entries"]:
        destination = Path(entry["destination"])
        destination.parent.mkdir(parents=True, exist_ok=True)
        entry["initial_destination"] = fingerprint(destination)
        entry["backup"] = str(destination.parent / (
            f".{destination.name}.omx-guard-backup-{operation_id}-{entry['index']:03d}"
        ))
        if exists(Path(entry["backup"])):
            raise RuntimeError(f"복구 backup 경로가 이미 존재합니다: {entry['backup']}")
        if entry.get("existed"):
            stage = destination.parent / (
                f".{destination.name}.omx-guard-stage-{operation_id}-{entry['index']:03d}"
            )
            entry["stage"] = str(stage)
            if exists(stage):
                raise RuntimeError(f"복구 staging 경로가 이미 존재합니다: {stage}")
            if fail_stage_index == entry["index"]:
                raise OSError(errno.ENOSPC, "test-only staging ENOSPC injection", str(stage))
            copy_item(Path(entry["source"]), stage, entry["kind"])
            digest, size = payload_digest(stage, entry["kind"])
            if digest != entry["sha256"] or size != entry["size_bytes"]:
                raise RuntimeError(f"staged payload checksum이 일치하지 않습니다: {destination}")
        entry["state"] = "staged"
        persist()

    for entry in plan["entries"]:
        destination = Path(entry["destination"])
        if fingerprint(destination) != entry["initial_destination"]:
            raise RuntimeError(f"staging 중 복구 목적지가 변경되었습니다: {destination}")

    plan["status"] = "applying"
    persist()
    for entry in plan["entries"]:
        destination = Path(entry["destination"])
        backup = Path(entry["backup"])
        try:
            os.rename(destination, backup)
            entry["state"] = "backup-moved"
            persist()
            if fingerprint(backup) != entry["initial_destination"]:
                raise RuntimeError(f"교체 직전 복구 목적지가 변경되었습니다: {destination}")
        except FileNotFoundError:
            if entry["initial_destination"]["kind"] != "absent":
                raise RuntimeError(f"교체 직전 복구 목적지가 사라졌습니다: {destination}")

        if entry.get("existed"):
            move_to_destination(Path(entry["stage"]), destination, entry["kind"], entry)
            entry["state"] = "installed"
            print(f"restored: {destination}")
        else:
            entry["state"] = "applied-absent"
            print(f"restored-absent: {destination}")
        persist()
        if interrupt_at == entry["index"]:
            raise KeyboardInterrupt("test-only restore interruption injection")

    config_file = Path(plan["codex_home"]) / "config.toml"
    if config_file.is_file() and not config_file.is_symlink():
        try:
            import tomllib as toml_parser
        except ModuleNotFoundError:
            try:
                import tomli as toml_parser
            except ModuleNotFoundError:
                toml_parser = None
        if toml_parser is not None:
            with config_file.open("rb") as handle:
                toml_parser.load(handle)

    plan["status"] = "committing"
    persist()
    for entry in plan["entries"]:
        backup = Path(entry["backup"])
        if backup.is_symlink() or backup.is_file():
            backup.unlink()
        elif backup.is_dir():
            shutil.rmtree(backup)
        stage_value = entry.get("stage")
        if stage_value:
            stage = Path(stage_value)
            if stage.is_symlink() or stage.is_file():
                stage.unlink()
            elif stage.is_dir():
                shutil.rmtree(stage)
        entry["state"] = "committed"
    plan["status"] = "completed"
    persist()
except BaseException as error:
    plan["error"] = f"{type(error).__name__}: {error}"
    rollback_errors = rollback()
    plan["status"] = "rollback-failed" if rollback_errors else "rolled-back"
    persist()
    print(f"ERROR: 복구가 실패했습니다: {error}", file=os.sys.stderr)
    print(f"ERROR: 복구 계획을 보존했습니다: {plan_path}", file=os.sys.stderr)
    print(
        f"ERROR: pre-restore 스냅샷: {plan.get('pre_restore_snapshot')}",
        file=os.sys.stderr,
    )
    if rollback_errors:
        for rollback_error in rollback_errors:
            print(f"ERROR: rollback 실패: {rollback_error}", file=os.sys.stderr)
    raise SystemExit(1)
PY

  remove_npm_installations "" "$restore_plan"

  validate_toml "$CODEX_HOME/config.toml"

  ok "복구 완료 (계획 기록: $restore_plan, pre-restore: $pre_restore_snapshot)"

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
