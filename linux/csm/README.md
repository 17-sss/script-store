# csm

Codex 로컬 세션을 TUI에서 찾고, 선택해서 보관/보관취소/격리/영구 삭제하는 도구입니다.

Codex CLI는 `resume`, `archive`, `delete`, `unarchive`는 제공하지만, 현재 로컬 active/archived 세션을 한 번에 사람이 보기 좋게 출력하는 `list` 명령은 없습니다. 이 스크립트는 로컬 transcript 파일을 읽어서 목록을 보여줍니다. 보관/보관취소는 공식 `codex` CLI에 위임하고, 삭제는 다른 세션으로 연쇄되지 않도록 선택한 transcript 파일만 정확히 처리합니다.

## Requirements

- Node.js
- `PATH`에서 실행 가능한 Codex CLI

`fzf`, npm package, 설치 단계는 필요 없습니다.

## Quick Start

설치해서 어느 폴더에서나 `csm` 명령으로 실행하려면 저장소 루트에서 다음을 실행합니다.

```bash
./linux/csm/install-csm.sh
source ~/.zshrc # zsh
# source ~/.bashrc # bash
```

설치기는 이 저장소의 `bin/csm`을 `~/.local/bin/csm`에 절대 심볼릭 링크합니다. `~/.local/bin`이 현재 `PATH`와 선택한 rc 파일 어디에도 없을 때만 관리되는 PATH 블록을 추가합니다. 사용자 파일이나 다른 대상을 가리키는 링크가 이미 있으면 덮어쓰지 않고 중단합니다.

설치 변경을 미리 보거나 제거할 수 있습니다.

```bash
./linux/csm/install-csm.sh --dry-run
./linux/csm/install-csm.sh --uninstall
```

`--shell bash|zsh`와 `--rc-file PATH`도 지원합니다. 제거 시에는 설치기가 만든 정확한 링크와 수정되지 않은 PATH 블록만 제거합니다.

이 README가 있는 폴더에서 실행:

```bash
./bin/csm
```

repo 루트에서 실행:

```bash
./linux/csm/bin/csm
```

기본 화면은 **현재 실행한 폴더와 그 하위 폴더에서 열린 Codex 세션**만 보여줍니다. 전체 로컬 세션을 보고 싶으면 TUI 안에서 `a`를 누르세요.

목록 제목은 Codex에서 rename한 세션 이름을 우선 표시합니다. 이름이 없으면 초기 prompt를 대신 표시하며, 하단 상세에는 rename 이름과 초기 prompt를 모두 표시합니다.

## 화면 읽는 법

상단 상태줄은 이런 형태입니다.

```txt
csm | View: active | Scope: current folder | Marked: 0 | Sessions: 3
```

- `View`: `active`는 일반 세션, `archived`는 아카이브된 세션입니다.
- `Scope`: `current folder`는 현재 폴더 기준, `all folders`는 전체 로컬 세션입니다.
- `Marked`: 선택한 행 개수입니다.
- `Sessions`: 현재 화면에 보이는 세션 개수입니다.

## 기본 사용 흐름

1. `Tab`으로 일반 세션과 아카이브 세션 목록을 전환합니다.
2. `a`로 현재 폴더 기준 목록과 전체 목록을 전환합니다.
3. 방향키 또는 `j` / `k`로 원하는 세션에 커서를 둡니다.
4. `Space`로 행을 선택합니다. 여러 개를 선택하면 한 번에 처리할 수 있습니다.
5. `b`, `u`, `d`로 보관, 보관취소, 격리를 실행합니다.

선택된 행이 하나라도 있으면 `b`, `u`, `d`는 **선택된 행 전체**에 적용됩니다. 선택된 행이 없으면 **현재 커서가 있는 행 하나**에 적용됩니다.

## 세션 ID 안전 정책

보관, 보관취소, 삭제 같은 변경 작업은 세션 ID를 안전하게 확인한 항목에만 실행됩니다.

- 파일명이 정확히 `rollout-...-<UUID>.jsonl` 형식일 때만 끝의 UUID를 canonical ID 후보로 사용합니다.
- transcript 안에서는 첫 번째 최상위 `session_meta.payload.id`만 확인합니다.
- 파일명 UUID와 첫 번째 transcript UUID가 의미상 같아야 변경 작업이 가능합니다.
- 실행 직전 파일 경로가 표시된 상태에 맞는 `$CODEX_HOME/sessions` 또는 `$CODEX_HOME/archived_sessions` 아래의 JSONL인지 다시 확인합니다.
- 뒤쪽에 부모 세션이나 이전 세션의 `session_meta`가 다시 등장해도 canonical ID를 덮어쓰지 않습니다.
- UUID가 없거나, 형식이 틀리거나, 두 UUID가 불일치하거나, transcript를 안전하게 판별할 수 없으면 `unsafe`로 표시하고 변경 작업을 차단합니다.
- 다중 선택에 unsafe 항목이 하나라도 포함되면 안전한 항목만 골라 실행하지 않고 전체 작업을 차단합니다.
- 다중 작업은 전체 대상을 먼저 검증하고, 각 CLI 호출 직전에도 해당 transcript를 다시 읽습니다. 앞선 명령 실행 중 남은 세션 ID가 바뀌면 이후 명령을 중단하고 선택 상태를 유지합니다.

unsafe 항목도 목록에는 표시됩니다. TUI 상세 영역과 list 출력에서 차단 사유를 확인할 수 있습니다.

## 단축키

