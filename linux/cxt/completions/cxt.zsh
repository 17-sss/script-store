#compdef cxt

# Zsh completion for cxt.

_cxt_session_names() {
  local session suffix

  command tmux list-sessions -F '#{session_name}' 2>/dev/null |
    while IFS= read -r session; do
      case "$session" in
        codex-*) ;;
        *) continue ;;
      esac

      suffix="${session#codex-}"
      case "$suffix" in
        ''|*[!A-Za-z0-9_-]*) continue ;;
      esac

      print -r -- "$session"
    done
}

_cxt_complete_sessions() {
  local -a sessions
  local session_output

  session_output="$(_cxt_session_names)"
  [[ -n "$session_output" ]] || return 1
  sessions=("${(@f)session_output}")
  compadd -- "${sessions[@]}"
}

_cxt() {
  local current_word previous_word
  local -a cxt_options
  local index

  current_word="${words[CURRENT]}"
  previous_word=
  (( CURRENT > 1 )) && previous_word="${words[CURRENT - 1]}"

  for (( index = 2; index < CURRENT; index++ )); do
    [[ "${words[index]}" == -- ]] && return 0
  done

  case "$previous_word" in
    --attach|--at|--kill-session|--ks)
      _cxt_complete_sessions
      return
      ;;
  esac

  case "$current_word" in
    --attach=*|--at=*|--kill-session=*|--ks=*)
      compset -P 1 '*='
      _cxt_complete_sessions
      return
      ;;
  esac

  cxt_options=(
    '--sol:use model gpt-5.6-sol'
    '--terra:use model gpt-5.6-terra'
    '--luna:use model gpt-5.6-luna'
    '--gpt55:use model gpt-5.5'
    '--gpt54:use model gpt-5.4'
    '--mini:use model gpt-5.4-mini'
    '--spark:use model gpt-5.3-codex-spark'
    '--low:use low reasoning effort'
    '--medium:use medium reasoning effort'
    '--high:use high reasoning effort'
    '--xhigh:use xhigh reasoning effort'
    '--max:use max reasoning effort'
    '--ultra:use ultra reasoning effort'
    '--safe:use read-only sandbox and untrusted approvals'
    '--auto:use workspace-write sandbox and on-request approvals'
    '--full-auto:use workspace-write sandbox without approval prompts'
    '--madmax:run without sandbox or approval prompts'
    '--attach:attach or switch to a cxt tmux session'
    '--at:attach or switch to a cxt tmux session'
    '--kill-session:kill one cxt tmux session'
    '--ks:kill one cxt tmux session'
    '--kill-all:kill all cxt tmux sessions'
    '--ka:kill all cxt tmux sessions'
    '--cxt-help:show cxt help'
    '--:stop interpreting cxt shortcuts'
  )
  _describe 'cxt option' cxt_options
}

if (( $+functions[compdef] )); then
  compdef _cxt cxt
fi
