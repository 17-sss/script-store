#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CXT_DIR="${SCRIPT_DIR%/tests}"
CXT="$CXT_DIR/bin/cxt"
INSTALLER="$CXT_DIR/install-cxt.sh"
ZSH_COMPLETION="$CXT_DIR/completions/cxt.zsh"
BASH_COMPLETION="$CXT_DIR/completions/cxt.bash"
LEGACY_CX="${CXT_DIR%/*}/cx/bin/cx"
ORIGINAL_PATH="$PATH"
ZSH_BIN="$(command -v zsh || true)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cxt-test.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_file_lacks_line() {
  local file="$1"
  local unexpected="$2"
  ! grep -Fxq -- "$unexpected" "$file" || fail "$file contains unexpected line: $unexpected"
}

assert_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual

  actual="$(grep -Fc -- "$pattern" "$file" || true)"
  [ "$actual" = "$expected" ] || fail "expected $expected occurrences of '$pattern' in $file, got $actual"
}

read_nul_args() {
  local file="$1"
  CAPTURED_ARGS=()
  while IFS= read -r -d '' captured_arg; do
    CAPTURED_ARGS+=("$captured_arg")
  done < "$file"
}

assert_args() {
  local file="$1"
  shift
  local index=0

  read_nul_args "$file"
  [ "${#CAPTURED_ARGS[@]}" -eq "$#" ] || fail "argument count mismatch for $file"
  for expected_arg in "$@"; do
    [ "${CAPTURED_ARGS[$index]}" = "$expected_arg" ] || \
      fail "argument $index mismatch: expected '$expected_arg', got '${CAPTURED_ARGS[$index]}'"
    index=$((index + 1))
  done
}

make_minimal_bin() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  ln -s "$(command -v bash)" "$bin_dir/bash"
  cat > "$bin_dir/date" <<'EOF'
#!/usr/bin/env bash
printf '000000\n'
EOF
  chmod +x "$bin_dir/date"
}

make_codex_mock() {
  local bin_dir="$1"
  cat > "$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
: > "$CXT_CODEX_LOG"
for mock_arg in "$@"; do
  printf '%s\0' "$mock_arg" >> "$CXT_CODEX_LOG"
done
exit "${CXT_CODEX_EXIT_CODE:-0}"
EOF
  chmod +x "$bin_dir/codex"
}

make_tmux_mock() {
  local bin_dir="$1"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
call_number=0
if [ -r "$CXT_TMUX_COUNT" ]; then
  IFS= read -r call_number < "$CXT_TMUX_COUNT"
fi
call_number=$((call_number + 1))
printf '%s\n' "$call_number" > "$CXT_TMUX_COUNT"
: > "$CXT_TMUX_LOG.$call_number"
for mock_arg in "$@"; do
  printf '%s\0' "$mock_arg" >> "$CXT_TMUX_LOG.$call_number"
done

case "${1:-}" in
  list-sessions)
    if [ -r "${CXT_TMUX_SESSIONS:-}" ]; then
      while IFS= read -r mock_session || [ -n "$mock_session" ]; do
        printf '%s\n' "$mock_session"
      done < "$CXT_TMUX_SESSIONS"
    fi
    ;;
  display-message)
    printf '%s\n' "${CXT_TMUX_CURRENT_SESSION:-}"
    ;;
esac

exit 0
EOF
  chmod +x "$bin_dir/tmux"
}

run_direct_case() {
  local case_name="$1"
  shift
  local case_root="$TMP_ROOT/direct-$case_name"
  local mock_bin="$case_root/bin"

  mkdir -p "$case_root/project"
  make_minimal_bin "$mock_bin"
  make_codex_mock "$mock_bin"
  (
    cd "$case_root/project"
    PATH="$mock_bin" CXT_CODEX_LOG="$case_root/codex.args" "$CXT" "$@"
  ) 2> "$case_root/stderr"
  assert_file_contains "$case_root/stderr" 'cxt: tmux not found; launching Codex directly'
  DIRECT_LOG="$case_root/codex.args"
}

assert_shortcut_conflict() {
  local category="$1"
  shift
  local case_root="$TMP_ROOT/conflict-$category"
  local conflict_status

  mkdir -p "$case_root/project"
  make_minimal_bin "$case_root/bin"
  make_codex_mock "$case_root/bin"

  set +e
  (
    cd "$case_root/project"
    PATH="$case_root/bin" CXT_CODEX_LOG="$case_root/codex.args" "$CXT" "$@"
  ) 2> "$case_root/stderr"
  conflict_status=$?
  set -e

  [ "$conflict_status" -eq 2 ] || fail "$category shortcut conflict returned $conflict_status instead of 2"
  assert_file_contains "$case_root/stderr" "cxt: $category shortcuts cannot be combined"
  [ ! -e "$case_root/codex.args" ] || fail "$category shortcut conflict launched Codex"
}

