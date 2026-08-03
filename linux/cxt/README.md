# cxt

현재 프로젝트 이름으로 tmux 세션을 만들고 Codex를 실행하는 Bash/Zsh 공용 명령입니다. `cxt` 자체는 Bash 기반 독립 실행 파일이므로 셸 rc 파일에 함수를 복사하지 않습니다.

## 설치

저장소 루트에서 실행합니다.

```bash
./linux/cxt/install-cxt.sh
source ~/.zshrc # zsh
# source ~/.bashrc # bash
```

설치기는 `linux/cxt/bin/cxt`를 절대 경로로 `~/.local/bin/cxt`에 심볼릭 링크합니다. `~/.local/bin`이 현재 `PATH`와 선택한 rc 파일 어디에도 설정되어 있지 않을 때만 PATH marker 블록을 추가하고, 선택한 Bash/Zsh용 탭 완성을 별도의 completion marker 블록으로 등록합니다. 부모 셸의 환경은 직접 변경하지 않으므로 설치 후 rc 파일을 다시 읽거나 새 터미널을 열어야 합니다.

이전 `cx` 설치기가 만든 정확한 심볼릭 링크와 3줄짜리 PATH marker가 있으면 새 설치기가 `cxt`로 이전합니다. marker 내부가 수정되었거나 중복·손상된 경우에는 사용자 설정으로 간주해 링크와 rc 파일을 변경하기 전에 중단합니다. 사용자가 직접 만든 `~/.local/bin/cx` 파일이나 다른 대상을 가리키는 링크도 변경하지 않습니다. 설치나 제거 도중 후속 단계가 실패하면 시작 전 rc 파일과 관리 링크 상태로 되돌립니다. 롤백 자체가 실패한 경로는 오류 메시지로 남겨 수동 확인할 수 있게 합니다.

셸 또는 rc 파일을 명시하거나 변경 내용을 미리 볼 수 있습니다.

```bash
./linux/cxt/install-cxt.sh --shell bash
./linux/cxt/install-cxt.sh --shell zsh --rc-file ~/.config/zsh/.zshrc
./linux/cxt/install-cxt.sh --dry-run
```

제거할 때는 설치기가 만든 링크와 marker 블록만 삭제합니다.

```bash
./linux/cxt/install-cxt.sh --uninstall
```

## 사용법

```bash
cxt
cxt --sol --high --auto
cxt --terra --medium --safe
cxt --luna --max --full-auto
cxt --sol --ultra --madmax
cxt resume --last
cxt --at
cxt --ks
```

- 모든 실행에는 `--no-alt-screen`이 기본으로 추가됩니다.
- `Ctrl+T`를 누르면 현재 세션의 transcript를 열 수 있습니다. transcript 화면에서는 방향키, `PageUp`/`PageDown`, `Home`/`End`로 이전 대화를 탐색하고 `q`로 돌아옵니다.
- Codex 네이티브 옵션과 서브커맨드는 그대로 전달됩니다.
- `--` 뒤의 값은 cxt 편의 옵션으로 변환하지 않습니다.
- tmux가 없으면 현재 터미널에서 Codex를 직접 실행하며 transcript 기능은 그대로 사용할 수 있습니다.
- tmux 안에서는 nested attach 대신 새 세션으로 client를 전환합니다.

세션 이름은 `codex-<현재 디렉터리>-<HHMMSS>` 형식이며 영문자, 숫자, `_`, `-` 이외의 문자는 `-`로 바뀝니다.

`Ctrl+T` transcript는 Codex의 네이티브 `tui.keymap.global.open_transcript` 설정을 cxt 실행에만 적용합니다. 사용자 전역 `~/.codex/config.toml`은 수정하지 않으며, 다른 키를 원하면 뒤에 네이티브 설정을 전달해 덮어쓸 수 있습니다. `Esc`는 Codex가 응답 중단과 이전 메시지 backtrack에 예약하므로 transcript 키로 지정할 수 없습니다.

```bash
cxt -c 'tui.keymap.global.open_transcript="alt-t"'
```

tmux로 시작한 새 cxt 창은 터미널 출력도 더 오래 볼 수 있도록 window 단위 `history-limit`을 50,000줄로 설정합니다. 사용자 전역 tmux 설정은 변경하지 않습니다. tmux가 없는 환경에서는 터미널 자체의 스크롤백 한도를 따르지만, `Ctrl+T` transcript는 저장된 Codex 대화를 별도로 보여줍니다.

## tmux 세션 관리

`cxt`가 예약한 `codex-` 접두사의 tmux 세션만 다시 연결하거나 종료할 수 있습니다. 세션 접두사는 유지되므로 이전 `cx`로 만든 세션도 계속 관리할 수 있습니다. 관리 옵션은 Codex 실행 옵션이나 프롬프트와 조합하지 않습니다.

