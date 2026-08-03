#!/usr/bin/env bash

set -u

PROGRAM_NAME="${0##*/}"
MARKER_BEGIN='# >>> script-store cxt >>>'
MARKER_END='# <<< script-store cxt <<<'
LEGACY_MARKER_BEGIN='# >>> script-store cx >>>'
LEGACY_MARKER_END='# <<< script-store cx <<<'
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

usage() {
  cat <<'EOF'
Usage: install-cxt.sh [options]

Options:
  --shell auto|zsh|bash  Select the shell rc file (default: auto)
  --rc-file PATH         Override the selected shell rc file
  --dry-run              Show changes without modifying files
  --uninstall            Remove only items managed by this installer
  -h, --help             Show this help
EOF
}

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

resolve_script_path() {
  local source_path source_dir link_target

  source_path="${BASH_SOURCE[0]}"
  while [ -L "$source_path" ]; do
    source_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)" || return 1
    link_target="$(readlink "$source_path")" || return 1
    case "$link_target" in
      /*) source_path="$link_target" ;;
      *) source_path="$source_dir/$link_target" ;;
    esac
  done

  source_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)" || return 1
  printf '%s/%s\n' "$source_dir" "$(basename "$source_path")"
}

marker_state() {
  local rc_file="$1"
  local marker_begin="${2:-$MARKER_BEGIN}"
  local marker_end="${3:-$MARKER_END}"

  [ -f "$rc_file" ] || return 1
  awk \
    -v marker_begin="$marker_begin" \
    -v marker_end="$marker_end" \
    -v path_line="$PATH_LINE" '
    BEGIN {
      inside = 0
      seen = 0
      malformed = 0
      modified = 0
      content_lines = 0
    }
    $0 == marker_begin {
      if (inside || seen) malformed = 1
      inside = 1
      seen = 1
      content_lines = 0
      next
    }
    $0 == marker_end {
      if (!inside) malformed = 1
      if (inside && (content_lines != 1 || content != path_line)) modified = 1
      inside = 0
      next
    }
    inside {
      content_lines++
      if (content_lines == 1) content = $0
      else modified = 1
      next
    }
    END {
      if (inside || malformed) exit 2
      if (!seen) exit 1
      if (modified) exit 3
      exit 0
    }
  ' "$rc_file"
}

preflight_marker_block() {
  local rc_file="$1"
  local marker_begin="$2"
  local marker_end="$3"
  local marker_name="$4"
  local state

  marker_state "$rc_file" "$marker_begin" "$marker_end"
  state=$?
  case "$state" in
    0|1) return 0 ;;
    2) die "found a malformed or duplicate $marker_name marker block in $rc_file; remove or repair it manually" ;;
    3) die "found a modified $marker_name marker block in $rc_file; leaving it unchanged for manual review" ;;
  esac
}

preflight_marker_blocks() {
  local rc_file="$1"

  if { [ -e "$rc_file" ] || [ -L "$rc_file" ]; } && [ ! -f "$rc_file" ]; then
    die "rc file is not a regular file: $rc_file"
  fi

  preflight_marker_block "$rc_file" "$MARKER_BEGIN" "$MARKER_END" cxt
  preflight_marker_block "$rc_file" "$LEGACY_MARKER_BEGIN" "$LEGACY_MARKER_END" cx
}

rc_has_local_bin() {
  local rc_file="$1"

  [ -f "$rc_file" ] || return 1
  awk '
    /^[[:space:]]*#/ { next }
    index($0, ".local/bin") && $0 ~ /PATH/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$rc_file"
}

path_has_local_bin() {
  case ":${PATH:-}:" in
    *":$BIN_DIR:"*|*":$BIN_DIR/:"*) return 0 ;;
    *) return 1 ;;
  esac
}

append_marker_block() {
  local rc_file="$1"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would add the managed PATH block to %s\n' "$rc_file"
    return 0
  fi

  if [ ! -e "$rc_file" ]; then
    : > "$rc_file" || die "could not create rc file: $rc_file"
  elif [ ! -f "$rc_file" ]; then
    die "rc file is not a regular file: $rc_file"
  fi

  if [ -s "$rc_file" ]; then
    printf '\n' >> "$rc_file" || die "could not update rc file: $rc_file"
  fi
  printf '%s\n%s\n%s\n' \
    "$MARKER_BEGIN" \
    "$PATH_LINE" \
    "$MARKER_END" >> "$rc_file" || die "could not update rc file: $rc_file"
  printf 'Added the managed PATH block to %s\n' "$rc_file"
}

remove_marker_blocks() {
  local rc_file="$1"
  local marker_begin="${2:-$MARKER_BEGIN}"
  local marker_end="${3:-$MARKER_END}"
  local marker_name="${4:-cxt}"
  local state temp_file

  marker_state "$rc_file" "$marker_begin" "$marker_end"
  state=$?
  case "$state" in
    1) return 0 ;;
    2) die "found a malformed or duplicate $marker_name marker block in $rc_file; remove or repair it manually" ;;
    3) die "found a modified $marker_name marker block in $rc_file; leaving it unchanged for manual review" ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would remove the managed %s PATH block from %s\n' "$marker_name" "$rc_file"
    return 0
  fi

  temp_file="$(mktemp "${TMPDIR:-/tmp}/install-cxt.XXXXXX")" || die 'could not create a temporary file'
  if ! awk -v marker_begin="$marker_begin" -v marker_end="$marker_end" '
    $0 == marker_begin { inside = 1; next }
    $0 == marker_end { inside = 0; next }
    !inside { print }
  ' "$rc_file" > "$temp_file"; then
    rm -f "$temp_file"
    die "could not prepare updated rc file: $rc_file"
  fi

  if ! cp "$temp_file" "$rc_file"; then
    rm -f "$temp_file"
    die "could not update rc file: $rc_file"
  fi
  rm -f "$temp_file"
  printf 'Removed the managed %s PATH block from %s\n' "$marker_name" "$rc_file"
}

migrate_legacy_marker_block() {
  local rc_file="$1"
  local legacy_state current_state temp_file

  marker_state "$rc_file" "$LEGACY_MARKER_BEGIN" "$LEGACY_MARKER_END"
  legacy_state=$?
  case "$legacy_state" in
    1) return 0 ;;
    2) die "found a malformed or duplicate cx marker block in $rc_file; remove or repair it manually" ;;
    3) die "found a modified cx marker block in $rc_file; leaving it unchanged for manual review" ;;
  esac

  marker_state "$rc_file"
  current_state=$?
  case "$current_state" in
    0)
      remove_marker_blocks "$rc_file" "$LEGACY_MARKER_BEGIN" "$LEGACY_MARKER_END" cx
      return 0
      ;;
    2)
      die "found a malformed or duplicate cxt marker block in $rc_file; remove or repair it manually"
      ;;
    3)
      die "found a modified cxt marker block in $rc_file; leaving it unchanged for manual review"
      ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would rename the managed cx PATH block to cxt in %s\n' "$rc_file"
    return 0
  fi

  temp_file="$(mktemp "${TMPDIR:-/tmp}/install-cxt.XXXXXX")" || die 'could not create a temporary file'
  if ! awk \
    -v legacy_begin="$LEGACY_MARKER_BEGIN" \
    -v legacy_end="$LEGACY_MARKER_END" \
    -v marker_begin="$MARKER_BEGIN" \
    -v marker_end="$MARKER_END" '
      $0 == legacy_begin { print marker_begin; next }
      $0 == legacy_end { print marker_end; next }
      { print }
    ' "$rc_file" > "$temp_file"; then
    rm -f "$temp_file"
    die "could not prepare migrated rc file: $rc_file"
  fi

  if ! cp "$temp_file" "$rc_file"; then
    rm -f "$temp_file"
    die "could not migrate rc file: $rc_file"
  fi
  rm -f "$temp_file"
  printf 'Renamed the managed cx PATH block to cxt in %s\n' "$rc_file"
}

remove_managed_link() {
  local destination="$1"
  local source="$2"
  local link_name="$3"

  if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'Would remove managed %s link %s\n' "$link_name" "$destination"
    else
      rm "$destination" || die "could not remove managed link: $destination"
      printf 'Removed managed %s link %s\n' "$link_name" "$destination"
    fi
  elif [ -e "$destination" ] || [ -L "$destination" ]; then
    printf 'Left non-managed path unchanged: %s\n' "$destination" >&2
  else
    printf 'Managed %s link is already absent: %s\n' "$link_name" "$destination"
  fi
}

migrate_legacy_link() {
  if [ -L "$LEGACY_DESTINATION" ] && [ "$(readlink "$LEGACY_DESTINATION")" = "$LEGACY_SOURCE" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'Would remove managed legacy cx link %s\n' "$LEGACY_DESTINATION"
    else
      rm "$LEGACY_DESTINATION" || die "could not remove legacy cx link: $LEGACY_DESTINATION"
      printf 'Removed managed legacy cx link %s\n' "$LEGACY_DESTINATION"
    fi
  elif [ -e "$LEGACY_DESTINATION" ] || [ -L "$LEGACY_DESTINATION" ]; then
    printf 'Left non-managed legacy cx path unchanged: %s\n' "$LEGACY_DESTINATION" >&2
  fi
}

SHELL_MODE=auto
RC_FILE_OVERRIDE=
DRY_RUN=0
UNINSTALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shell)
      [ "$#" -ge 2 ] || die '--shell requires auto, zsh, or bash'
      SHELL_MODE="$2"
      shift 2
      ;;
    --rc-file)
      [ "$#" -ge 2 ] || die '--rc-file requires a path'
      RC_FILE_OVERRIDE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

case "$SHELL_MODE" in
  auto)
    case "${SHELL:-}" in
      */zsh|zsh) SELECTED_SHELL=zsh ;;
      */bash|bash) SELECTED_SHELL=bash ;;
      *) die 'could not detect bash or zsh from $SHELL; use --shell zsh or --shell bash' ;;
    esac
    ;;
  zsh|bash)
    SELECTED_SHELL="$SHELL_MODE"
    ;;
  *)
    die "unsupported shell: $SHELL_MODE (expected auto, zsh, or bash)"
    ;;