bash -n "$CXT"
bash -n "$INSTALLER"
bash -n "$BASH_COMPLETION"
bash -n "$0"
if [ -n "$ZSH_BIN" ]; then
  "$ZSH_BIN" -n "$ZSH_COMPLETION"
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s bash "$CXT" "$INSTALLER" "$BASH_COMPLETION"
else
  printf 'SKIP: ShellCheck is not installed\n'
fi

"$CXT" --cxt-help > "$TMP_ROOT/cxt-help"
assert_file_contains "$TMP_ROOT/cxt-help" 'Usage: cxt [CXT_OPTIONS] [CODEX_OPTIONS] [PROMPT|COMMAND ...]'
assert_file_contains "$TMP_ROOT/cxt-help" '--sol       --model gpt-5.6-sol'
assert_file_contains "$TMP_ROOT/cxt-help" '--safe       read-only + untrusted approvals'
assert_file_contains "$TMP_ROOT/cxt-help" '--attach, --at [SESSION]'
assert_file_contains "$TMP_ROOT/cxt-help" '--kill-session, --ks [SESSION]'
assert_file_contains "$TMP_ROOT/cxt-help" '--kill-all, --ka'

run_direct_case empty
assert_args "$DIRECT_LOG" --no-alt-screen

for effort in low medium high xhigh max ultra; do
  run_direct_case "reasoning-$effort" "--$effort"
  assert_args "$DIRECT_LOG" --no-alt-screen -c "model_reasoning_effort=\"$effort\""
done

run_direct_case model-sol --sol
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.6-sol

run_direct_case model-terra --terra
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.6-terra

run_direct_case model-luna --luna
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.6-luna

run_direct_case model-gpt55 --gpt55
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.5

run_direct_case model-gpt54 --gpt54
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.4

run_direct_case model-mini --mini
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.4-mini

run_direct_case model-spark --spark
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.3-codex-spark

run_direct_case permission-safe --safe
assert_args "$DIRECT_LOG" --no-alt-screen --sandbox read-only --ask-for-approval untrusted

run_direct_case permission-auto --auto
assert_args "$DIRECT_LOG" --no-alt-screen --sandbox workspace-write --ask-for-approval on-request

run_direct_case permission-full-auto --full-auto
assert_args "$DIRECT_LOG" --no-alt-screen --sandbox workspace-write --ask-for-approval never

run_direct_case madmax --madmax
assert_args "$DIRECT_LOG" --no-alt-screen --yolo

run_direct_case combined --xhigh --madmax
assert_args "$DIRECT_LOG" --no-alt-screen -c 'model_reasoning_effort="xhigh"' --yolo

run_direct_case all-shortcuts --sol --high --auto 'prompt with spaces'
assert_args "$DIRECT_LOG" \
  --no-alt-screen \
  --model gpt-5.6-sol \
  -c 'model_reasoning_effort="high"' \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  'prompt with spaces'

run_direct_case prompt --xhigh '현재 프로젝트의 테스트를 수정해줘'
assert_args "$DIRECT_LOG" --no-alt-screen -c 'model_reasoning_effort="xhigh"' '현재 프로젝트의 테스트를 수정해줘'

run_direct_case passthrough -- --sol --high --auto --madmax --at --ks --ka
assert_args "$DIRECT_LOG" --no-alt-screen -- --sol --high --auto --madmax --at --ks --ka

run_direct_case native --model gpt-5.6-sol --sandbox workspace-write --ask-for-approval on-request --image './reference image.png'
assert_args "$DIRECT_LOG" --no-alt-screen --model gpt-5.6-sol --sandbox workspace-write --ask-for-approval on-request --image './reference image.png'

run_direct_case subcommand resume --last
assert_args "$DIRECT_LOG" --no-alt-screen resume --last

run_direct_case review review
assert_args "$DIRECT_LOG" --no-alt-screen review

assert_shortcut_conflict model --sol --terra
assert_shortcut_conflict reasoning --low --high
assert_shortcut_conflict permission --safe --auto

# Calling the executable from zsh still dispatches through its Bash shebang.
if [ -n "$ZSH_BIN" ]; then
  zsh_case="$TMP_ROOT/zsh-call"
  mkdir -p "$zsh_case/project"
  make_minimal_bin "$zsh_case/bin"
  make_codex_mock "$zsh_case/bin"
  CXT_PATH="$CXT" MOCK_PATH="$zsh_case/bin" CXT_CODEX_LOG="$zsh_case/codex.args" \
    "$ZSH_BIN" -c 'cd "$1" && PATH="$MOCK_PATH" "$CXT_PATH" --madmax' zsh "$zsh_case/project" \
    2> "$zsh_case/stderr"
  assert_args "$zsh_case/codex.args" --no-alt-screen --yolo
