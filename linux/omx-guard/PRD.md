# OMX Guard PRD

## 1. 문서 정보

- 제품명: OMX Guard
- 유형: Bash 기반 로컬 CLI 유틸리티
- 버전: 2.1.1
- 대상 운영체제: macOS, Linux
- 주요 사용자: Codex CLI와 Oh My Codex(OMX)를 개인 또는 원격 개발 환경에서 사용하는 개발자

## 2. 배경

네이티브 `omx uninstall`과 npm 전역 패키지 삭제는 담당 범위가 다르다. 네이티브 제거기는 OMX가 관리하는 hooks, prompts, skills, agents 및 `AGENTS.md`를 소유권 기준으로 정리하지만 전역 npm 패키지 자체를 제거하지 않는다. 반대로 OMX Guard의 `remove`는 패키지, 실행 파일, 명백한 설정, 상태 및 캐시를 정리하지만 네이티브 관리 파일의 부분 삭제를 대체하지 않는다.

두 단계 중 하나만 실행하면 Codex 사용자 설정에 다음 흔적이 남을 수 있다.

- `mcp_servers.omx_*`
- OMX marketplace/plugin 등록
- 삭제된 `node_modules/oh-my-codex` 경로 참조
- `~/.omx` 상태
- Codex plugin cache
- 프로젝트 로컬 `.omx`
- OMX 설치 과정에서 변경된 `config.toml`, `AGENTS.md`, skills, hooks

단순 문자열 삭제로는 OMX 설치 전부터 사용자가 보유했던 개인화 설정과 OMX가 추가한 설정을 정확하게 구분하기 어렵다. 특히 `multi_agent`, `max_threads`, `max_depth` 같은 값은 OMX와 Codex 자체 기능이 모두 사용할 수 있어 소유권을 추론하여 지우면 데이터 손실 가능성이 있다.

## 3. 문제 정의

사용자는 다음 두 상황을 안전하게 처리할 수 있어야 한다.

1. 스냅샷, 네이티브 uninstall, Guard 후처리를 순서대로 실행하여 현재 설치된 OMX와 활성 설정 흔적을 제거한다.
2. OMX를 다시 설치하고 사용한 뒤, 설치 전의 개인화된 Codex 환경으로 되돌린다.

## 4. 목표

- OMX 설치 전 사용자 설정을 파일 단위로 보존한다.
- 네이티브 OMX 제거 전에 복구 지점을 만든다.
- `omx uninstall`이 관리하는 설정 자산과 Guard가 정리하는 패키지 및 상태의 책임 경계를 명확히 한다.
- OMX 관련 패키지, 실행 파일, MCP 설정, 상태와 캐시를 제거한다.
- 설치 전에 없던 파일까지 포함해 정확한 파일 존재 상태를 복원한다.
- macOS 및 Linux의 일반적인 Node 설치 환경을 지원한다.
- 실제 사용자 홈을 손상시키지 않는 테스트 방법을 제공한다.

## 5. 비목표

- Codex CLI 자체 제거
- Codex 인증 정보, 세션, 로그, 명령 이력 백업
- 임의의 사용자 TOML 설정을 OMX 소유로 추측해 삭제
- 네이티브 `omx uninstall` 대체
- 제3자 훅의 소유권을 추측하여 자동 삭제하거나 네이티브 uninstall의 fail-closed 검사를 우회
- OMX가 설치된 스냅샷의 npm 패키지 자동 재설치
- Windows 네이티브 환경 지원
- 프로젝트 전체 소스코드 백업
- 원격 서버 간 스냅샷 이동 및 경로 재매핑

## 6. 사용자 시나리오

### 시나리오 A: 현재 OMX 제거

1. 사용자가 `snapshot before-omx-uninstall`을 실행한다.
2. 사용자가 `omx uninstall --dry-run`으로 네이티브 제거 계획을 검증한다.
3. dry-run이 성공하면 `omx uninstall`로 OMX 관리 hooks, prompts, skills, agents 및 `AGENTS.md`를 제거한다.
4. 사용자가 `remove --no-snapshot`을 실행한다.
5. Guard는 알려진 OMX 패키지, 실행 파일, 명백한 설정, 상태 및 캐시를 제거한다.
6. 사용자가 Guard `status`로 최종 상태를 확인한다. 전역 패키지와 `omx` 실행 파일이 제거된 뒤에는 `omx doctor`를 실행할 수 없다.

### 시나리오 B: OMX 설치 전 환경 보존

