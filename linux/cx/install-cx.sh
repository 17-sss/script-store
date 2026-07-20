#!/usr/bin/env bash

set -u

PROGRAM_NAME="${0##*/}"
MARKER_BEGIN='# >>> script-store cx >>>'
MARKER_END='# <<< script-store cx <<<'
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

usage() {
  cat <<'EOF'
Usage: install-cx.sh [options]

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

  [ -f "$rc_file" ] || return 1
  awk -v marker_begin="$MARKER_BEGIN" -v marker_end="$MARKER_END" '
    BEGIN { inside = 0; seen = 0; malformed = 0 }
    $0 == marker_begin {
      if (inside) malformed = 1
      inside = 1
      seen = 1
      next
    }
    $0 == marker_end {
      if (!inside) malformed = 1
      inside = 0
      next
    }
    END {
      if (inside || malformed) exit 2
      if (seen) exit 0
      exit 1
    }
  ' "$rc_file"
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
  local state temp_file

  marker_state "$rc_file"
  state=$?
  case "$state" in
    1) return 0 ;;
    2) die "found a malformed cx marker block in $rc_file; remove or repair it manually" ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would remove the managed PATH block from %s\n' "$rc_file"
    return 0
  fi

  temp_file="$(mktemp "${TMPDIR:-/tmp}/install-cx.XXXXXX")" || die 'could not create a temporary file'
  if ! awk -v marker_begin="$MARKER_BEGIN" -v marker_end="$MARKER_END" '
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
  printf 'Removed the managed PATH block from %s\n' "$rc_file"
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
SOURCE="$SCRIPT_DIR/bin/cx"
BIN_DIR="$HOME/.local/bin"
DESTINATION="$BIN_DIR/cx"

[ -f "$SOURCE" ] || die "cx executable not found: $SOURCE"

if [ "$UNINSTALL" -eq 1 ]; then
  remove_marker_blocks "$RC_FILE"

  if [ -L "$DESTINATION" ] && [ "$(readlink "$DESTINATION")" = "$SOURCE" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'Would remove managed link %s\n' "$DESTINATION"
    else
      rm "$DESTINATION" || die "could not remove managed link: $DESTINATION"
      printf 'Removed managed link %s\n' "$DESTINATION"
    fi
  elif [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    printf 'Left non-managed path unchanged: %s\n' "$DESTINATION" >&2
  else
    printf 'Managed cx link is already absent: %s\n' "$DESTINATION"
  fi

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
  chmod +x "$SOURCE" || die "could not make cx executable: $SOURCE"
  if [ -L "$DESTINATION" ]; then
    printf 'Managed link is already correct: %s -> %s\n' "$DESTINATION" "$SOURCE"
  else
    ln -s "$SOURCE" "$DESTINATION" || die "could not create link: $DESTINATION"
    printf 'Created link %s -> %s\n' "$DESTINATION" "$SOURCE"
  fi
fi

marker_state "$RC_FILE"
marker_status=$?
case "$marker_status" in
  0)
    printf 'Managed PATH block is already present in %s\n' "$RC_FILE"
    ;;
  2)
    die "found a malformed cx marker block in $RC_FILE; remove or repair it manually"
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

printf '\nInstallation complete. This installer cannot modify the parent shell environment.\n'
printf 'Run the following command, or open a new terminal:\n'
printf '  source "%s"\n' "$RC_FILE"
