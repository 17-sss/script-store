# OMX Guard

macOS와 Linux에서 Oh My Codex(OMX)를 백업, 제거, 복구하기 위한 안전 중심의 CLI 스크립트입니다.

OMX를 단순히 삭제하는 데 그치지 않고, 설치 전 Codex 개인화 설정을 스냅샷으로 저장한 뒤 나중에 원래 상태로 복구할 수 있습니다.

## 구성 파일

```text
omx-guard.sh
smoke-test.sh
README.md
PRD.md
```

## 주요 기능

- 현재 OMX 설치 및 Codex 설정 상태 확인
- Codex 사용자 설정 스냅샷 생성
- OMX 전역 패키지, 실행 파일, MCP 등록, 상태 및 캐시 제거
- 설치 전에 존재하던 파일과 존재하지 않던 상태까지 복원
- 프로젝트별 `.omx` 및 `.codex` 선택 백업
- 스냅샷 목록 조회 및 삭제
- macOS와 Linux 지원을 목표로 설계
- NVM, fnm, Volta, Homebrew/Linuxbrew 및 일반적인 npm 전역 경로 탐색

## 요구 사항

- Bash 3.2 이상 (`set -u`가 활성화된 macOS 기본 Bash 포함)
- Python 3.8 이상
- Codex CLI는 선택 사항
- npm 및 Node 버전 관리자는 OMX 패키지 제거 시에만 관련됨

시스템 전역 경로에 root 권한으로 OMX를 설치한 경우 해당 파일 제거에 적절한 권한이 필요할 수 있습니다. 스크립트 자체를 무조건 `sudo`로 실행하는 것은 권장하지 않습니다.

## 설치

저장소 루트에서 바로 실행할 수 있습니다.

```bash
./linux/omx-guard/omx-guard.sh status
```

이 README가 있는 폴더에서는 다음처럼 실행합니다.

```bash
chmod +x omx-guard.sh
./omx-guard.sh status
```

전역 명령처럼 사용하려면:

```bash
mkdir -p ~/.local/bin
cp omx-guard.sh ~/.local/bin/omx-guard
chmod +x ~/.local/bin/omx-guard
```

`~/.local/bin`이 `PATH`에 포함되어 있어야 합니다.

## 권장 사용 흐름

### 1. OMX 설치 전 상태 저장

```bash
./omx-guard.sh snapshot pre-omx
```

프로젝트 설정도 저장하려면:

```bash
./omx-guard.sh snapshot pre-omx \
  --project ~/work/project-a \
  --project ~/work/project-b
```

### 2. OMX 설치 및 사용

OMX는 평소 방식대로 설치하고 사용합니다.

### 3. 설치 전 상태로 복구

```bash
./omx-guard.sh restore pre-omx
```

복구 직전 현재 상태도 `pre-restore` 스냅샷으로 자동 저장됩니다.

### 4. 현재 OMX 완전 제거

```bash
./omx-guard.sh remove
```

`remove`는 삭제 전에 `pre-remove` 스냅샷을 자동 생성합니다.

프로젝트의 `.omx`도 명시적으로 제거하려면:

```bash
./omx-guard.sh remove \
  --purge-project-state \
  --project ~/work/project-a
```

기본 동작에서는 프로젝트 로컬 `.omx`를 삭제하지 않습니다.

## 명령어

```text
omx-guard.sh status
omx-guard.sh snapshot [이름] [--project /path]...
omx-guard.sh list
omx-guard.sh remove [--purge-project-state] [--project /path]...
omx-guard.sh restore <스냅샷-ID|label|latest>
omx-guard.sh delete-snapshot <스냅샷-ID>
omx-guard.sh help
omx-guard.sh --version
```

### `status`

현재 운영체제, `HOME`, `CODEX_HOME`, OMX 실행 파일, 알려진 Node 관리 경로의 패키지 흔적, 주요 Codex 설정의 OMX 문자열 및 스냅샷 목록을 출력합니다.

```bash
./omx-guard.sh status
```

### `snapshot`

Codex 설정과 선택한 프로젝트 설정을 저장합니다.

```bash
./omx-guard.sh snapshot pre-omx
```

기본 백업 대상:

```text
$CODEX_HOME/config.toml
$CODEX_HOME/AGENTS.md
$CODEX_HOME/hooks.json
$CODEX_HOME/agents
$CODEX_HOME/prompts
$CODEX_HOME/skills
$CODEX_HOME/plugins
$CODEX_HOME/commands
$CODEX_HOME/rules
~/.omx
~/.agents/skills
~/.config/omx
~/.config/oh-my-codex
```

`--project`를 사용하면 해당 프로젝트의 다음 경로도 저장합니다.

```text
<project>/.omx
<project>/.codex
```

Codex 인증, 세션, 로그 및 명령 이력은 백업 대상에 포함하지 않습니다.

### `remove`

다음을 정리합니다.

- `oh-my-codex` 전역 패키지
- 알려진 NVM, fnm, Volta, Homebrew/Linuxbrew 및 npm 전역 경로의 OMX 실행 파일
- `[mcp_servers.omx_*]` TOML 섹션
- OMX marketplace 및 plugin 등록
- 삭제된 `node_modules/oh-my-codex` 경로 참조
- `~/.omx`
- `~/.config/omx`
- `~/.config/oh-my-codex`
- Codex plugin cache의 OMX 디렉터리

다음과 같은 값은 Codex 자체 기능 또는 사용자 설정일 수 있어 자동 삭제하지 않습니다.

```toml
multi_agent = true
max_threads = 4
max_depth = 2
```

이러한 애매한 설정까지 정확하게 되돌리려면 OMX 설치 전에 `snapshot`을 만든 뒤 `restore`를 사용해야 합니다.

