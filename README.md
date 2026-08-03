# script-store

반복해서 쓰는 개발 환경 작업을 작고 독립적인 스크립트로 모아 둔 저장소입니다. Linux/macOS용 셸 도구와 Windows PowerShell 도구를 운영체제별로 구분하며, 각 도구는 별도 패키지 설치 없이 해당 폴더에서 바로 실행하는 것을 기본으로 합니다.

> 일부 스크립트는 셸 설정, Codex 세션, cron, 방화벽처럼 사용자 환경을 변경합니다. 실행 전 각 도구의 상세 문서와 주의사항을 확인하세요.

## 한눈에 보기

| 환경 | 도구 | 이런 때 사용합니다 | 바로가기 |
| --- | --- | --- | --- |
| Linux | **agent-heartbeat** | Claude, Codex 같은 터미널 에이전트에 cron으로 주기적인 메시지를 보낼 때 | [상세 문서](linux/agent-heartbeat/README.md) |
| Linux | **codex-session-manager** | 로컬 Codex 세션을 TUI에서 찾고 보관·복구·격리할 때 | [상세 문서](linux/codex-session-manager/README.md) |
| Linux | **cxt** | 현재 프로젝트 전용 tmux 세션에서 Codex를 빠르게 실행할 때 | [상세 문서](linux/cxt/README.md) |
| Linux / macOS | **OMX Guard** | Oh My Codex 설정을 백업하고 안전하게 제거·복구할 때 | [상세 문서](linux/omx-guard/README.md) |
| Windows | **devtunnel** | 원격 개발 서버의 포트를 SSH 터널로 Windows localhost에 연결할 때 | [상세 문서](windows/devtunnel/README.md) |
| Windows + WSL | **wsl-portproxy** | WSL 개발 서버를 Windows 또는 LAN에 노출하거나 기존 규칙을 정리할 때 | [상세 문서](windows/wsl-portproxy/README.md) |

## 저장소 구조

```text
script-store/
├── linux/
│   ├── agent-heartbeat/       # 에이전트 주기 메시지 전송
│   ├── codex-session-manager/ # Codex 로컬 세션 관리 TUI
│   ├── cxt/                    # Codex tmux 실행 명령
│   └── omx-guard/             # OMX 백업·제거·복구
├── windows/
│   ├── devtunnel/             # SSH 로컬 포트 포워딩 도우미
│   └── wsl-portproxy/         # Windows ↔ WSL portproxy 관리
└── docs/                      # 프로젝트 인수인계 문서
```

## Linux / macOS 스크립트

### agent-heartbeat

`crontab`을 이용해 정해진 시간마다 tmux pane, CLI 명령 또는 파일로 메시지를 보내는 Linux 유틸리티입니다. 기본 스케줄은 매일 `08:00`, `13:00`, `18:00`, `23:00`이며 설정 파일에서 바꿀 수 있습니다.

지원하는 전송 방식:

- `tmux`: 실행 중인 에이전트 pane에 메시지를 입력하고 선택적으로 Enter까지 전송
- `command`: `AGENT_TARGET`, `AGENT_MESSAGE` 환경 변수와 함께 임의 명령 실행
- `file`: 메시지를 파일 끝에 추가해 로깅이나 안전한 테스트에 사용

빠른 시작:

```bash
cd linux/agent-heartbeat
./agent-heartbeat.sh init-config
./agent-heartbeat.sh run --dry-run
./agent-heartbeat.sh install
```

| 파일 | 역할 |
| --- | --- |
| `agent-heartbeat.sh` | 설정 생성, 메시지 전송, cron 미리보기·설치·제거를 담당하는 메인 스크립트 |
| `agent-heartbeat.ini.example` | target과 실행 주기를 정의하는 설정 예시 |
| `smoke-test.sh` | 실제 crontab이나 tmux를 건드리지 않고 설정 파싱과 전송 결과를 검증 |

요구 사항은 Bash, `cron`/`crontab`이며 tmux target을 쓸 때는 tmux가 추가로 필요합니다. 설정 방법과 Claude CLI 예시는 [agent-heartbeat README](linux/agent-heartbeat/README.md)를 참고하세요.

### codex-session-manager

`~/.codex/sessions`와 `~/.codex/archived_sessions`의 로컬 transcript를 읽어 Codex 세션을 탐색하고 관리하는 의존성 없는 TUI입니다. 현재 폴더 또는 전체 폴더 범위에서 검색할 수 있고, 여러 세션을 선택해 한 번에 처리할 수 있습니다.

