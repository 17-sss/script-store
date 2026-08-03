# Bash completion for cxt.

_cxt_session_names() {
  local session suffix

  while IFS= read -r session; do
    case "$session" in
      codex-*) ;;
      *) continue ;;
    esac

    suffix="${session#codex-}"
    case "$suffix" in
      ''|*[!A-Za-z0-9_-]*) continue ;;
    esac

    printf '%s\n' "$session"
  done < <(command tmux list-sessions -F '#{session_name}' 2>/dev/null)
}

_cxt_complete() {
  local current previous option value candidate index

  COMPREPLY=()
  current="${COMP_WORDS[COMP_CWORD]}"
  previous=
  if [ "$COMP_CWORD" -gt 0 ]; then
    previous="${COMP_WORDS[COMP_CWORD - 1]}"
  fi

  index=1
  while [ "$index" -lt "$COMP_CWORD" ]; do
    [ "${COMP_WORDS[$index]}" = -- ] && return 0
    index=$((index + 1))
  done

  case "$previous" in
    --attach|--at|--kill-session|--ks)
      while IFS= read -r candidate; do
        [ -n "$candidate" ] && COMPREPLY+=("$candidate")
      done < <(compgen -W "$(_cxt_session_names)" -- "$current")
      return 0
      ;;
  esac

  case "$current" in
    --attach=*|--at=*|--kill-session=*|--ks=*)
      option="${current%%=*}"
      value="${current#*=}"
      while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        COMPREPLY+=("$option=$candidate")
      done < <(compgen -W "$(_cxt_session_names)" -- "$value")
      return 0
      ;;
  esac

  case "$current" in
    -*)
      while IFS= read -r candidate; do
        [ -n "$candidate" ] && COMPREPLY+=("$candidate")
      done < <(compgen -W '
        --sol --terra --luna --gpt55 --gpt54 --mini --spark
        --low --medium --high --xhigh --max --ultra
        --safe --auto --full-auto --madmax
        --attach --at --kill-session --ks --kill-all --ka
        --cxt-help --
      ' -- "$current")
      ;;
  esac
}

complete -F _cxt_complete cxt
