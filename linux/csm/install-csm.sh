#!/usr/bin/env bash

set -u

PROGRAM_NAME="${0##*/}"
MARKER_BEGIN='# >>> script-store csm >>>'
MARKER_END='# <<< script-store csm <<<'
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
TRANSACTION_ACTIVE=0
TRANSACTION_BACKUP=
TRANSACTION_RC_EXISTED=0
TRANSACTION_CREATED_BIN_DIR=0
TRANSACTION_CREATED_LINK=0
TRANSACTION_REMOVED_LINK=0

usage() {
  cat <<'EOF'
Usage: install-csm.sh [options]

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
  CSM_EXPECTED_MARKER_LINE="$PATH_LINE" awk \
    -v marker_begin="$MARKER_BEGIN" \
    -v marker_end="$MARKER_END" '
    BEGIN {
      expected_line = ENVIRON["CSM_EXPECTED_MARKER_LINE"]
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
      if (inside && (content_lines != 1 || content != expected_line)) modified = 1
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

preflight_rc_file() {
  local state

  if { [ -e "$RC_FILE" ] || [ -L "$RC_FILE" ]; } && [ ! -f "$RC_FILE" ]; then
    die "rc file is not a regular file: $RC_FILE"
  fi

  marker_state "$RC_FILE"
  state=$?
  case "$state" in
    0|1) return 0 ;;
    2) die "found a malformed or duplicate csm marker block in $RC_FILE; remove or repair it manually" ;;
    3) die "found a modified csm marker block in $RC_FILE; leaving it unchanged for manual review" ;;
  esac
}

rc_has_local_bin() {
  [ -f "$RC_FILE" ] || return 1
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, ".local/bin") { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$RC_FILE"
}

path_has_local_bin() {
  case ":${PATH:-}:" in
    *":$BIN_DIR:"*|*":$BIN_DIR/:"*) return 0 ;;
    *) return 1 ;;
  esac
}

append_marker_block() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would add the managed PATH block to %s\n' "$RC_FILE"
    return 0
  fi

  if [ ! -e "$RC_FILE" ]; then
    : > "$RC_FILE" || die "could not create rc file: $RC_FILE"
  elif [ ! -f "$RC_FILE" ]; then
    die "rc file is not a regular file: $RC_FILE"
  fi

  if [ -s "$RC_FILE" ]; then
    printf '\n' >> "$RC_FILE" || die "could not update rc file: $RC_FILE"
  fi
  printf '%s\n%s\n%s\n' "$MARKER_BEGIN" "$PATH_LINE" "$MARKER_END" >> "$RC_FILE" || \
    die "could not update rc file: $RC_FILE"
  printf 'Added the managed PATH block to %s\n' "$RC_FILE"
}

remove_marker_block() {
  local state temp_file

  marker_state "$RC_FILE"
  state=$?
  case "$state" in
    1) return 0 ;;
    2) die "found a malformed or duplicate csm marker block in $RC_FILE; remove or repair it manually" ;;
    3) die "found a modified csm marker block in $RC_FILE; leaving it unchanged for manual review" ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would remove the managed PATH block from %s\n' "$RC_FILE"
    return 0
  fi

  temp_file="$(mktemp "${TMPDIR:-/tmp}/install-csm.XXXXXX")" || \
    die 'could not create a temporary file'
  if ! awk -v marker_begin="$MARKER_BEGIN" -v marker_end="$MARKER_END" '
    $0 == marker_begin { inside = 1; next }
    $0 == marker_end { inside = 0; next }
    !inside { print }
  ' "$RC_FILE" > "$temp_file"; then
    rm -f "$temp_file"
    die "could not prepare updated rc file: $RC_FILE"
  fi
  if ! cp "$temp_file" "$RC_FILE"; then
    rm -f "$temp_file"
    die "could not update rc file: $RC_FILE"
  fi
  rm -f "$temp_file"
  printf 'Removed the managed PATH block from %s\n' "$RC_FILE"
}

restore_managed_link() {
  if [ -L "$DESTINATION" ] && [ "$(readlink "$DESTINATION")" = "$SOURCE" ]; then
    return 0
  fi
  if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    printf '%s: rollback could not restore the managed link because the path is occupied: %s\n' \
      "$PROGRAM_NAME" "$DESTINATION" >&2
    return 1
  fi
  if ! ln -s "$SOURCE" "$DESTINATION"; then
    printf '%s: rollback could not restore the managed link: %s\n' "$PROGRAM_NAME" "$DESTINATION" >&2
    return 1
  fi
}