1. 사용자가 OMX 설치 전에 `snapshot pre-omx`를 실행한다.
2. 도구는 개인화된 Codex 설정과 선택한 프로젝트 설정을 보관한다.
3. 사용자는 OMX를 설치하고 사용한다.

### 시나리오 C: 설치 전 상태로 복구

1. 사용자가 `restore pre-omx`를 실행한다.
2. 도구는 현재 상태를 `pre-restore`로 자동 저장한다.
3. 대상 스냅샷과 현재 `HOME`, `CODEX_HOME`이 같은지 검사한다.
4. 설치 전에 없던 OMX 파일과 디렉터리를 제거한다.
5. 설치 전에 존재했던 설정 파일과 디렉터리를 복원한다.
6. TOML 문법과 최종 상태를 확인한다.

OMX가 설치된 상태에서 만든 스냅샷으로 복구하려면 사용자가 manifest의 `omx.installed_version`을 확인하고 원래 패키지 관리자로 해당 버전을 먼저 재설치해야 한다. Guard는 npm 패키지 내용을 스냅샷하거나 자동 재설치하지 않는다.

### 시나리오 D: 프로젝트별 OMX 상태 관리

1. 사용자가 `--project`로 프로젝트를 명시한다.
2. 스냅샷은 `<project>/.omx`, `<project>/.codex`를 포함한다.
3. 프로젝트 `.omx` 삭제는 `--purge-project-state`가 있을 때만 수행한다.

### 시나리오 E: 네이티브 uninstall이 외부 훅 때문에 중단됨

1. `omx uninstall --dry-run`이 `Removing OMX hooks would shift a foreign coordinate or discard opaque metadata` 오류로 중단된다.
2. 사용자는 Guard snapshot이 이 검사를 우회하지 않는다는 안내를 확인한다.
3. 사용자는 `hooks.json`과 외부 도구 설정을 백업하고, 소유권이 명확한 제3자 훅을 해당 도구의 제거 절차로 정리한다.
4. 사용자는 `omx uninstall --dry-run`을 다시 실행한다.
5. dry-run이 성공한 뒤에만 시나리오 A의 실제 제거를 계속한다.

## 7. 기능 요구사항

### FR-1 상태 확인

`status`는 다음을 출력해야 한다.

- 운영체제
- `HOME`
- `CODEX_HOME`
- 스냅샷 저장소
- 현재 `omx` 명령 경로
- 알려진 Node 관리 경로의 OMX 패키지 및 바이너리 흔적
- 주요 Codex 설정의 OMX 문자열
- 자동 삭제하지 않은 legacy agent 옵션
- 스냅샷 목록

### FR-2 스냅샷 생성

`snapshot [label]`은 다음을 수행해야 한다.

- 타임스탬프가 포함된 고유 스냅샷 ID 생성
- 각 추적 경로의 존재 여부 저장
- 파일, 디렉터리, 심볼릭 링크를 구분하여 복사
- 플랫폼, 홈 경로, Codex 홈, OMX 설치 여부를 manifest에 저장
- 활성 여부와 관계없이 발견한 OMX 패키지 및 실행 파일의 정확한 경로를 manifest에 저장
- `--project`를 반복해서 받을 수 있음
- 백업 권한은 현재 사용자에게 제한

### FR-3 네이티브 제거 후 Guard 정리

`remove`는 다음을 수행해야 한다.

- 기본적으로 제거 전 스냅샷 생성
- NVM, fnm, Volta, Homebrew/Linuxbrew 및 일반적인 npm 전역 경로 탐색
- `oh-my-codex` 패키지와 연관된 `omx` 실행 파일 제거
- TOML의 명백한 OMX 섹션 제거
- OMX 전용 주석 및 삭제된 패키지 경로 참조 제거
- OMX 상태 및 plugin cache 제거
- `multi_agent`, `max_threads`, `max_depth`는 자동 삭제하지 않음
- 프로젝트 `.omx`는 명시적 옵션 없이는 제거하지 않음
- 명명된 제거 전 스냅샷이 이미 있는 경우 `--no-snapshot`으로 중복 스냅샷 생성을 생략할 수 있음

`remove`는 다음을 수행하지 않는다.

- `$CODEX_HOME/hooks.json`에서 OMX 관리 훅의 소유권 기반 부분 삭제
- OMX가 설치한 prompts, skills, agents 및 `AGENTS.md`의 소유권 기반 부분 삭제
- 제3자 훅 제거 또는 네이티브 uninstall 안전 검사 우회

현재 설치를 완전히 제거하는 문서 흐름은 `snapshot` → `omx uninstall --dry-run` → `omx uninstall` → `remove --no-snapshot` 순서를 사용해야 한다.