fi

missing_root="$TMP_ROOT/missing-codex"
mkdir -p "$missing_root/project"
make_minimal_bin "$missing_root/bin"
set +e
(
  cd "$missing_root/project"
  PATH="$missing_root/bin" "$CXT"
) 2> "$missing_root/stderr"
missing_status=$?
set -e
[ "$missing_status" -eq 127 ] || fail "missing codex returned $missing_status instead of 127"
assert_file_contains "$missing_root/stderr" 'cxt: codex command not found'

# Session management tests use only the mock tmux state below. They do not
# inspect or mutate the tmux server that launched this test process.
session_root="$TMP_ROOT/session-management"
mkdir -p "$session_root/project"
make_minimal_bin "$session_root/bin"
make_tmux_mock "$session_root/bin"
printf '%s\n' \
  '400:work' \
  '100:codex-project-old' \
  '300:codex-project-new' > "$session_root/sessions"

(
  unset TMUX
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    "$CXT" --at
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" attach-session -t codex-project-new

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    "$CXT" --attach codex-project-old
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" switch-client -t codex-project-old

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  unset TMUX
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    "$CXT" --ks
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" kill-session -t codex-project-new

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    CXT_TMUX_CURRENT_SESSION=codex-project-old \
    "$CXT" --kill-session
)
assert_args "$session_root/tmux.args.1" display-message -p '#{session_name}'
assert_args "$session_root/tmux.args.2" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.3" kill-session -t codex-project-old

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    CXT_TMUX_CURRENT_SESSION=codex-project-old \
    "$CXT" --ka
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" display-message -p '#{session_name}'
assert_args "$session_root/tmux.args.3" kill-session -t codex-project-new
assert_args "$session_root/tmux.args.4" kill-session -t codex-project-old

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
set +e
(
  unset TMUX
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    "$CXT" --at work
) 2> "$session_root/non-cxt.stderr"
non_cxt_status=$?
set -e
[ "$non_cxt_status" -eq 2 ] || fail "non-cxt attach returned $non_cxt_status instead of 2"
assert_file_contains "$session_root/non-cxt.stderr" 'cxt: not a cxt tmux session: work'
[ ! -e "$session_root/tmux.count" ] || fail 'non-cxt attach called tmux'

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
printf '%s\n' '400:work' > "$session_root/no-cxt-sessions"
set +e
(
  unset TMUX
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/no-cxt-sessions" \
    "$CXT" --attach
) 2> "$session_root/no-cxt.stderr"
no_cxt_status=$?
set -e
[ "$no_cxt_status" -eq 1 ] || fail "empty cxt attach returned $no_cxt_status instead of 1"
assert_file_contains "$session_root/no-cxt.stderr" 'cxt: no cxt tmux sessions found'
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
set +e
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    "$CXT" --at --kill-all
) 2> "$session_root/action-conflict.stderr"
action_conflict_status=$?
set -e
[ "$action_conflict_status" -eq 2 ] || fail "session action conflict returned $action_conflict_status instead of 2"
assert_file_contains "$session_root/action-conflict.stderr" 'cxt: session management shortcuts cannot be combined'
[ ! -e "$session_root/tmux.count" ] || fail 'session action conflict called tmux'

set +e
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CXT_TMUX_COUNT="$session_root/tmux.count" \
    CXT_TMUX_LOG="$session_root/tmux.args" \
    CXT_TMUX_SESSIONS="$session_root/sessions" \
    "$CXT" --attach --safe
) 2> "$session_root/action-codex-conflict.stderr"
action_codex_status=$?
set -e
[ "$action_codex_status" -eq 2 ] || fail "session/Codex conflict returned $action_codex_status instead of 2"
assert_file_contains "$session_root/action-codex-conflict.stderr" 'cxt: session management options cannot be combined with Codex arguments'
[ ! -e "$session_root/tmux.count" ] || fail 'session/Codex conflict called tmux'

missing_tmux_root="$TMP_ROOT/missing-tmux-management"
mkdir -p "$missing_tmux_root/project"
make_minimal_bin "$missing_tmux_root/bin"
set +e
(
  cd "$missing_tmux_root/project"
  PATH="$missing_tmux_root/bin" "$CXT" --ka
) 2> "$missing_tmux_root/stderr"
missing_tmux_status=$?
set -e
[ "$missing_tmux_status" -eq 127 ] || fail "missing tmux management returned $missing_tmux_status instead of 127"
assert_file_contains "$missing_tmux_root/stderr" 'cxt: tmux command not found'