rollback_transaction() {
  local rollback_failed=0

  if [ "$TRANSACTION_RC_EXISTED" -eq 1 ]; then
    if ! cmp -s "$TRANSACTION_BACKUP" "$RC_FILE" && ! cp "$TRANSACTION_BACKUP" "$RC_FILE"; then
      printf '%s: rollback could not restore rc file: %s\n' "$PROGRAM_NAME" "$RC_FILE" >&2
      rollback_failed=1
    fi
  elif [ -e "$RC_FILE" ] || [ -L "$RC_FILE" ]; then
    if [ -f "$RC_FILE" ]; then
      rm -f "$RC_FILE" || rollback_failed=1
    else
      rollback_failed=1
    fi
  fi

  if [ "$TRANSACTION_CREATED_LINK" -eq 1 ]; then
    if [ -L "$DESTINATION" ] && [ "$(readlink "$DESTINATION")" = "$SOURCE" ]; then
      rm "$DESTINATION" || rollback_failed=1
    elif [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
      rollback_failed=1
    fi
  fi
  if [ "$TRANSACTION_REMOVED_LINK" -eq 1 ]; then
    restore_managed_link || rollback_failed=1
  fi
  if [ "$TRANSACTION_CREATED_BIN_DIR" -eq 1 ] && [ -d "$BIN_DIR" ]; then
    rmdir "$BIN_DIR" 2>/dev/null || true
  fi

  if [ "$rollback_failed" -eq 0 ]; then
    printf 'Rolled back the failed csm operation.\n' >&2
  else
    printf '%s: rollback was incomplete; inspect the paths reported above\n' "$PROGRAM_NAME" >&2
  fi
}

transaction_exit() {
  local status=$?

  trap - EXIT
  if [ "$TRANSACTION_ACTIVE" -eq 1 ] && [ "$status" -ne 0 ]; then
    rollback_transaction
  fi
  if [ -n "$TRANSACTION_BACKUP" ]; then
    rm -f "$TRANSACTION_BACKUP" || true
  fi
  exit "$status"
}

begin_transaction() {
  TRANSACTION_BACKUP="$(mktemp "${TMPDIR:-/tmp}/install-csm.rollback.XXXXXX")" || \
    die 'could not create a rollback file'
  if [ -f "$RC_FILE" ]; then
    cp "$RC_FILE" "$TRANSACTION_BACKUP" || die "could not snapshot rc file: $RC_FILE"
    TRANSACTION_RC_EXISTED=1
  fi
  TRANSACTION_ACTIVE=1
  trap transaction_exit EXIT
}

commit_transaction() {
  if [ -n "$TRANSACTION_BACKUP" ]; then
    rm -f "$TRANSACTION_BACKUP" || die 'could not remove the rollback file'
  fi
  TRANSACTION_BACKUP=
  TRANSACTION_ACTIVE=0
  trap - EXIT
}

remove_managed_link() {
  if [ -L "$DESTINATION" ] && [ "$(readlink "$DESTINATION")" = "$SOURCE" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'Would remove managed link %s\n' "$DESTINATION"
    else
      rm "$DESTINATION" || die "could not remove managed link: $DESTINATION"
      TRANSACTION_REMOVED_LINK=1
      printf 'Removed managed link %s\n' "$DESTINATION"
    fi
  elif [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    printf 'Left non-managed path unchanged: %s\n' "$DESTINATION" >&2
  else
    printf 'Managed link is already absent: %s\n' "$DESTINATION"
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
    *) die "unknown option: $1" ;;
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
  zsh|bash) SELECTED_SHELL="$SHELL_MODE" ;;
  *) die "unsupported shell: $SHELL_MODE (expected auto, zsh, or bash)" ;;
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
SOURCE="$SCRIPT_DIR/bin/csm"
BIN_DIR="$HOME/.local/bin"
DESTINATION="$BIN_DIR/csm"

[ -f "$SOURCE" ] || die "csm executable not found: $SOURCE"

preflight_rc_file

if [ "$UNINSTALL" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    begin_transaction
  fi
  remove_marker_block
  remove_managed_link
  if [ "$DRY_RUN" -eq 0 ]; then
    commit_transaction
  fi
  printf 'Uninstall complete. Existing PATH settings outside the managed block were not changed.\n'
  exit 0
fi

if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
  if [ ! -L "$DESTINATION" ] || [ "$(readlink "$DESTINATION")" != "$SOURCE" ]; then
    die "refusing to overwrite $DESTINATION; move or remove it, then run $PROGRAM_NAME again"
  fi
fi

if [ "$DRY_RUN" -eq 0 ]; then
  begin_transaction
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
  if [ ! -e "$BIN_DIR" ] && [ ! -L "$BIN_DIR" ]; then
    TRANSACTION_CREATED_BIN_DIR=1
  fi
  mkdir -p "$BIN_DIR" || die "could not create directory: $BIN_DIR"
  chmod +x "$SOURCE" || die "could not make csm executable: $SOURCE"
  if [ -L "$DESTINATION" ]; then
    printf 'Managed link is already correct: %s -> %s\n' "$DESTINATION" "$SOURCE"
  else
    ln -s "$SOURCE" "$DESTINATION" || die "could not create link: $DESTINATION"
    TRANSACTION_CREATED_LINK=1
    printf 'Created link %s -> %s\n' "$DESTINATION" "$SOURCE"
  fi
fi

marker_state "$RC_FILE"
marker_status=$?
case "$marker_status" in
  0) printf 'Managed PATH block is already present in %s\n' "$RC_FILE" ;;
  2) die "found a malformed or duplicate csm marker block in $RC_FILE; remove or repair it manually" ;;
  3) die "found a modified csm marker block in $RC_FILE; leaving it unchanged for manual review" ;;
  *)
    if path_has_local_bin; then
      printf '%s is already present in the current PATH; no rc change needed.\n' "$BIN_DIR"
    elif rc_has_local_bin; then
      printf '%s already configures .local/bin; no rc change needed.\n' "$RC_FILE"
    else
      append_marker_block
    fi
    ;;
esac

if [ "$DRY_RUN" -eq 0 ]; then
  commit_transaction
fi

printf '\nInstallation complete. This installer cannot modify the parent shell environment.\n'
printf 'Run the following command, or open a new terminal:\n'
printf '  source "%s"\n' "$RC_FILE"