esac

[ -n "${HOME:-}" ] || die 'HOME is not set'

if [ -n "$RC_FILE_OVERRIDE" ]; then
  RC_FILE="$RC_FILE_OVERRIDE"
elif [ "$SELECTED_SHELL" = zsh ]; then
  RC_FILE="$HOME/.zshrc"
else
  RC_FILE="$HOME/.bashrc"
fi

SCRIPT_PATH="$(resolve_script_path)" || die 'could not resolve the installer location'
SCRIPT_DIR="${SCRIPT_PATH%/*}"
SOURCE="$SCRIPT_DIR/bin/cxt"
BIN_DIR="$HOME/.local/bin"
DESTINATION="$BIN_DIR/cxt"
LEGACY_SOURCE="${SCRIPT_DIR%/*}/cx/bin/cx"
LEGACY_DESTINATION="$BIN_DIR/cx"

[ -f "$SOURCE" ] || die "cxt executable not found: $SOURCE"

# Validate every managed rc block before changing either the rc file or links.
preflight_marker_blocks "$RC_FILE"

if [ "$UNINSTALL" -eq 1 ]; then
  remove_marker_blocks "$RC_FILE" "$MARKER_BEGIN" "$MARKER_END" cxt
  remove_marker_blocks "$RC_FILE" "$LEGACY_MARKER_BEGIN" "$LEGACY_MARKER_END" cx
  remove_managed_link "$DESTINATION" "$SOURCE" cxt
  remove_managed_link "$LEGACY_DESTINATION" "$LEGACY_SOURCE" cx

  printf 'Uninstall complete. Existing PATH settings outside the managed block were not changed.\n'
  exit 0
