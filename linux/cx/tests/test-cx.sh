#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CX_DIR="${SCRIPT_DIR%/tests}"
CX="$CX_DIR/bin/cx"
INSTALLER="$CX_DIR/install-cx.sh"
ORIGINAL_PATH="$PATH"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cx-test.XXXXXX")"

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
: > "$CX_CODEX_LOG"
for mock_arg in "$@"; do
  printf '%s\0' "$mock_arg" >> "$CX_CODEX_LOG"
done
exit "${CX_CODEX_EXIT_CODE:-0}"
EOF
  chmod +x "$bin_dir/codex"
}

make_tmux_mock() {
  local bin_dir="$1"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
call_number=0
if [ -r "$CX_TMUX_COUNT" ]; then
  IFS= read -r call_number < "$CX_TMUX_COUNT"
fi
call_number=$((call_number + 1))
printf '%s\n' "$call_number" > "$CX_TMUX_COUNT"
: > "$CX_TMUX_LOG.$call_number"
for mock_arg in "$@"; do
  printf '%s\0' "$mock_arg" >> "$CX_TMUX_LOG.$call_number"
done

case "${1:-}" in
  list-sessions)
    if [ -r "${CX_TMUX_SESSIONS:-}" ]; then
      while IFS= read -r mock_session || [ -n "$mock_session" ]; do
        printf '%s\n' "$mock_session"
      done < "$CX_TMUX_SESSIONS"
    fi
    ;;
  display-message)
    printf '%s\n' "${CX_TMUX_CURRENT_SESSION:-}"
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
    PATH="$mock_bin" CX_CODEX_LOG="$case_root/codex.args" "$CX" "$@"
  ) 2> "$case_root/stderr"
  assert_file_contains "$case_root/stderr" 'cx: tmux not found; launching Codex directly'
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
    PATH="$case_root/bin" CX_CODEX_LOG="$case_root/codex.args" "$CX" "$@"
  ) 2> "$case_root/stderr"
  conflict_status=$?
  set -e

  [ "$conflict_status" -eq 2 ] || fail "$category shortcut conflict returned $conflict_status instead of 2"
  assert_file_contains "$case_root/stderr" "cx: $category shortcuts cannot be combined"
  [ ! -e "$case_root/codex.args" ] || fail "$category shortcut conflict launched Codex"
}

bash -n "$CX"
bash -n "$INSTALLER"
bash -n "$0"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s bash "$CX" "$INSTALLER"
else
  printf 'SKIP: ShellCheck is not installed\n'
fi

"$CX" --cx-help > "$TMP_ROOT/cx-help"
assert_file_contains "$TMP_ROOT/cx-help" 'Usage: cx [CX_OPTIONS] [CODEX_OPTIONS] [PROMPT|COMMAND ...]'
assert_file_contains "$TMP_ROOT/cx-help" '--sol       --model gpt-5.6-sol'
assert_file_contains "$TMP_ROOT/cx-help" '--safe       read-only + untrusted approvals'
assert_file_contains "$TMP_ROOT/cx-help" '--attach, --at [SESSION]'
assert_file_contains "$TMP_ROOT/cx-help" '--kill-session, --ks [SESSION]'
assert_file_contains "$TMP_ROOT/cx-help" '--kill-all, --ka'

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
if command -v zsh >/dev/null 2>&1; then
  zsh_case="$TMP_ROOT/zsh-call"
  mkdir -p "$zsh_case/project"
  make_minimal_bin "$zsh_case/bin"
  make_codex_mock "$zsh_case/bin"
  CX_PATH="$CX" MOCK_PATH="$zsh_case/bin" CX_CODEX_LOG="$zsh_case/codex.args" \
    zsh -c 'cd "$1" && PATH="$MOCK_PATH" "$CX_PATH" --madmax' zsh "$zsh_case/project" \
    2> "$zsh_case/stderr"
  assert_args "$zsh_case/codex.args" --no-alt-screen --yolo
fi