Node 설치 경로는 다음 변형을 함께 확인합니다.

- NVM: `~/.nvm`, `$XDG_CONFIG_HOME/nvm`, `$NVM_DIR`
- fnm: `$XDG_DATA_HOME/fnm`, Linux 기본 경로, macOS `~/Library/Application Support/fnm`, `$FNM_DIR`
- Volta: `~/.volta`, `$VOLTA_HOME`
- npm: 현재 `npm prefix/root -g`, `~/.npm-global`, Homebrew, Linuxbrew 및 시스템 prefix

### `restore`

스냅샷에 기록된 각 경로를 설치 전 상태로 되돌립니다.

- 스냅샷에 존재했던 파일 및 디렉터리는 복원
- 스냅샷에 존재하지 않았던 경로는 제거
- 스냅샷 이후 새로 생긴 OMX 패키지와 실행 파일만 제거
- 스냅샷 당시 비활성 Node 버전에 있던 OMX 설치 경로는 보존
- 스냅샷 이후 처음 노출된 Node 관리자/npm 루트의 설치는 보존하고 경고
- 복구 전 현재 상태를 자동 백업
- 스냅샷의 `HOME` 및 `CODEX_HOME`과 현재 환경이 같은지 확인
- 복구 후 `config.toml` 문법 검사

OMX가 설치된 상태에서 만든 스냅샷을 복구하는 경우 당시 발견한 패키지와 실행 파일의 정확한 경로를 보존하지만, 패키지 내용이나 버전을 자동으로 되돌리지는 않습니다. 정확한 설치 경로 기록이 없는 2.1.0 이하 스냅샷은 데이터 손실을 피하기 위해 npm 패키지 및 실행 파일 제거를 건너뜁니다. 권장 용도는 OMX 설치 전 스냅샷 복구입니다.

## 스냅샷 위치

기본값:

```text
${XDG_STATE_HOME:-~/.local/state}/omx-guard/snapshots
```

별도 위치를 사용하려면:

```bash
export OMX_GUARD_STATE_HOME="$HOME/.omx-guard-state"
```

Codex 홈이 기본 경로가 아니라면:

```bash
export CODEX_HOME="/custom/path/.codex"
```

격리 테스트에서는 실제 홈과 Node 관리자 환경을 상속하지 않도록 모든 관련 경로와 `PATH`를 함께 교체합니다.

```bash
TMP_ROOT="$(mktemp -d)"
ISOLATED_BIN="$TMP_ROOT/bin"
mkdir -p "$ISOLATED_BIN"
for command_name in bash python3 uname mktemp rm mkdir grep basename; do
  ln -s "$(command -v "$command_name")" "$ISOLATED_BIN/$command_name"
done

export HOME="$TMP_ROOT/home"
export CODEX_HOME="$HOME/.codex"
export OMX_GUARD_STATE_HOME="$TMP_ROOT/state"
export OMX_GUARD_NPM_PREFIXES="$TMP_ROOT/npm-prefix"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export NVM_DIR="$HOME/.nvm"
export FNM_DIR="$XDG_DATA_HOME/fnm"
export VOLTA_HOME="$HOME/.volta"
export PATH="$ISOLATED_BIN"
```

`HOME`만 바꾸고 기존 `NVM_DIR`, `FNM_DIR`, `VOLTA_HOME`, XDG 변수 또는 `PATH`를 남겨두면 실제 사용자 설치 경로가 탐색될 수 있습니다. 가장 안전한 검증 방법은 제공된 `smoke-test.sh` 또는 읽기 전용으로 저장소를 마운트한 컨테이너를 사용하는 것입니다.

일반적인 실제 제거에서는 `OMX_GUARD_NPM_PREFIXES`를 설정하지 않아야 `/usr/local`, `/opt/homebrew`, `/home/linuxbrew/.linuxbrew`, `/usr`도 확인합니다.

스냅샷은 `umask 077`로 생성되어 현재 사용자 외의 접근을 제한합니다.

## 안전 설계

- `remove` 전에 자동 스냅샷 생성
- `restore` 전에 현재 상태 자동 스냅샷 생성
- 프로젝트 상태 삭제는 명시적인 옵션과 프로젝트 경로가 필요
- 개인 설정일 수 있는 legacy agent 옵션은 자동 삭제하지 않음
- 서로 다른 `HOME` 또는 `CODEX_HOME`으로 스냅샷 복구 차단
- 스냅샷 루트 밖 경로 선택 차단 및 manifest 복구 경로/payload 사전 검증
- 스냅샷 루트 바깥 경로를 `delete-snapshot`으로 삭제하지 못하도록 제한
- 실제 사용자 홈을 사용하는 테스트는 금지하고 임시 `HOME`으로 테스트 권장

## 검증

현재 버전은 다음 검증을 통과했습니다.

```bash
bash -n omx-guard.sh
./smoke-test.sh
```

격리된 Linux 임시 환경에서 다음 통합 흐름도 검증했습니다.

```text
스냅샷 생성
→ config/AGENTS/skills/project 설정 변조
→ OMX 상태 및 plugin 파일 생성
→ restore 실행
→ 기존 개인 설정 복구
→ 설치 전에 없었던 OMX 파일 제거
```

Bash 3.2 컨테이너에서는 프로젝트 인자 없는 `snapshot`, `restore`, `remove`와 macOS/Linux Node 관리자 경로를 함께 검증합니다. 실제 macOS 호스트 통합 테스트는 별도로 수행하는 것이 좋습니다.

## 버전

```bash
./omx-guard.sh --version
```

현재 스크립트 버전: `2.1.1`
