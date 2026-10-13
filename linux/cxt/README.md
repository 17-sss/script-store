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

같은 저장소 경로에서 업데이트하면 실행 파일은 심볼릭 링크를 통해 바로 반영됩니다. 이미 열린 셸의 completion은 rc 파일을 다시 읽어 갱신합니다. 저장소 위치나 설치할 셸이 바뀌면 설치기를 다시 실행합니다. 설치기는 Codex 설정이나 별도 프로필을 생성·수정하지 않습니다.

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
cxt --astra --high --auto
cxt --sol --high --auto
cxt --terra --medium --safe
cxt --luna --max --full-auto
cxt --sol --ultra --madmax
cxt resume --last
cxt --at
cxt --ks
```

- 모든 실행에는 `--no-alt-screen`이 기본으로 추가됩니다.
- transcript 키는 Codex 사용자 설정을 따릅니다. cxt는 키 바인딩을 강제하지 않습니다.
- Codex 네이티브 옵션과 서브커맨드는 그대로 전달됩니다.
- `--` 뒤의 값은 cxt 편의 옵션으로 변환하지 않습니다.
- tmux가 없으면 현재 터미널에서 Codex를 직접 실행하며 transcript 기능은 그대로 사용할 수 있습니다.
- tmux 안에서는 nested attach 대신 새 세션으로 client를 전환합니다.

세션 이름은 `codex-<현재 디렉터리>-<HHMMSS>` 형식이며 영문자, 숫자, `_`, `-` 이외의 문자는 `-`로 바뀝니다.

### 공유 서버와 transcript 키

기본 `cxt`는 `--no-alt-screen`만 추가하며, Codex의 공유 백그라운드 서버 사용을 막는 설정 override를 주입하지 않습니다. tmux가 없는 직접 실행에도 같은 정책을 적용합니다. 공유 서버 연결 여부는 Codex의 설정과 실행 상태에 따릅니다.

Codex `0.162.1`에서는 `-c`, `--enable`, `--disable`, `--search`를 사용하면 embedded mode로 실행되고 공유 서버를 사용하지 않는다는 경고가 나올 수 있습니다. `--high` 같은 cxt 생각 레벨 옵션도 `-c model_reasoning_effort=...`로 변환되므로 이 제약을 따릅니다. cxt는 경고를 숨기거나 `--no-daemon`을 자동 추가하지 않습니다. 직접 실행과 embedded mode에서도 tmux 세션 관리와 스크롤백은 유지됩니다.

`Ctrl+T`로 transcript를 열려면 사용자가 `${CODEX_HOME:-$HOME/.codex}/config.toml`의 기존 `tui.keymap.global` 설정에 다음 항목을 추가할 수 있습니다. 이미 같은 TOML 테이블이 있으면 중복 테이블을 만들지 않고 기존 항목을 편집합니다. 이 설정은 일반 `codex`에도 적용됩니다. 설치기는 해당 파일을 변경하지 않습니다. [공식 키맵 설정 문서](https://learn.chatgpt.com/docs/config-file/config-basic#tui-keymap)를 참고합니다.

```toml
[tui.keymap.global]
open_transcript = "ctrl-t"
```

transcript 화면에서는 방향키, `PageUp`/`PageDown`, `Home`/`End`로 이전 대화를 탐색하고 `q`로 돌아옵니다. 한 번만 다른 키를 지정하려면 네이티브 override를 전달할 수 있으며, 이 경우 공유 서버 제약이 적용됩니다.

```bash
cxt -c 'tui.keymap.global.open_transcript="alt-t"'
```

tmux로 시작한 새 cxt 창은 터미널 출력도 더 오래 볼 수 있도록 첫 Codex pane을 만들기 전에 window 단위 `history-limit`을 50,000줄로 설정합니다. 사용자 전역 tmux 설정은 변경하지 않습니다. tmux가 없는 환경에서는 터미널 자체의 스크롤백 한도를 따르며, Codex transcript는 설정한 키로 별도로 열 수 있습니다.

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
| `--astra` | `--model gpt-6-astra` |
| `--sol` | `--model gpt-6.1-sol` |
| `--terra` | `--model gpt-5.6-terra` |
| `--luna` | `--model gpt-6-luna` |

2026-10-14 검토부터 `--sol`과 `--luna`는 위 모델을 선택합니다. 이전 모델을 원하면 `--model gpt-5.6-sol` 또는 `--model gpt-5.6-luna`를 직접 사용합니다.

`--gpt55`와 `--spark`는 현재 list-visible 카탈로그에 모델이 없으므로 종료 코드 `2`와 이전 안내를 반환하고 completion·도움말에서 제외합니다. 해당 모델이 노출되는 계정에서는 `--model gpt-5.5` 또는 `--model gpt-5.3-codex-spark`를 직접 지정할 수 있습니다. 이는 모델의 전역 서비스 종료를 뜻하지 않습니다.

현재 list-visible 모델 카탈로그에서 빠진 `--gpt54` 별칭은 더 이상 안내하지 않으며, 사용하면 종료 코드 `2`와 마이그레이션 안내를 반환합니다. 계정에서 `gpt-5.4`를 계속 노출한다면 Codex 네이티브 옵션 `--model gpt-5.4`를 직접 사용할 수 있습니다.

`--mini`도 현재 검토한 카탈로그에서 `gpt-5.4-mini`가 list-visible이 아니므로 종료 코드 `2`와 안내를 반환합니다. `--luna`를 사용하거나, 해당 모델이 노출되는 계정에서는 `--model gpt-5.4-mini`를 직접 지정할 수 있습니다. 이는 모델의 전역 서비스 종료를 뜻하지 않습니다.

생각 레벨은 `--low`, `--medium`, `--high`, `--xhigh`, `--max`, `--ultra`를 지원하며 각각 `model_reasoning_effort` 설정으로 변환됩니다. 선택한 모델이 해당 레벨을 지원하지 않으면 Codex가 오류를 반환합니다. 현재 Luna는 `max`까지 지원하며 `ultra`는 지원하지 않습니다.

권한 프리셋은 sandbox와 approval policy를 함께 설정합니다.

| cxt 옵션 | Sandbox | Approval |
| --- | --- | --- |
| `--safe` | `read-only` | `on-request` |
| `--auto` | `workspace-write` | `on-request` |
| `--full-auto` | `workspace-write` | `never` |
| `--madmax` | 없음 (`--yolo`) | 없음 (`--yolo`) |

모델·생각 레벨·권한 프리셋은 각각 하나씩 조합할 수 있습니다.

```bash
cxt --sol --xhigh --auto "현재 프로젝트의 테스트를 수정해줘"
cxt --terra --low --safe review
cxt --luna --high --full-auto resume --last
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

macOS처럼 `TMPDIR`가 `/`로 끝나거나 심볼릭 링크를 포함해도 테스트는 물리 경로를
기준으로 비교합니다. Linux에서도 `TMPDIR=/tmp/ ./linux/cxt/tests/test-cxt.sh`로
같은 경로 조건을 검증할 수 있습니다(저장소 루트 기준).