fi

if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
  if [ ! -L "$DESTINATION" ] || [ "$(readlink "$DESTINATION")" != "$SOURCE" ]; then
    die "refusing to overwrite $DESTINATION; move or remove it, then run $PROGRAM_NAME again"
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  if [ ! -d "$BIN_DIR" ]; then
    printf 'Would create directory %s\n' "$BIN_DIR"
  fi
  if [ ! -x "$SOURCE" ]; then
    printf 'Would make executable %s\n' "$SOURCE"
  fi
  if [ -L "$DESTINATION" ]; then
    printf 'Managed link is already correct: %s -> %s\n' "$DESTINATION" "$SOURCE"
  else
    printf 'Would create link %s -> %s\n' "$DESTINATION" "$SOURCE"
  fi
else
  mkdir -p "$BIN_DIR" || die "could not create directory: $BIN_DIR"
  chmod +x "$SOURCE" || die "could not make cxt executable: $SOURCE"
  if [ -L "$DESTINATION" ]; then
    printf 'Managed link is already correct: %s -> %s\n' "$DESTINATION" "$SOURCE"
  else
    ln -s "$SOURCE" "$DESTINATION" || die "could not create link: $DESTINATION"
    printf 'Created link %s -> %s\n' "$DESTINATION" "$SOURCE"
  fi
fi

migrate_legacy_marker_block "$RC_FILE"

marker_state "$RC_FILE"
marker_status=$?
case "$marker_status" in
  0)
    printf 'Managed PATH block is already present in %s\n' "$RC_FILE"
    ;;
  2)
    die "found a malformed or duplicate cxt marker block in $RC_FILE; remove or repair it manually"
    ;;
  3)
    die "found a modified cxt marker block in $RC_FILE; leaving it unchanged for manual review"
    ;;
  *)
    if path_has_local_bin; then
      printf '%s is already present in the current PATH; no rc change needed.\n' "$BIN_DIR"
    elif rc_has_local_bin "$RC_FILE"; then
      printf '%s already configures .local/bin; no rc change needed.\n' "$RC_FILE"
    else
      append_marker_block "$RC_FILE"
    fi
    ;;
esac

# Keep the old managed launcher available until the new link and rc setup have
# both completed successfully.
migrate_legacy_link

printf '\nInstallation complete. This installer cannot modify the parent shell environment.\n'
printf 'Run the following command, or open a new terminal:\n'
printf '  source "%s"\n' "$RC_FILE"