### FR-4 복구

`restore <id|label|latest>`는 다음을 수행해야 한다.

- 복구 전 현재 상태 자동 스냅샷
- 스냅샷 환경과 현재 환경의 경로 일치 검증
- 스냅샷의 `existed=false` 경로는 현재 환경에서 제거
- 스냅샷의 `existed=true` 경로는 보관본으로 완전 교체
- 복구 후 TOML 문법 검사
- 스냅샷 이후 새로 발견된 OMX 패키지 및 실행 파일만 제거
- 스냅샷 당시 비활성 Node 버전에 존재하던 OMX 설치 경로 보존
- 스냅샷과 현재 실행에서 공통으로 탐색한 루트 안의 신규 경로만 제거
- 스냅샷 이후 처음 노출된 탐색 루트의 경로는 보존하고 경고
- 정확한 설치 경로가 없는 이전 manifest에서는 npm 패키지 제거를 보수적으로 건너뜀
- OMX 설치 스냅샷의 패키지 내용이나 버전은 자동 복원하지 않음
- OMX 설치 스냅샷 복구 절차는 manifest 버전 재설치 → `restore` → `omx doctor` 순서를 안내

### FR-5 스냅샷 관리

- `list`: 사용 가능한 스냅샷 ID, OMX 설치 여부, 생성 시각 출력
- `delete-snapshot`: 스냅샷 루트 내부의 정확한 대상만 삭제
- `latest`: 가장 최근 스냅샷 선택
- 동일 label은 가장 최근 스냅샷 선택

### FR-6 네이티브 uninstall 연계 안내

문서는 다음을 명시해야 한다.

- Guard는 `omx uninstall`의 대체제가 아님
- 실제 제거 전에 `omx uninstall --dry-run` 사용
- 외부 훅 좌표 또는 불투명 메타데이터 오류는 Guard snapshot 실패가 아니라 네이티브 fail-closed 결과
- 외부 훅은 출처와 소유권을 확인한 뒤 해당 도구의 제거 절차로 정리
- 네이티브 uninstall 성공 후 Guard `remove`로 패키지와 상태를 후처리

## 8. 비기능 요구사항

### NFR-1 안전성

- Bash strict mode 사용
- 스냅샷 파일 권한 제한
- 삭제 전에 복구 지점 생성
- 네이티브 uninstall의 외부 훅 소유권 검사를 우회하지 않음
- 제3자 훅은 문자열 일치만으로 자동 삭제하지 않음
- 프로젝트 삭제는 명시적 선택
- 다른 홈 환경으로 복구 차단
- 사용자의 Codex 인증/세션 데이터는 다루지 않음

### NFR-2 이식성

- macOS 기본 Bash 3.2와 일반 Linux Bash에서 `nounset` 빈 인자 오류 없이 실행 가능해야 함
- Python 3.8 이상 사용
- GNU 전용 `readlink -f`, `sed -i`, `mapfile`에 의존하지 않음
- 경로 처리는 Python `pathlib`을 우선 사용

### NFR-3 관찰 가능성

- 각 단계의 시작과 결과 출력
- 제거한 경로 출력
- 남은 설정과 수동 검토 대상 경고
- 버전 출력 지원

### NFR-4 성능

- 사용자 전체 홈을 무제한 탐색하지 않음
- 사전에 정의된 설정과 패키지 경로만 처리
- npm 명령은 중단된 환경에서 무한 대기하지 않도록 제한

## 9. 데이터 모델

스냅샷 디렉터리:

```text
<state-root>/snapshots/<snapshot-id>/
├── manifest.json
└── payload/
    ├── entry-000
    ├── entry-001
    └── ...
```

manifest 주요 필드:

```json
{
  "format_version": 1,
  "snapshot_id": "20260719-120000-pre-omx",
  "created_at": "ISO-8601",
  "label": "pre-omx",
  "home": "/Users/example",
  "codex_home": "/Users/example/.codex",
  "projects": [],
  "omx": {
    "command_path": null,
    "installed": false,
    "installed_version": null,
    "npm_prefix": null,
    "discovery": {
      "schema_version": 1,
      "active_command": null,
      "packages": [],
      "binary_only": [],
      "removable_paths": [],
      "scan_roots": [],
      "path_roots": {}
    }
  },
  "entries": [
    {
      "path": "/Users/example/.codex/config.toml",
      "existed": true,
      "archive_name": "entry-000",
      "kind": "file"
    }
  ]
}
```

## 10. 수용 기준

