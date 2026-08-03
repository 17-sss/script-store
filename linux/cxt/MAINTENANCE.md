# cxt 유지보수

`cxt`는 Codex 네이티브 옵션을 그대로 전달하지만, 모델·생각 레벨·권한 편의 옵션은 현재 Codex CLI 계약과 모델 카탈로그를 바탕으로 직접 매핑합니다. 따라서 Codex 업데이트로 모델 slug나 지원 레벨, 권한 옵션이 바뀌면 이 매핑도 점검해야 합니다.

## 마지막 검토 기준

- 검토일: 2026-07-20
- Codex CLI: `codex-cli 0.144.6`
- 로컬 모델 카탈로그 client version: `0.144.1`
- 공식 기준: [Codex manual](https://developers.openai.com/codex/codex-manual.md), 현재 CLI 도움말, 현재 사용자에게 노출된 로컬 모델 카탈로그

이 값은 호환성 보장이 아니라 다음 점검에서 차이를 찾기 위한 기준점입니다. 유지보수 작업을 마칠 때 검토일과 버전을 현재 확인값으로 갱신합니다.

## 권장 주기

- 2주마다 전체 점검
- Codex CLI를 업데이트한 직후 즉시 점검
- 모델 선택 UI, reasoning effort, sandbox 또는 approval 동작이 달라졌을 때 즉시 점검
- 변경이 없더라도 분기마다 전체 mock 테스트 실행

모델 캐시나 매뉴얼의 변화는 검토를 시작할 신호이지, 무조건 별칭을 추가하거나 제거하라는 뜻은 아닙니다. 실제 사용자에게 노출되는 값과 CLI 동작을 함께 확인합니다.

## 정기 점검 절차

1. 현재 변경과 설치 상태를 확인합니다.

   ```bash
   git status --short --branch
   command -v cxt
   readlink "$HOME/.local/bin/cxt"
   ```

2. 현재 CLI 계약을 확인합니다.

   ```bash
   codex --version
   codex --help
   codex exec --help
   ```

3. 현재 사용자에게 노출된 모델과 모델별 reasoning level을 확인합니다.

   ```bash
   python3 - <<'PY'
   import json
   import os
   from pathlib import Path

   codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
   data = json.loads((codex_home / "models_cache.json").read_text())
   print("fetched_at:", data.get("fetched_at"))
   print("client_version:", data.get("client_version"))
   for model in data.get("models", []):
       if model.get("visibility") != "list":
           continue
       efforts = ",".join(
           item.get("effort", "")
           for item in model.get("supported_reasoning_levels", [])
       )
       print(model.get("slug"), efforts, sep="\t")
   PY
   ```

   `models_cache.json`이 없거나 오래되었다면 캐시만 보고 결론내리지 말고 Codex의 모델 선택 화면과 공식 매뉴얼을 교차 확인합니다.

4. 현재 Codex 매뉴얼을 새로 확인합니다. 시스템 `openai-docs` 스킬이 있으면 그 절차를 우선합니다. 직접 helper를 실행할 때는 다음 명령을 사용합니다.

   ```bash
   node "${CODEX_HOME:-$HOME/.codex}/skills/.system/openai-docs/scripts/fetch-codex-manual.mjs"
   ```

   helper를 사용할 수 없다면 위의 공식 manual URL을 확인합니다. 이 Node 사용은 유지보수용이며 `cxt` 실행 의존성이 아닙니다.

5. 다음 drift를 비교합니다.

   - `bin/cxt`의 모델 별칭이 현재 list-visible 모델 slug를 정확히 가리키는가
   - 각 reasoning 별칭이 현재 모델들이 지원하는 값인가
   - `--sandbox`와 `--ask-for-approval` 값이 현재 CLI 도움말과 일치하는가
   - deprecated 또는 새 위험 옵션이 권한 프리셋 의미를 바꾸지 않았는가
   - 모든 새 Codex 네이티브 옵션이 여전히 변환 없이 전달되는가
   - `--` 뒤의 값과 공백이 포함된 인자의 boundary가 보존되는가

6. drift가 있을 때만 `bin/cxt`, `--cxt-help`, `completions/cxt.bash`, `completions/cxt.zsh`, `README.md`, `tests/test-cxt.sh`를 함께 수정합니다. 이 문서의 마지막 검토 기준도 갱신합니다.

7. 검증합니다.

   ```bash
   cd linux/cxt
   bash -n bin/cxt
   bash -n install-cxt.sh
   bash -n completions/cxt.bash
   zsh -n completions/cxt.zsh
   bash -n tests/test-cxt.sh
   ./tests/test-cxt.sh
   git diff --check
   ```

   ShellCheck가 설치되어 있으면 실행하고, 없으면 누락 사실을 결과에 남깁니다. 실제 `~/.zshrc`, `~/.bashrc`, `~/.local/bin`을 테스트 대상으로 사용하지 않습니다.

## 정기 실행용 프롬프트

다음 프롬프트를 Codex에서 수동으로 실행하거나 이 저장소를 대상으로 한 Scheduled task에 사용합니다. 예약 작업은 진행 중인 main 작업과 섞이지 않도록 전용 worktree를 권장합니다.

```text
현재 저장소의 linux/cxt 편의 옵션을 최신 Codex CLI와 동기화해라.

먼저 linux/cxt/AGENTS.md와 linux/cxt/MAINTENANCE.md를 전부 읽고 그 절차를 따른다. 현재 git 상태를 확인해 기존 변경을 보존한다. 설치된 codex --version, codex --help, codex exec --help, 현재 사용자에게 list-visible인 $CODEX_HOME/models_cache.json, 최신 공식 Codex manual을 근거로 다음을 점검한다.

- 모델 별칭과 실제 model slug
- 모델별 reasoning effort 지원 범위
- safe/auto/full-auto/madmax 권한 프리셋의 sandbox 및 approval 의미
- 네이티브 옵션 passthrough와 -- 이후 무변환 계약

drift가 확인된 경우에만 linux/cxt/bin/cxt, --cxt-help, completions/cxt.bash, completions/cxt.zsh, README.md, tests/test-cxt.sh, MAINTENANCE.md의 마지막 검토 기준을 함께 갱신한다. 추측한 모델이나 숨겨진 모델을 추가하지 않는다. npm/Node 런타임 의존성을 추가하지 않는다. 실제 사용자 홈이나 shell rc를 수정하지 않는다.

Bash/Zsh completion을 포함한 구문 검사, 전체 격리 테스트, 설치되어 있다면 ShellCheck, git diff --check를 실행한다. 변경이 없으면 근거와 함께 no-op으로 보고한다. 변경이 있으면 파일별 변경, 검증 결과, 남은 모델별 제약을 보고한다. 커밋하거나 푸시하지 않는다.
```

AGENTS 지침 자체는 예약 실행을 만들지 않습니다. 자동 주기 실행이 필요하면 Codex app의 Scheduled task에 위 프롬프트와 이 저장소를 연결해야 합니다.