주요 기능:

- active/archived 세션 목록 전환, 검색, 다중 선택
- Codex CLI를 통한 세션 재개·보관·보관취소
- 기본 삭제 동작 대신 manifest가 남는 격리(quarantine) 제공
- `--force`를 명시한 경우에만 영구 삭제 허용
- 파일명과 transcript의 UUID를 교차 검증해 잘못된 대상 변경 차단
- 자동화에 사용할 수 있는 텍스트·JSON 목록 출력

빠른 시작:

```bash
./linux/codex-session-manager/codex-session-manager.js

# TUI 없이 전체 세션을 JSON으로 조회
./linux/codex-session-manager/codex-session-manager.js --list all --json --all
```

| 파일 | 역할 |
| --- | --- |
| `codex-session-manager.js` | 세션 목록 TUI, 비대화형 조회, 보관·격리·삭제 작업을 제공하는 메인 스크립트 |
| `smoke-test.sh` | 임시 HOME과 가짜 Codex CLI를 사용해 조회 및 변경 작업의 안전성을 검증 |

Node.js와 `PATH`에서 실행 가능한 Codex CLI가 필요하며 `fzf`나 npm 설치는 필요하지 않습니다. 단축키와 격리 복구 절차는 [codex-session-manager README](linux/codex-session-manager/README.md)에 정리되어 있습니다.

### cxt

현재 디렉터리 이름을 기준으로 새 tmux 세션을 만들고 Codex를 실행하는 Bash/Zsh 공용 명령입니다. tmux가 없으면 현재 터미널에서 Codex를 직접 실행합니다.

```bash
./linux/cxt/install-cxt.sh
source ~/.zshrc

cxt
cxt --xhigh
cxt --madmax
cxt resume --last
cxt --at <Tab>
```

- 모든 실행에 `--no-alt-screen`을 기본 적용합니다.
- `--xhigh`를 Codex의 최고 추론 강도 설정으로 변환합니다.
- `--madmax`를 `--yolo`로 변환합니다. 승인과 sandbox를 우회하므로 신뢰할 수 있는 작업에서만 사용하세요.
- tmux 안에서 실행하면 중첩 attach 대신 새 세션으로 현재 client를 전환합니다.
- `--at`/`--attach`와 `--ks`/`--kill-session` 뒤에서 유효한 `codex-*` tmux 세션만 탭 완성합니다.

| 파일 | 역할 |
| --- | --- |
| `bin/cxt` | tmux 세션을 만들고 인자를 변환해 Codex를 실행하는 본체 |
| `completions/` | Bash/Zsh에서 cxt 세션과 편의 옵션을 탭 완성 |
| `install-cxt.sh` | 심볼릭 링크와 필요한 PATH·completion marker를 설치·제거 |
| `tests/test-cxt.sh` | mock Codex/tmux와 임시 HOME으로 실행·설치 동작을 검증 |

Codex CLI가 필수이며 tmux는 선택 사항입니다. 설치 옵션과 정확한 인자 전달 규칙은 [cxt README](linux/cxt/README.md)를 참고하세요.

### OMX Guard

Oh My Codex(OMX) 설치 전후의 Codex 설정을 스냅샷으로 남기고, 네이티브 제거 후 남은 패키지·실행 파일·상태·캐시를 정리하거나 이전 상태로 복구하는 Linux/macOS 도구입니다.

OMX Guard는 `omx uninstall`을 대체하지 않습니다. 완전 제거 시에는 OMX가 관리하는 hooks, prompts, skills, agents 등을 먼저 네이티브 명령으로 정리한 뒤 Guard를 후처리에 사용합니다.

```bash
# 현재 상태 확인
./linux/omx-guard/omx-guard.sh status

# OMX 설치 전 복구 지점 생성
./linux/omx-guard/omx-guard.sh snapshot pre-omx

# 저장한 상태로 복구
./linux/omx-guard/omx-guard.sh restore pre-omx
```

현재 OMX를 제거하는 권장 흐름:

```bash
./linux/omx-guard/omx-guard.sh snapshot before-omx-uninstall
omx uninstall --dry-run
omx uninstall
./linux/omx-guard/omx-guard.sh remove --no-snapshot
```

| 파일 | 역할 |
| --- | --- |
| `omx-guard.sh` | 상태 확인, 스냅샷 생성·조회·삭제, OMX 후처리 제거, 복구를 담당하는 메인 스크립트 |
| `smoke-test.sh` | 격리된 HOME·CODEX_HOME·Node 관리자 경로에서 백업/변경/복구 흐름을 검증 |
| `PRD.md` | 도구의 요구 사항, 범위, 안전 원칙을 기록한 제품 요구 문서 |