- `bash -n omx-guard.sh`가 성공한다.
- 빈 임시 `HOME`에서도 `status`, `snapshot`, `list`가 실패하지 않는다.
- 개인 설정을 스냅샷한 뒤 파일을 변조하고 `restore`하면 원본 내용이 복원된다.
- 스냅샷 당시 없던 OMX 파일은 `restore` 후 제거된다.
- 스냅샷 당시 비활성 Node 버전에 있던 OMX 설치는 `restore` 후 보존된다.
- OMX와 무관한 동명의 `omx` 실행 파일은 제거하지 않는다.
- 로컬 소스 체크아웃의 `node_modules/oh-my-codex`는 전역 탐색 루트 밖이면 제거하지 않는다.
- 스냅샷 이후 처음 노출된 Node 관리자/npm 루트의 설치는 제거하지 않는다.
- 프로젝트를 지정한 스냅샷은 프로젝트 `.codex`를 복원하고 `.omx` 존재 상태를 되돌린다.
- `remove`는 명백한 `mcp_servers.omx_*`를 제거하지만 개인 MCP 설정은 보존한다.
- `remove`는 legacy agent 옵션을 자동 삭제하지 않는다.
- 문서는 `remove` 단독 실행을 완전 제거로 설명하지 않는다.
- 문서는 `snapshot` → `omx uninstall --dry-run` → `omx uninstall` → `remove --no-snapshot` 순서를 제공한다.
- 외부 훅 좌표 오류 발생 시 snapshot이 검사를 우회하지 않으며 제3자 훅 소유권을 먼저 확인하도록 안내한다.
- OMX 설치 스냅샷 복구 시 기록된 버전의 패키지를 먼저 재설치하도록 안내한다.
- 서로 다른 `HOME`으로 복구를 시도하면 중단된다.
- 스냅샷 루트 밖 경로나 변조된 manifest의 허용되지 않은 복구 경로는 거부된다.
- 스냅샷 루트 바깥 경로는 `delete-snapshot`으로 삭제할 수 없다.
- 실제 사용자 홈이 아닌 임시 환경에서 통합 테스트가 수행된다.
- 프로젝트 경로를 지정하지 않은 `snapshot`, `restore`, `remove`가 Bash 3.2에서 성공한다.
- NVM/fnm/Volta의 기본, XDG, macOS 및 사용자 지정 홈 경로를 탐색한다.

## 11. 테스트 계획

### 정적 검사

```bash
bash -n omx-guard.sh
```

가능한 경우:

```bash
shellcheck omx-guard.sh
```

### 격리 통합 테스트

테스트 전용 임시 경로를 사용한다.

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

테스트 `PATH`에서는 실제 `npm`과 `omx`를 노출하지 않는다.

검증 흐름:

1. 개인 `config.toml`, `AGENTS.md`, skill, 프로젝트 `.codex` 생성
2. `snapshot pre-omx --project ...`
3. 개인 설정 변조
4. `.omx`, plugin 파일 및 OMX MCP 설정 생성
5. `restore pre-omx`
6. 원본 개인 설정 복원 확인
7. 스냅샷 당시 없던 OMX 파일 제거 확인
8. 변조된 manifest가 스냅샷 추적 대상 밖의 파일을 삭제하지 못하는지 확인
9. Bash 3.2에서 프로젝트 인자 없는 `snapshot`, `restore`, `remove` 확인
10. Linux/macOS의 NVM, fnm, Volta 및 npm prefix 변형 제거 확인
11. 스냅샷 당시 비활성 OMX 설치 및 무관한 동명 실행 파일 보존 확인
12. 새로 노출된 탐색 루트와 로컬 소스 체크아웃 보존 확인

문서 검증:

13. `remove`를 네이티브 uninstall의 대체제로 표현하지 않는지 확인
14. 권장 제거 순서와 `--no-snapshot`의 목적이 README와 PRD에서 일치하는지 확인
15. 외부 훅 fail-closed 오류와 설치된 상태의 스냅샷 복구 제한이 문서화됐는지 확인

## 12. 향후 개선 후보

- `--dry-run`
- 스냅샷 압축 및 암호화
- 스냅샷 보존 개수 정책
- `doctor` 형식의 상세 진단
- Homebrew 또는 패키지 매니저 설치 지원
- CI 기반 macOS/Linux 행렬 테스트
- OMX 버전별 설정 소유권 manifest
- 네이티브 `omx uninstall` dry-run 결과를 읽기 전용으로 요약하는 보조 명령
- 외부 훅 소유권 충돌 진단 개선
- 복구 전 diff 미리보기