# Completion tests use a mock tmux server and expose only valid cxt session
# names. General tmux sessions and malformed codex-* names must stay hidden.
completion_root="$TMP_ROOT/completion"
make_minimal_bin "$completion_root/bin"
make_tmux_mock "$completion_root/bin"
printf '%s\n' \
  work \
  codex-alpha-100000 \
  codex-project_two-120000 \
  codex- \
  codex-invalid.name > "$completion_root/sessions"

PATH="$completion_root/bin" \
  CXT_TMUX_COUNT="$completion_root/bash-tmux.count" \
  CXT_TMUX_LOG="$completion_root/bash-tmux.args" \
  CXT_TMUX_SESSIONS="$completion_root/sessions" \
  BASH_COMPLETION="$BASH_COMPLETION" \
  bash -c '
    source "$BASH_COMPLETION"
    COMP_WORDS=(cxt --at "")
    COMP_CWORD=2
    _cxt_complete
    printf "%s\n" "${COMPREPLY[@]}"
  ' > "$completion_root/bash-at.out"
assert_file_contains "$completion_root/bash-at.out" 'codex-alpha-100000'
assert_file_contains "$completion_root/bash-at.out" 'codex-project_two-120000'
assert_file_lacks_line "$completion_root/bash-at.out" work
assert_file_lacks_line "$completion_root/bash-at.out" codex-invalid.name
assert_file_lacks_line "$completion_root/bash-at.out" codex-

rm -f "$completion_root/bash-tmux.count" "$completion_root"/bash-tmux.args.*
PATH="$completion_root/bin" \
  CXT_TMUX_COUNT="$completion_root/bash-tmux.count" \
  CXT_TMUX_LOG="$completion_root/bash-tmux.args" \
  CXT_TMUX_SESSIONS="$completion_root/sessions" \
  BASH_COMPLETION="$BASH_COMPLETION" \
  bash -c '
    source "$BASH_COMPLETION"
    COMP_WORDS=(cxt --ks=codex-project)
    COMP_CWORD=1
    _cxt_complete
    printf "%s\n" "${COMPREPLY[@]}"
  ' > "$completion_root/bash-ks-equals.out"
assert_file_contains "$completion_root/bash-ks-equals.out" '--ks=codex-project_two-120000'

if [ -n "$ZSH_BIN" ]; then
  PATH="$completion_root/bin" \
    CXT_TMUX_COUNT="$completion_root/zsh-tmux.count" \
    CXT_TMUX_LOG="$completion_root/zsh-tmux.args" \
    CXT_TMUX_SESSIONS="$completion_root/sessions" \
    ZSH_COMPLETION="$ZSH_COMPLETION" \
    "$ZSH_BIN" -f -c 'source "$ZSH_COMPLETION"; _cxt_session_names' \
      > "$completion_root/zsh-sessions.out"
  assert_file_contains "$completion_root/zsh-sessions.out" 'codex-alpha-100000'
  assert_file_contains "$completion_root/zsh-sessions.out" 'codex-project_two-120000'
  assert_file_lacks_line "$completion_root/zsh-sessions.out" work
  assert_file_lacks_line "$completion_root/zsh-sessions.out" codex-invalid.name
  assert_file_lacks_line "$completion_root/zsh-sessions.out" codex-

  rm -f "$completion_root/zsh-tmux.count" "$completion_root"/zsh-tmux.args.*
  PATH="$completion_root/bin" \
    CXT_TMUX_COUNT="$completion_root/zsh-tmux.count" \
    CXT_TMUX_LOG="$completion_root/zsh-tmux.args" \
    CXT_TMUX_SESSIONS="$completion_root/sessions" \
    ZSH_COMPLETION="$ZSH_COMPLETION" \
    "$ZSH_BIN" -f -c '
      source "$ZSH_COMPLETION"
      compadd() {
        [[ "${1:-}" == -- ]] && shift
        print -rl -- "$@"
      }
      words=(cxt --kill-session "")
      CURRENT=3
      _cxt
    ' > "$completion_root/zsh-kill-session.out"
  assert_file_contains "$completion_root/zsh-kill-session.out" 'codex-alpha-100000'
  assert_file_contains "$completion_root/zsh-kill-session.out" 'codex-project_two-120000'
  assert_file_lacks_line "$completion_root/zsh-kill-session.out" work
fi