Bash 3.2 이상과 Python 3.8 이상이 필요합니다. `remove`와 `restore`는 실제 설정을 변경할 수 있으므로 먼저 [OMX Guard README](linux/omx-guard/README.md)의 백업 범위와 안전 설계를 확인하세요.

## Windows 스크립트

### devtunnel

원격 개발 서버에서 실행 중인 웹 서버를 Windows 브라우저의 `localhost`로 연결하는 PowerShell 도구입니다. 설치 스크립트가 `$PROFILE`에 `devtunnel` 함수를 추가하며, SSH host alias와 포트는 실행할 때 지정합니다.

```powershell
cd windows\devtunnel
.\devtunnel-manager.ps1 install
. $PROFILE

devtunnel 3123 prox-dev-hoyoung
devtunnel 3000,5173,6006 prox-dev-hoyoung
```

내부적으로 각 포트에 대해 `ssh -N -L <port>:127.0.0.1:<port> <alias>` 형태의 로컬 포워딩을 구성합니다. SSH config는 생성하거나 수정하지 않습니다.

| 파일 | 역할 |
| --- | --- |
| `devtunnel-manager.ps1` | PowerShell profile에 `devtunnel` 함수를 설치·재설치·제거 |
| `smoke-test.ps1` | 임시 profile에서 설치, 도움말, SSH 인자 생성, 제거 흐름을 검증 |

Windows PowerShell과 OpenSSH client가 필요합니다. 설치 후 profile 반영, 실행 정책, 포트 충돌 해결은 [devtunnel README](windows/devtunnel/README.md)를 참고하세요.

### wsl-portproxy

WSL에서 실행 중인 개발 서버를 Windows 또는 같은 네트워크의 다른 기기에 노출하기 위한 PowerShell 스크립트입니다. Windows의 `netsh interface portproxy` 규칙과 해당 방화벽 허용 규칙을 함께 관리합니다.

관리자 PowerShell에서 실행하세요.

```powershell
# Windows 0.0.0.0:5173 → WSL_IP:5173 연결
.\windows\wsl-portproxy\setup.ps1 -Port 5173

# portproxy와 관련 방화벽 규칙 제거
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173
```

| 파일 | 역할 |
| --- | --- |
| `setup.ps1` | 현재 WSL IP를 찾아 지정 포트의 portproxy와 inbound 방화벽 규칙을 생성 |
| `uninstall.ps1` | 지정 포트의 portproxy 및 현재·레거시 방화벽 규칙을 제거 |

Windows, WSL, 관리자 권한이 필요합니다. `devtunnel`과 같은 포트를 함께 사용하면 바인딩 충돌이 날 수 있으므로 [wsl-portproxy README](windows/wsl-portproxy/README.md)의 확인 및 문제 해결 절차를 참고하세요.

## 테스트

Linux 도구는 각 폴더의 스모크 테스트를 직접 실행할 수 있습니다.

```bash
./linux/agent-heartbeat/smoke-test.sh
./linux/codex-session-manager/smoke-test.sh
./linux/cxt/tests/test-cxt.sh
./linux/omx-guard/smoke-test.sh
```

Windows의 `devtunnel` 테스트는 PowerShell에서 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\devtunnel\smoke-test.ps1
```

각 스모크 테스트는 가능한 한 임시 디렉터리와 mock 명령을 사용해 실제 사용자 설정을 변경하지 않도록 구성되어 있습니다. `wsl-portproxy`는 Windows 네트워크 설정을 직접 변경하는 도구이므로 별도 자동 테스트가 없으며, 실행 전 현재 규칙을 확인하는 것이 좋습니다.

```powershell
netsh interface portproxy show all
```

## 새 스크립트 추가 원칙

새 도구는 운영체제 폴더 아래에 독립된 디렉터리로 추가합니다.

- 사용 목적과 요구 사항, 설치·제거 방법을 해당 폴더의 `README.md`에 기록합니다.
- 사용자 환경을 바꾸는 작업은 가능한 경우 `--dry-run` 또는 격리된 스모크 테스트를 제공합니다.
- 스크립트가 관리하는 설정 범위를 marker나 명시적인 경로로 제한합니다.
- 새 도구를 추가하면 이 README의 요약 표와 파일 설명도 함께 갱신합니다.
