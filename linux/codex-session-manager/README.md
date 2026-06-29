# codex-session-manager

Codex 로컬 세션을 TUI에서 찾고, 선택해서 보관/보관취소/삭제하는 도구입니다.

Codex CLI는 `resume`, `archive`, `delete`, `unarchive`는 제공하지만, 현재 로컬 active/archived 세션을 한 번에 사람이 보기 좋게 출력하는 `list` 명령은 없습니다. 이 스크립트는 로컬 transcript 파일을 읽어서 목록을 보여주고, 변경 작업은 공식 `codex` CLI로 위임합니다.

## Requirements

- Node.js
- `PATH`에서 실행 가능한 Codex CLI

`fzf`, npm package, 설치 단계는 필요 없습니다.

## Quick Start

이 README가 있는 폴더에서 실행:

```bash
./codex-session-manager.js
```

repo 루트에서 실행:

```bash
./linux/codex-session-manager/codex-session-manager.js
```

기본 화면은 **현재 실행한 폴더와 그 하위 폴더에서 열린 Codex 세션**만 보여줍니다. 전체 로컬 세션을 보고 싶으면 TUI 안에서 `a`를 누르세요.

## 화면 읽는 법

상단 상태줄은 이런 형태입니다.

```txt
codex-session-manager | View: active | Scope: current folder | Marked: 0 | Sessions: 3
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
5. `b`, `u`, `d`로 보관, 보관취소, 삭제를 실행합니다.

선택된 행이 하나라도 있으면 `b`, `u`, `d`는 **선택된 행 전체**에 적용됩니다. 선택된 행이 없으면 **현재 커서가 있는 행 하나**에 적용됩니다.

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
| `d` | 세션 삭제 |
| `q` | 종료 |

## 삭제 확인

삭제는 실수 방지를 위해 확인 문구를 입력해야 합니다. TUI에서는 실제로 입력해야 하는 값이 굵은 노란색으로 표시됩니다.

한 개 삭제:

```txt
DELETE 019efcef
```

여러 개 삭제:

```txt
DELETE 3
```

여러 개 삭제에서 숫자는 현재 선택된 세션 개수입니다. 화면에 표시된 `Required input:` 뒤의 값을 그대로 입력하면 됩니다.

확인 후 각 세션에 대해 `codex delete <SESSION_UUID> --force`를 실행합니다.

## Non-Interactive List Mode

TUI를 열지 않고 목록만 보고 싶을 때 쓸 수 있습니다.

```bash
./codex-session-manager.js --list active
./codex-session-manager.js --list archived
./codex-session-manager.js --list all --all
./codex-session-manager.js --list all --json --all
```

테스트나 다른 Codex home을 확인할 때는 `CODEX_HOME`을 바꿀 수 있습니다.

```bash
CODEX_HOME=/tmp/example-codex ./codex-session-manager.js --list all --all
```

## Data Sources

스크립트가 읽는 위치:

```txt
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
```

기본 `CODEX_HOME`은 `~/.codex`입니다.

변경 작업은 세션 파일을 직접 수정하지 않고 아래 명령으로 실행합니다.

```bash
codex archive <SESSION_UUID>
codex delete <SESSION_UUID> --force
codex unarchive <SESSION_UUID>
```