tmux_root="$TMP_ROOT/tmux"
tmux_project="$tmux_root/Project name+demo"
mkdir -p "$tmux_project"
make_minimal_bin "$tmux_root/bin"
make_codex_mock "$tmux_root/bin"
make_tmux_mock "$tmux_root/bin"
(
  unset TMUX
  cd "$tmux_project"
  PATH="$tmux_root/bin" \
    CXT_TMUX_COUNT="$tmux_root/tmux.count" \
    CXT_TMUX_LOG="$tmux_root/tmux.args" \
    "$CXT" --xhigh 'prompt with spaces'
)
assert_args "$tmux_root/tmux.args.1" \
  new-session -d -s codex-Project-name-demo-000000 -c "$tmux_project" \
  codex --no-alt-screen -c 'model_reasoning_effort="xhigh"' 'prompt with spaces'
assert_args "$tmux_root/tmux.args.2" set-option -t codex-Project-name-demo-000000 mouse on
assert_args "$tmux_root/tmux.args.3" set-option -w -t codex-Project-name-demo-000000 remain-on-exit off
assert_args "$tmux_root/tmux.args.4" attach-session -t codex-Project-name-demo-000000

rm -f "$tmux_root/tmux.count" "$tmux_root"/tmux.args.*
(
  cd "$tmux_project"
  PATH="$tmux_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CXT_TMUX_COUNT="$tmux_root/tmux.count" \
    CXT_TMUX_LOG="$tmux_root/tmux.args" \
    "$CXT" review
)
assert_args "$tmux_root/tmux.args.4" switch-client -t codex-Project-name-demo-000000

# Installer tests always use temporary homes.
install_home="$TMP_ROOT/install-home"
mkdir -p "$install_home"
printf '# Keep this ~/.local/bin note\nexport EDITOR=vim\n' > "$install_home/.zshrc"
HOME="$install_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER"
[ -L "$install_home/.local/bin/cxt" ] || fail 'installer did not create the cxt symlink'
[ "$(readlink "$install_home/.local/bin/cxt")" = "$CXT" ] || fail 'installer link target is not the absolute cxt path'
assert_file_contains "$install_home/.zshrc" '# Keep this ~/.local/bin note'
assert_file_contains "$install_home/.zshrc" 'export EDITOR=vim'
assert_count 1 '# >>> script-store cxt >>>' "$install_home/.zshrc"
assert_count 1 '# >>> script-store cxt completion >>>' "$install_home/.zshrc"
assert_file_contains "$install_home/.zshrc" "$ZSH_COMPLETION"
if [ -n "$ZSH_BIN" ]; then
  HOME="$install_home" ZDOTDIR="$install_home" PATH="$ORIGINAL_PATH" \
    "$ZSH_BIN" -f -c 'source "$1"; [[ "${_comps[cxt]-}" = _cxt ]]' zsh "$install_home/.zshrc" || \
    fail 'installed zsh completion did not register cxt'
fi
HOME="$install_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER"
assert_count 1 '# >>> script-store cxt >>>' "$install_home/.zshrc"
assert_count 1 '# >>> script-store cxt completion >>>' "$install_home/.zshrc"

HOME="$install_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall
[ ! -e "$install_home/.local/bin/cxt" ] && [ ! -L "$install_home/.local/bin/cxt" ] || fail 'uninstall left the managed link behind'
assert_count 0 '# >>> script-store cxt >>>' "$install_home/.zshrc"
assert_count 0 '# >>> script-store cxt completion >>>' "$install_home/.zshrc"
assert_file_contains "$install_home/.zshrc" '# Keep this ~/.local/bin note'
assert_file_contains "$install_home/.zshrc" 'export EDITOR=vim'

legacy_home="$TMP_ROOT/legacy-home"
mkdir -p "$legacy_home/.local/bin"
ln -s "$LEGACY_CX" "$legacy_home/.local/bin/cx"
printf '%s\n' \
  '# keep legacy migration content' \
  '# >>> script-store cx >>>' \
  'export PATH="$HOME/.local/bin:$PATH"' \
  '# <<< script-store cx <<<' > "$legacy_home/.zshrc"
HOME="$legacy_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" > "$legacy_home/install.out"
[ -L "$legacy_home/.local/bin/cxt" ] || fail 'migration did not create the cxt symlink'
[ "$(readlink "$legacy_home/.local/bin/cxt")" = "$CXT" ] || fail 'migrated cxt link target is incorrect'
[ ! -e "$legacy_home/.local/bin/cx" ] && [ ! -L "$legacy_home/.local/bin/cx" ] || fail 'migration left the managed cx link behind'
assert_count 1 '# >>> script-store cxt >>>' "$legacy_home/.zshrc"
assert_count 1 '# >>> script-store cxt completion >>>' "$legacy_home/.zshrc"
assert_count 0 '# >>> script-store cx >>>' "$legacy_home/.zshrc"
assert_file_contains "$legacy_home/.zshrc" '# keep legacy migration content'
assert_file_contains "$legacy_home/install.out" 'Removed managed legacy cx link'
assert_file_contains "$legacy_home/install.out" 'Renamed the managed cx PATH block to cxt'

