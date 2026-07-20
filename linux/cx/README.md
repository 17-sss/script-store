# cx

현재 프로젝트 이름으로 tmux 세션을 만들고 Codex를 실행하는 Bash/Zsh 공용 명령입니다. `cx` 자체는 Bash 기반 독립 실행 파일이므로 셸 rc 파일에 함수를 복사하지 않습니다.

## 설치

저장소 루트에서 실행합니다.

```bash
./linux/cx/install-cx.sh
source ~/.zshrc # zsh
# source ~/.bashrc # bash
```

설치기는 `linux/cx/bin/cx`를 절대 경로로 `~/.local/bin/cx`에 심볼릭 링크합니다. `~/.local/bin`이 현재 `PATH`와 선택한 rc 파일 어디에도 설정되어 있지 않을 때만 marker 블록을 추가합니다. 부모 셸의 환경은 직접 변경하지 않으므로 설치 후 rc 파일을 다시 읽거나 새 터미널을 열어야 합니다.

셸 또는 rc 파일을 명시하거나 변경 내용을 미리 볼 수 있습니다.

```bash
./linux/cx/install-cx.sh --shell bash
./linux/cx/install-cx.sh --shell zsh --rc-file ~/.config/zsh/.zshrc
./linux/cx/install-cx.sh --dry-run
```

제거할 때는 설치기가 만든 링크와 marker 블록만 삭제합니다.

```bash
./linux/cx/install-cx.sh --uninstall
```

## 사용법

```bash
cx
cx --xhigh
cx --madmax
cx --xhigh --madmax
cx --model gpt-5.6-sol
cx resume --last
```

- 모든 실행에는 `--no-alt-screen`이 기본으로 추가됩니다.
- `--xhigh`는 `-c 'model_reasoning_effort="xhigh"'`로 변환됩니다.
- `--madmax`는 Codex의 `--yolo`로 변환됩니다. 승인 절차와 sandbox를 우회하므로 신뢰할 수 있는 작업에서만 사용하세요.
- `--` 뒤의 `--xhigh`와 `--madmax`는 변환하지 않고 그대로 전달됩니다.
- tmux가 없으면 현재 터미널에서 Codex를 직접 실행합니다.
- tmux 안에서는 nested attach 대신 새 세션으로 client를 전환합니다.

세션 이름은 `codex-<현재 디렉터리>-<HHMMSS>` 형식이며 영문자, 숫자, `_`, `-` 이외의 문자는 `-`로 바뀝니다.

## 테스트

테스트는 mock `codex`, mock `tmux`, 임시 `HOME`만 사용하며 실제 사용자 설정을 변경하지 않습니다.

```bash
./linux/cx/tests/test-cx.sh
```

ShellCheck가 설치되어 있으면 테스트 중 자동으로 두 실행 스크립트를 검사합니다.