| 동작 | 긴 옵션 | 짧은 옵션 | 대상을 생략했을 때 |
| --- | --- | --- | --- |
| 다시 연결 | `--attach` | `--at` | 가장 최근 cxt 세션 |
| 하나 종료 | `--kill-session` | `--ks` | 현재 cxt 세션, 없으면 가장 최근 cxt 세션 |
| 모두 종료 | `--kill-all` | `--ka` | 모든 cxt 세션 |

```bash
cxt --at
cxt --attach codex-my-project-142530
cxt --ks
cxt --kill-session codex-my-project-142530
cxt --ka
```

tmux 안에서 attach를 실행하면 nested attach 대신 해당 cxt 세션으로 client를 전환합니다. 세션 이름을 직접 지정할 때는 정확한 `codex-...` 이름만 허용하며, 일반 tmux 세션은 attach나 종료 대상이 되지 않습니다. `--ka`는 현재 cxt 세션을 마지막에 종료하므로 cxt 안에서도 다른 cxt 세션을 먼저 모두 닫을 수 있습니다.

설치 후 rc 파일을 다시 읽으면 attach와 단일 종료 대상도 탭으로 고를 수 있습니다. 후보는 현재 tmux 서버의 유효한 `codex-*` 세션만 실시간으로 표시하며 일반 tmux 세션은 노출하지 않습니다. 공백형과 `=`형을 모두 지원합니다.

```bash
cxt --at <Tab>
cxt --attach=<Tab>
cxt --ks <Tab>
cxt --kill-session=<Tab>
```

## 편의 옵션

현재 설치된 Codex가 노출하는 주요 모델을 짧게 선택할 수 있습니다.

| cxt 옵션 | Codex 변환 |
| --- | --- |
| `--sol` | `--model gpt-5.6-sol` |
| `--terra` | `--model gpt-5.6-terra` |
| `--luna` | `--model gpt-5.6-luna` |
| `--gpt55` | `--model gpt-5.5` |
| `--gpt54` | `--model gpt-5.4` |
| `--mini` | `--model gpt-5.4-mini` |
| `--spark` | `--model gpt-5.3-codex-spark` |

생각 레벨은 `--low`, `--medium`, `--high`, `--xhigh`, `--max`, `--ultra`를 지원하며 각각 `model_reasoning_effort` 설정으로 변환됩니다. 선택한 모델이 해당 레벨을 지원하지 않으면 Codex가 오류를 반환합니다.

권한 프리셋은 sandbox와 approval policy를 함께 설정합니다.

| cxt 옵션 | Sandbox | Approval |
| --- | --- | --- |
| `--safe` | `read-only` | `untrusted` |
| `--auto` | `workspace-write` | `on-request` |
| `--full-auto` | `workspace-write` | `never` |
| `--madmax` | 없음 (`--yolo`) | 없음 (`--yolo`) |

모델·생각 레벨·권한 프리셋은 각각 하나씩 조합할 수 있습니다.

```bash
cxt --sol --xhigh --auto "현재 프로젝트의 테스트를 수정해줘"
cxt --terra --low --safe review
cxt --mini --high --full-auto resume --last
```

같은 종류의 편의 옵션을 둘 이상 지정하면 모호한 실행을 막기 위해 종료 코드 `2`로 실패합니다. Codex 네이티브 옵션을 직접 사용할 수도 있습니다.

```bash
cxt --model custom-model \
  -c 'model_reasoning_effort="high"' \
  --sandbox workspace-write \
  --ask-for-approval on-request
```

전체 편의 옵션은 다음 명령으로 확인합니다.

```bash
cxt --cxt-help
```

## 유지보수

모델 slug, reasoning effort, sandbox 및 approval 옵션은 Codex 릴리스에 따라 바뀔 수 있습니다. `cxt` 편의 옵션은 2주마다, 그리고 Codex CLI를 업데이트한 직후 점검합니다.

검토 기준, 최신화 절차, 검증 명령과 Scheduled task용 프롬프트는 [MAINTENANCE.md](MAINTENANCE.md)에 있습니다. 향후 Codex가 `linux/cxt/`를 수정할 때는 가까운 [AGENTS.md](AGENTS.md)의 호환성 규칙을 우선 적용합니다.

## 테스트

테스트는 mock `codex`, mock `tmux`, 임시 `HOME`만 사용하며 실제 사용자 설정을 변경하지 않습니다.

```bash
./linux/cxt/tests/test-cxt.sh
```

ShellCheck가 설치되어 있으면 테스트 중 Bash 실행 스크립트와 completion을 자동으로 검사합니다.