HOME="$legacy_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall > "$legacy_home/uninstall.out"
[ ! -e "$legacy_home/.local/bin/cxt" ] && [ ! -L "$legacy_home/.local/bin/cxt" ] || fail 'uninstall left the migrated cxt link behind'
assert_count 0 '# >>> script-store cxt >>>' "$legacy_home/.zshrc"
assert_count 0 '# >>> script-store cxt completion >>>' "$legacy_home/.zshrc"

legacy_modified_home="$TMP_ROOT/legacy-modified-home"
mkdir -p "$legacy_modified_home/.local/bin"
ln -s "$LEGACY_CX" "$legacy_modified_home/.local/bin/cx"
printf '%s\n' \
  '# >>> script-store cx >>>' \
  'export PATH="$HOME/.local/bin:$PATH"' \
  'export KEEP_ME_FROM_USER=1' \
  '# <<< script-store cx <<<' > "$legacy_modified_home/.zshrc"
cp "$legacy_modified_home/.zshrc" "$legacy_modified_home/.zshrc.before"
set +e
HOME="$legacy_modified_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$legacy_modified_home/stdout" 2> "$legacy_modified_home/stderr"
legacy_modified_status=$?
set -e
[ "$legacy_modified_status" -ne 0 ] || fail 'installer accepted a modified legacy marker block'
[ ! -e "$legacy_modified_home/.local/bin/cxt" ] && [ ! -L "$legacy_modified_home/.local/bin/cxt" ] || \
  fail 'modified legacy marker preflight created the cxt link'
[ -L "$legacy_modified_home/.local/bin/cx" ] || fail 'modified legacy marker preflight removed the cx link'
cmp -s "$legacy_modified_home/.zshrc.before" "$legacy_modified_home/.zshrc" || \
  fail 'installer changed a modified legacy marker block'
assert_file_contains "$legacy_modified_home/stderr" 'found a modified cx marker block'

legacy_malformed_home="$TMP_ROOT/legacy-malformed-home"
mkdir -p "$legacy_malformed_home/.local/bin"
ln -s "$LEGACY_CX" "$legacy_malformed_home/.local/bin/cx"
printf '%s\n' \
  '# >>> script-store cx >>>' \
  'export PATH="$HOME/.local/bin:$PATH"' > "$legacy_malformed_home/.zshrc"
cp "$legacy_malformed_home/.zshrc" "$legacy_malformed_home/.zshrc.before"
set +e
HOME="$legacy_malformed_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$legacy_malformed_home/stdout" 2> "$legacy_malformed_home/stderr"
legacy_malformed_status=$?
set -e
[ "$legacy_malformed_status" -ne 0 ] || fail 'installer accepted a malformed legacy marker block'
[ ! -e "$legacy_malformed_home/.local/bin/cxt" ] && [ ! -L "$legacy_malformed_home/.local/bin/cxt" ] || \
  fail 'malformed legacy marker preflight created the cxt link'
[ -L "$legacy_malformed_home/.local/bin/cx" ] || fail 'malformed legacy marker preflight removed the cx link'
cmp -s "$legacy_malformed_home/.zshrc.before" "$legacy_malformed_home/.zshrc" || \
  fail 'installer changed a malformed legacy marker block'
assert_file_contains "$legacy_malformed_home/stderr" 'found a malformed or duplicate cx marker block'

current_modified_home="$TMP_ROOT/current-modified-home"
mkdir -p "$current_modified_home/.local/bin"
ln -s "$CXT" "$current_modified_home/.local/bin/cxt"
printf '%s\n' \
  '# >>> script-store cxt >>>' \
  'export PATH="$HOME/.local/bin:$PATH"' \
  'export KEEP_CURRENT_USER_LINE=1' \
  '# <<< script-store cxt <<<' > "$current_modified_home/.bashrc"
cp "$current_modified_home/.bashrc" "$current_modified_home/.bashrc.before"
set +e
HOME="$current_modified_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall \
  > "$current_modified_home/stdout" 2> "$current_modified_home/stderr"
current_modified_status=$?
set -e
[ "$current_modified_status" -ne 0 ] || fail 'uninstaller accepted a modified cxt marker block'
[ -L "$current_modified_home/.local/bin/cxt" ] || fail 'uninstaller removed cxt before marker preflight'
cmp -s "$current_modified_home/.bashrc.before" "$current_modified_home/.bashrc" || \
  fail 'uninstaller changed a modified cxt marker block'
assert_file_contains "$current_modified_home/stderr" 'found a modified cxt marker block'