| Key | 동작 |
| --- | --- |
| `Up` / `Down` | 커서 이동 |
| `j` / `k` | 커서 이동 |
| `Tab` | 일반 세션 / 아카이브 세션 목록 전환 |
| `a` | 현재 폴더 기준 / 전체 폴더 기준 전환 |
| `/` | 검색 입력 시작 |
| `Enter` | 검색어 적용 |
| `Esc` | 검색 취소 |
| `R` | 디스크에서 세션 목록 다시 읽기 |
| `Space` | 현재 행 선택 / 선택 해제 |
| `A` | 현재 보이는 행 전체 선택 / 전체 선택 해제 |
| `C` | 선택 전부 해제 |
| `r` | 현재 active 세션 재개 |
| `b` | active 세션 보관 |
| `u` | archived 세션 보관취소 |
| `d` | 세션 격리 (`--force` 실행 시 영구 삭제) |
| `q` | 종료 |

## 격리와 영구 삭제

기본 실행에서 `d`는 삭제가 아니라 격리입니다. 선택한 JSONL 파일만 아래 기본 위치의 새 batch 디렉터리로 옮기며, batch마다 원래 경로와 보관된 상대 경로를 기록한 `manifest.json`을 생성합니다.

```txt
$XDG_DATA_HOME/csm/quarantine
```

`XDG_DATA_HOME`이 없으면 `~/.local/share/csm/quarantine`을 사용합니다. 다른 위치를 쓰려면 `--quarantine-dir PATH`를 지정할 수 있습니다. active/archived 세션 디렉터리 안쪽이나 홈/CODEX_HOME 자체처럼 지나치게 넓은 경로는 거부합니다.

격리 확인 문구:

```txt
QUARANTINE 019efcef-19e5-7a83-821a-1b3ec9e1716d
```

여러 개라면 대상 UUID 전체가 뒤에 이어집니다.

격리 없이 영구 삭제하려면 처음부터 `--force`로 TUI를 실행합니다.

```bash
./bin/csm --force
```

상단의 `Delete: permanent`와 `d=PERMADEL` 표시로 영구 삭제 모드임을 확인할 수 있습니다. 이 모드의 확인 문구는 더 강하게 구분됩니다.

```txt
FORCE DELETE 019efcef-19e5-7a83-821a-1b3ec9e1716d
```

확인에는 개수나 짧은 prefix가 아니라 화면에 표시된 대상 UUID 전체를 입력합니다. `Required input:` 뒤의 값을 그대로 입력해야 합니다.

확인 입력 후 대상 파일을 다시 읽어 UUID 안전성을 재검증합니다. 그 사이 ID가 바뀌거나 unsafe 상태가 되면 아무 파일도 변경하지 않고 전체 작업을 차단합니다. 격리는 batch 작업 도중 실패하면 이미 옮긴 파일을 원래 위치로 되돌리려고 시도합니다. 영구 삭제는 재검증을 통과한 선택 대상의 정확한 JSONL 경로만 `unlink`하며, 공식 `codex delete`를 호출하지 않습니다.

격리한 세션을 복구할 때는 해당 batch의 `manifest.json`에서 `originalPath`와 `storedRelativePath`를 확인한 뒤, batch 아래 파일을 원래 경로로 옮기면 됩니다. 복구 전에는 같은 원래 경로에 새 파일이 생기지 않았는지 먼저 확인하세요.

archive와 unarchive도 실행 전에 대상 UUID 목록을 터미널에 표시합니다.

transcript에서 읽은 제목, 경로, source 같은 표시 문자열에서는 터미널 제어 시퀀스를 제거하므로 세션 내용이 확인 화면이나 TUI를 조작할 수 없습니다.

## Non-Interactive List Mode

TUI를 열지 않고 목록만 보고 싶을 때 쓸 수 있습니다.

```bash
./bin/csm --list active
./bin/csm --list archived
./bin/csm --list all --all
./bin/csm --list all --json --all
```

테스트나 다른 Codex home을 확인할 때는 `CODEX_HOME`을 바꿀 수 있습니다.

```bash
CODEX_HOME=/tmp/example-codex ./bin/csm --list all --all
```

## Data Sources

스크립트가 읽는 위치:

```txt
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
$CODEX_HOME/state_5.sqlite
```

`state_5.sqlite`은 rename한 세션 이름을 읽을 때만 사용합니다. 이 파일을 읽을 수 없거나 현재 Node.js가 SQLite 읽기를 지원하지 않으면 목록은 기존처럼 초기 prompt를 표시합니다.

기본 `CODEX_HOME`은 `~/.codex`입니다.

archive와 unarchive는 세션 파일을 직접 수정하지 않고 아래 명령으로 실행합니다.

```bash
codex archive <SESSION_UUID>
codex unarchive <SESSION_UUID>
```

기본 `d`는 선택한 transcript를 격리 디렉터리로 이동하고, `--force`의 `d`는 선택한 transcript만 영구 삭제합니다.

## Tests

```bash
./smoke-test.sh
```

테스트는 `mktemp -d`로 만든 격리 디렉터리 안에서만 합성 JSONL fixture를 만들고, `HOME`, `CODEX_HOME`, `XDG_*` 경로를 모두 임시 위치로 바꿉니다. archive/unarchive 검증은 실제 `codex`가 아니라 `PATH` 앞에 둔 fake `codex` 바이너리로만 수행하고, 격리/영구 삭제도 임시 fixture만 대상으로 확인합니다.

설치 테스트 역시 임시 HOME만 사용하며 실제 `~/.local/bin`, `.bashrc`, `.zshrc`를 변경하지 않습니다.