missing_root="$TMP_ROOT/missing-codex"
mkdir -p "$missing_root/project"
make_minimal_bin "$missing_root/bin"
set +e
(
  cd "$missing_root/project"
  PATH="$missing_root/bin" "$CX"
) 2> "$missing_root/stderr"
missing_status=$?
set -e
[ "$missing_status" -eq 127 ] || fail "missing codex returned $missing_status instead of 127"
assert_file_contains "$missing_root/stderr" 'cx: codex command not found'

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
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    "$CX" --at
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" attach-session -t codex-project-new

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    "$CX" --attach codex-project-old
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" switch-client -t codex-project-old

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  unset TMUX
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    "$CX" --ks
)
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.2" kill-session -t codex-project-new

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    CX_TMUX_CURRENT_SESSION=codex-project-old \
    "$CX" --kill-session
)
assert_args "$session_root/tmux.args.1" display-message -p '#{session_name}'
assert_args "$session_root/tmux.args.2" list-sessions -F '#{session_created}:#{session_name}'
assert_args "$session_root/tmux.args.3" kill-session -t codex-project-old

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    TMUX='/tmp/mock-tmux,1,0' \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    CX_TMUX_CURRENT_SESSION=codex-project-old \
    "$CX" --ka
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
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    "$CX" --at work
) 2> "$session_root/non-cx.stderr"
non_cx_status=$?
set -e
[ "$non_cx_status" -eq 2 ] || fail "non-cx attach returned $non_cx_status instead of 2"
assert_file_contains "$session_root/non-cx.stderr" 'cx: not a cx tmux session: work'
[ ! -e "$session_root/tmux.count" ] || fail 'non-cx attach called tmux'

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
printf '%s\n' '400:work' > "$session_root/no-cx-sessions"
set +e
(
  unset TMUX
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/no-cx-sessions" \
    "$CX" --attach
) 2> "$session_root/no-cx.stderr"
no_cx_status=$?
set -e
[ "$no_cx_status" -eq 1 ] || fail "empty cx attach returned $no_cx_status instead of 1"
assert_file_contains "$session_root/no-cx.stderr" 'cx: no cx tmux sessions found'
assert_args "$session_root/tmux.args.1" list-sessions -F '#{session_created}:#{session_name}'

rm -f "$session_root/tmux.count" "$session_root"/tmux.args.*
set +e
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    "$CX" --at --kill-all
) 2> "$session_root/action-conflict.stderr"
action_conflict_status=$?
set -e
[ "$action_conflict_status" -eq 2 ] || fail "session action conflict returned $action_conflict_status instead of 2"
assert_file_contains "$session_root/action-conflict.stderr" 'cx: session management shortcuts cannot be combined'
[ ! -e "$session_root/tmux.count" ] || fail 'session action conflict called tmux'

set +e
(
  cd "$session_root/project"
  PATH="$session_root/bin" \
    CX_TMUX_COUNT="$session_root/tmux.count" \
    CX_TMUX_LOG="$session_root/tmux.args" \
    CX_TMUX_SESSIONS="$session_root/sessions" \
    "$CX" --attach --safe
) 2> "$session_root/action-codex-conflict.stderr"
action_codex_status=$?
set -e
[ "$action_codex_status" -eq 2 ] || fail "session/Codex conflict returned $action_codex_status instead of 2"
assert_file_contains "$session_root/action-codex-conflict.stderr" 'cx: session management options cannot be combined with Codex arguments'
[ ! -e "$session_root/tmux.count" ] || fail 'session/Codex conflict called tmux'

missing_tmux_root="$TMP_ROOT/missing-tmux-management"
mkdir -p "$missing_tmux_root/project"
make_minimal_bin "$missing_tmux_root/bin"
set +e
(
  cd "$missing_tmux_root/project"
  PATH="$missing_tmux_root/bin" "$CX" --ka
) 2> "$missing_tmux_root/stderr"
missing_tmux_status=$?
set -e
[ "$missing_tmux_status" -eq 127 ] || fail "missing tmux management returned $missing_tmux_status instead of 127"
assert_file_contains "$missing_tmux_root/stderr" 'cx: tmux command not found'

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
    CX_TMUX_COUNT="$tmux_root/tmux.count" \
    CX_TMUX_LOG="$tmux_root/tmux.args" \
    "$CX" --xhigh 'prompt with spaces'
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
    CX_TMUX_COUNT="$tmux_root/tmux.count" \
    CX_TMUX_LOG="$tmux_root/tmux.args" \
    "$CX" review
)
assert_args "$tmux_root/tmux.args.4" switch-client -t codex-Project-name-demo-000000