legacy_other_target="$TMP_ROOT/user-managed-cx"
printf '#!/usr/bin/env bash\n' > "$legacy_other_target"
legacy_other_home="$TMP_ROOT/legacy-other-home"
mkdir -p "$legacy_other_home/.local/bin"
printf 'export PATH="$PATH:$HOME/.local/bin"\n' > "$legacy_other_home/.bashrc"
ln -s "$legacy_other_target" "$legacy_other_home/.local/bin/cx"
HOME="$legacy_other_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$legacy_other_home/stdout" 2> "$legacy_other_home/stderr"
[ -L "$legacy_other_home/.local/bin/cxt" ] || fail 'installer did not create cxt beside a non-managed cx link'
[ "$(readlink "$legacy_other_home/.local/bin/cx")" = "$legacy_other_target" ] || fail 'installer changed a non-managed cx link'
assert_file_contains "$legacy_other_home/stderr" 'Left non-managed legacy cx path unchanged'

configured_home="$TMP_ROOT/configured-home"
mkdir -p "$configured_home"
printf 'export PATH="$PATH:$HOME/.local/bin"\n' > "$configured_home/.bashrc"
HOME="$configured_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --shell bash
assert_count 0 '# >>> script-store cxt >>>' "$configured_home/.bashrc"
assert_count 1 '# >>> script-store cxt completion >>>' "$configured_home/.bashrc"
assert_file_contains "$configured_home/.bashrc" "$BASH_COMPLETION"
HOME="$configured_home" PATH="$ORIGINAL_PATH" \
  bash -c 'source "$1"; complete -p cxt >/dev/null' bash "$configured_home/.bashrc" || \
  fail 'installed bash completion did not register cxt'

path_home="$TMP_ROOT/path-home"
mkdir -p "$path_home/.local/bin"
printf '# keep me\n' > "$path_home/.bashrc"
HOME="$path_home" SHELL=/bin/bash PATH="$path_home/.local/bin/:$ORIGINAL_PATH" "$INSTALLER"
assert_count 0 '# >>> script-store cxt >>>' "$path_home/.bashrc"
assert_count 1 '# >>> script-store cxt completion >>>' "$path_home/.bashrc"
assert_file_contains "$path_home/.bashrc" '# keep me'

rollback_home="$TMP_ROOT/rollback-home"
rollback_fixture="$TMP_ROOT/fail-completion-write.bash"
mkdir -p "$rollback_home"
cat > "$rollback_fixture" <<'EOF'
printf() {
  if [ "${1:-}" = '%s\n%s\n%s\n' ] && \
    [ "${2:-}" = '# >>> script-store cxt completion >>>' ]; then
    return 1
  fi
  builtin printf "$@"
}
EOF
set +e
HOME="$rollback_home" \
  SHELL=/bin/bash \
  PATH="$ORIGINAL_PATH" \
  BASH_ENV="$rollback_fixture" \
  "$INSTALLER" > "$rollback_home/stdout" 2> "$rollback_home/stderr"
rollback_status=$?
set -e
[ "$rollback_status" -ne 0 ] || fail 'installer accepted a forced completion write failure'
[ ! -e "$rollback_home/.bashrc" ] && [ ! -L "$rollback_home/.bashrc" ] || \
  fail 'rollback left a newly created rc file behind'
[ ! -e "$rollback_home/.local/bin/cxt" ] && [ ! -L "$rollback_home/.local/bin/cxt" ] || \
  fail 'rollback left the newly created cxt link behind'
assert_file_contains "$rollback_home/stderr" 'could not update rc file'
assert_file_contains "$rollback_home/stderr" 'Rolled back the failed cxt operation.'

uninstall_rollback_home="$TMP_ROOT/uninstall-rollback-home"
uninstall_rollback_fixture="$TMP_ROOT/fail-cxt-link-removal.bash"
mkdir -p "$uninstall_rollback_home"
HOME="$uninstall_rollback_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" \
  > "$uninstall_rollback_home/install.out"
cp "$uninstall_rollback_home/.bashrc" "$uninstall_rollback_home/.bashrc.before"
cat > "$uninstall_rollback_fixture" <<'EOF'
rm() {
  case "${1:-}" in
    */.local/bin/cxt) return 1 ;;
  esac
  command rm "$@"
}
EOF
set +e
HOME="$uninstall_rollback_home" \
  SHELL=/bin/bash \
  PATH="$ORIGINAL_PATH" \
  BASH_ENV="$uninstall_rollback_fixture" \
  "$INSTALLER" --uninstall \
    > "$uninstall_rollback_home/stdout" 2> "$uninstall_rollback_home/stderr"
uninstall_rollback_status=$?
set -e
[ "$uninstall_rollback_status" -ne 0 ] || fail 'uninstaller accepted a forced link removal failure'
[ -L "$uninstall_rollback_home/.local/bin/cxt" ] || \
  fail 'uninstall rollback did not preserve the managed cxt link'
[ "$(readlink "$uninstall_rollback_home/.local/bin/cxt")" = "$CXT" ] || \
  fail 'uninstall rollback restored the wrong cxt link target'
cmp -s "$uninstall_rollback_home/.bashrc.before" "$uninstall_rollback_home/.bashrc" || \
  fail 'uninstall rollback did not restore the rc file'
assert_file_contains "$uninstall_rollback_home/stderr" 'could not remove managed link'
assert_file_contains "$uninstall_rollback_home/stderr" 'Rolled back the failed cxt operation.'

completion_modified_home="$TMP_ROOT/completion-modified-home"
mkdir -p "$completion_modified_home/.local/bin"
ln -s "$CXT" "$completion_modified_home/.local/bin/cxt"
printf '%s\n' \
  '# >>> script-store cxt completion >>>' \
  'source /tmp/user-modified-cxt-completion' \
  '# <<< script-store cxt completion <<<' > "$completion_modified_home/.bashrc"
cp "$completion_modified_home/.bashrc" "$completion_modified_home/.bashrc.before"
set +e
HOME="$completion_modified_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall \
  > "$completion_modified_home/stdout" 2> "$completion_modified_home/stderr"
completion_modified_status=$?
set -e
[ "$completion_modified_status" -ne 0 ] || fail 'uninstaller accepted a modified completion marker block'
[ -L "$completion_modified_home/.local/bin/cxt" ] || fail 'completion preflight removed cxt link'
cmp -s "$completion_modified_home/.bashrc.before" "$completion_modified_home/.bashrc" || \
  fail 'installer changed a modified completion marker block'
assert_file_contains "$completion_modified_home/stderr" 'found a modified cxt completion marker block'

collision_home="$TMP_ROOT/collision-home"
mkdir -p "$collision_home/.local/bin"
printf 'user file\n' > "$collision_home/.local/bin/cxt"
set +e
HOME="$collision_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" > "$collision_home/stdout" 2> "$collision_home/stderr"
collision_status=$?
set -e
[ "$collision_status" -ne 0 ] || fail 'installer accepted a conflicting cxt file'
[ "$(cat "$collision_home/.local/bin/cxt")" = 'user file' ] || fail 'installer overwrote a conflicting cxt file'
assert_file_contains "$collision_home/stderr" 'refusing to overwrite'

other_target="$TMP_ROOT/other-cxt"
printf '#!/usr/bin/env bash\n' > "$other_target"
other_link_home="$TMP_ROOT/other-link-home"
mkdir -p "$other_link_home/.local/bin"
ln -s "$other_target" "$other_link_home/.local/bin/cxt"
HOME="$other_link_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall \
  > "$other_link_home/stdout" 2> "$other_link_home/stderr"
[ -L "$other_link_home/.local/bin/cxt" ] || fail 'uninstall removed a non-managed link'
[ "$(readlink "$other_link_home/.local/bin/cxt")" = "$other_target" ] || fail 'uninstall changed a non-managed link'

dry_home="$TMP_ROOT/dry-home"
HOME="$dry_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --dry-run > "$TMP_ROOT/dry-run.out"
[ ! -e "$dry_home" ] || fail 'dry-run changed the temporary HOME'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would create directory'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would create link'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would add the managed PATH block'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would add the managed completion block'

legacy_dry_home="$TMP_ROOT/legacy-dry-home"
mkdir -p "$legacy_dry_home/.local/bin"
ln -s "$LEGACY_CX" "$legacy_dry_home/.local/bin/cx"
printf '%s\n' \
  '# >>> script-store cx >>>' \
  'export PATH="$HOME/.local/bin:$PATH"' \
  '# <<< script-store cx <<<' > "$legacy_dry_home/.zshrc"
HOME="$legacy_dry_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" --dry-run > "$legacy_dry_home/dry-run.out"
[ ! -e "$legacy_dry_home/.local/bin/cxt" ] && [ ! -L "$legacy_dry_home/.local/bin/cxt" ] || fail 'legacy dry-run created the cxt link'
[ -L "$legacy_dry_home/.local/bin/cx" ] || fail 'legacy dry-run removed the cx link'
assert_count 1 '# >>> script-store cx >>>' "$legacy_dry_home/.zshrc"
assert_count 0 '# >>> script-store cxt >>>' "$legacy_dry_home/.zshrc"
assert_file_contains "$legacy_dry_home/dry-run.out" 'Would remove managed legacy cx link'
assert_file_contains "$legacy_dry_home/dry-run.out" 'Would rename the managed cx PATH block to cxt'

printf 'cxt tests passed\n'