# Installer tests always use temporary homes.
install_home="$TMP_ROOT/install-home"
mkdir -p "$install_home"
printf '# Keep this ~/.local/bin note\nexport EDITOR=vim\n' > "$install_home/.zshrc"
HOME="$install_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER"
[ -L "$install_home/.local/bin/cx" ] || fail 'installer did not create the cx symlink'
[ "$(readlink "$install_home/.local/bin/cx")" = "$CX" ] || fail 'installer link target is not the absolute cx path'
assert_file_contains "$install_home/.zshrc" '# Keep this ~/.local/bin note'
assert_file_contains "$install_home/.zshrc" 'export EDITOR=vim'
assert_count 1 '# >>> script-store cx >>>' "$install_home/.zshrc"
HOME="$install_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER"
assert_count 1 '# >>> script-store cx >>>' "$install_home/.zshrc"

HOME="$install_home" SHELL=/bin/zsh PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall
[ ! -e "$install_home/.local/bin/cx" ] && [ ! -L "$install_home/.local/bin/cx" ] || fail 'uninstall left the managed link behind'
assert_count 0 '# >>> script-store cx >>>' "$install_home/.zshrc"
assert_file_contains "$install_home/.zshrc" '# Keep this ~/.local/bin note'
assert_file_contains "$install_home/.zshrc" 'export EDITOR=vim'

configured_home="$TMP_ROOT/configured-home"
mkdir -p "$configured_home"
printf 'export PATH="$PATH:$HOME/.local/bin"\n' > "$configured_home/.bashrc"
HOME="$configured_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --shell bash
assert_count 0 '# >>> script-store cx >>>' "$configured_home/.bashrc"

path_home="$TMP_ROOT/path-home"
mkdir -p "$path_home/.local/bin"
printf '# keep me\n' > "$path_home/.bashrc"
HOME="$path_home" SHELL=/bin/bash PATH="$path_home/.local/bin/:$ORIGINAL_PATH" "$INSTALLER"
assert_count 0 '# >>> script-store cx >>>' "$path_home/.bashrc"
assert_file_contains "$path_home/.bashrc" '# keep me'

collision_home="$TMP_ROOT/collision-home"
mkdir -p "$collision_home/.local/bin"
printf 'user file\n' > "$collision_home/.local/bin/cx"
set +e
HOME="$collision_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" > "$collision_home/stdout" 2> "$collision_home/stderr"
collision_status=$?
set -e
[ "$collision_status" -ne 0 ] || fail 'installer accepted a conflicting cx file'
[ "$(cat "$collision_home/.local/bin/cx")" = 'user file' ] || fail 'installer overwrote a conflicting cx file'
assert_file_contains "$collision_home/stderr" 'refusing to overwrite'

other_target="$TMP_ROOT/other-cx"
printf '#!/usr/bin/env bash\n' > "$other_target"
other_link_home="$TMP_ROOT/other-link-home"
mkdir -p "$other_link_home/.local/bin"
ln -s "$other_target" "$other_link_home/.local/bin/cx"
HOME="$other_link_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --uninstall \
  > "$other_link_home/stdout" 2> "$other_link_home/stderr"
[ -L "$other_link_home/.local/bin/cx" ] || fail 'uninstall removed a non-managed link'
[ "$(readlink "$other_link_home/.local/bin/cx")" = "$other_target" ] || fail 'uninstall changed a non-managed link'

dry_home="$TMP_ROOT/dry-home"
HOME="$dry_home" SHELL=/bin/bash PATH="$ORIGINAL_PATH" "$INSTALLER" --dry-run > "$TMP_ROOT/dry-run.out"
[ ! -e "$dry_home" ] || fail 'dry-run changed the temporary HOME'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would create directory'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would create link'
assert_file_contains "$TMP_ROOT/dry-run.out" 'Would add the managed PATH block'

printf 'cx tests passed\n'
