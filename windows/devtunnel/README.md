# devtunnel-manager

Windows PowerShell에서 SSH 포트 포워딩을 쉽게 실행하기 위한 `devtunnel` 함수를 설치/제거하는 스크립트입니다.

원격 개발 서버에서 `pnpm dev`, `npm run dev`, `vite`, `next dev`, `storybook` 등을 실행한 뒤, Windows 로컬 브라우저에서 `http://localhost:3000` 같은 주소로 접속하고 싶을 때 사용합니다.

## 구성 파일

```txt
devtunnel-manager.ps1
smoke-test.ps1
README.md
```

## 지원 기능

- PowerShell `$PROFILE`에 `devtunnel` 함수 설치
- PowerShell `$PROFILE`에서 `devtunnel` 함수 제거
- 실행 시 SSH host alias 입력
- 실행 시 단일 포트 또는 여러 포트 입력
- Windows IPv4 loopback(`127.0.0.1`)에만 명시적으로 bind
- 모든 초기 포워딩 생성 성공을 요구하고 SSH 실패 종료를 호출자에게 전달
- `Ctrl + C`로 열린 터널 종료
- `devtunnel` 도움말 출력

이 스크립트는 SSH config를 생성하거나 수정하지 않습니다. SSH alias는 사용자가 직접 관리하는 `~/.ssh/config`의 `Host`를 사용합니다.

## 설치 전 준비

PowerShell에서 원격 개발 서버에 SSH 접속이 가능한지 먼저 확인하세요.

```powershell
ssh prox-dev-hoyoung
```

## 실행 정책 때문에 막힐 때

PowerShell 스크립트 실행이 막히면 현재 세션에서만 다음 명령을 실행하세요.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## 실제 설치 전 스모크 테스트

실제 PowerShell profile을 건드리기 전에 임시 디렉터리에서 설치/제거 흐름을 검증할 수 있습니다.

```powershell
.\smoke-test.ps1
```

실패한 임시 파일을 확인하고 싶으면:

```powershell
.\smoke-test.ps1 -KeepTemp
```

테스트는 아래 항목을 확인합니다.

- 임시 profile에 `devtunnel` 함수가 설치되는지
- SSH config를 만들거나 수정하지 않는지
- `devtunnel -Help`, `devtunnel -h`, `Get-Help devtunnel -Detailed`이 동작하는지
- `devtunnel 3000,5173 alias`가 올바른 SSH 포워딩 인자를 만드는지
- `ExitOnForwardFailure=yes`와 명시적 `127.0.0.1` local bind를 전달하는지
- 옵션처럼 시작하거나 공백이 있는 host alias와 중복 포트를 SSH 실행 전에 거부하는지
- mock SSH 비정상 종료가 성공으로 처리되지 않는지
- UTF-8 BOM·CRLF·한글·`[]` 경로의 기존 profile bytes가 제거 후 정확히 복원되는지
- marker 충돌·managed block 수정·원자 교체 실패가 기존 bytes를 바꾸지 않는지
- `uninstall`이 profile에서 함수 블록을 제거하는지

## 설치

```powershell
.\devtunnel-manager.ps1 install
```

설치 중 SSH 관련 값은 입력하지 않습니다. 설치는 `devtunnel` 함수만 PowerShell profile에 추가합니다.

설치 후 PowerShell을 재시작하거나 아래 명령을 실행하세요.

```powershell
. $PROFILE
```

같은 PowerShell 창에서 바로 `devtunnel`을 쓰려면 이 명령이 필요합니다. 실행하지 않으면 새 함수가 아직 현재 세션에 로드되지 않아 `devtunnel` 명령을 찾을 수 없다고 나옵니다.

## 사용법

특정 포트 하나 열기:

```powershell
devtunnel 3123 prox-dev-hoyoung
```

여러 포트 열기:

```powershell
devtunnel 3000,5173,6006 prox-dev-hoyoung
```

명시적 파라미터로 실행:

```powershell
devtunnel -Ports 3123 -HostAlias prox-dev-hoyoung
devtunnel -Ports 3000,5173,6006 -HostAlias prox-dev-hoyoung
```

도움말 확인:

```powershell
devtunnel -Help
devtunnel -h
Get-Help devtunnel -Detailed
```

터널을 닫으려면 해당 터미널에서 `Ctrl + C`를 누르면 됩니다.

## 동작 예시

원격 개발 서버에서 개발 서버 실행:

```bash
pnpm dev --port 3123
```

Windows PowerShell에서 터널 실행:

```powershell
devtunnel 3123 prox-dev-hoyoung
```

Windows 브라우저에서 접속:

```txt
http://localhost:3123
```

동작 구조:

```txt
Windows localhost:3123
  -> SSH tunnel
    -> prox-dev-hoyoung 127.0.0.1:3123
```

내부적으로는 다음 SSH 명령과 유사하게 동작합니다.

```powershell
ssh -o ExitOnForwardFailure=yes -N `
  -L 127.0.0.1:3123:127.0.0.1:3123 `
  prox-dev-hoyoung
```

여러 포트를 열면 `-L` 인자가 포트 수만큼 추가됩니다.

```powershell
ssh -N `
  -o ExitOnForwardFailure=yes `
  -L 127.0.0.1:3000:127.0.0.1:3000 `
  -L 127.0.0.1:5173:127.0.0.1:5173 `
  -L 127.0.0.1:6006:127.0.0.1:6006 `
  prox-dev-hoyoung
```

local bind 주소를 생략하지 않으므로 사용자 SSH 설정의 `GatewayPorts` 값과
관계없이 Windows의 IPv4 loopback에서만 열립니다. 하나라도 초기 bind 또는
forwarding 설정에 실패하면 `ExitOnForwardFailure=yes`로 SSH가 비정상 종료하고
`devtunnel`도 오류를 반환합니다.

## 재설치

`devtunnel` 함수를 다시 덮어쓰고 싶으면:

```powershell
.\devtunnel-manager.ps1 reinstall
```

`install`과 `reinstall`은 설치된 managed block이 현재 버전과 byte-equivalent하면
profile을 다시 쓰지 않습니다. marker는 같지만 내용이 다르거나 사용자가
managed block을 수정한 경우에는 해당 내용을 덮어쓰지 않고 충돌로 중단합니다.

## 제거

```powershell
.\devtunnel-manager.ps1 remove
```

`uninstall`도 같은 동작입니다.

```powershell
.\devtunnel-manager.ps1 uninstall
```

## 설치되는 PowerShell 함수

설치 후 PowerShell에서 아래 함수가 사용 가능해집니다.

```powershell
devtunnel 3000,5173,6006 prox-dev-hoyoung
```

## 자주 쓰는 포트

| 포트 | 용도 |
|---:|---|
| 3000 | Next.js, React dev server |
| 5173 | Vite |
| 6006 | Storybook |
| 8080 | 일반 웹 서버 |
| 8000 | Django, FastAPI 등 |

## 주의사항

이 스크립트는 PowerShell profile의 아래 marker 사이 내용만 관리합니다.

```powershell
# >>> devtunnel function >>>
# <<< devtunnel function <<<
```

marker는 각각 정확히 하나여야 하고, block 전체가 현재 manager가 생성한 내용과
일치해야 제거할 수 있습니다. 중복 marker, 한쪽 marker만 있는 경우, block 내부
수정은 모두 profile을 변경하지 않고 오류로 종료합니다. 이전 버전이 만든
서명 없는 block도 자동 변환하거나 삭제하지 않으므로 내용을 직접 검토한 뒤
정리해야 합니다.

profile은 `-LiteralPath` 의미의 .NET 파일 API로 읽고, 기존 BOM·encoding·개행과
managed block 밖 bytes를 보존합니다. 같은 디렉터리의 임시 파일을 쓴 뒤
원자적으로 교체하므로 쓰기/교체 실패 전에 원본을 삭제하지 않습니다.

SSH config는 읽거나 쓰지 않습니다.

SSH host alias는 빈 값, 공백 포함 값, `-`로 시작하는 옵션 형태를 거부합니다.
SSH config의 정상적인 단일 alias(필요하면 `user@host`)를 사용하세요.

## 문제 해결

### 설치 후 바로 실행했는데 예전 동작이나 이상한 SSH 인자가 나올 때

`install`은 `$PROFILE` 파일을 업데이트하지만, 이미 열려 있는 PowerShell 세션의 함수 메모리를 자동으로 바꾸지는 않습니다. 같은 창에서 바로 쓰려면 profile을 다시 로드하세요.

```powershell
. $PROFILE
```

그래도 이전 함수가 실행되는 것 같으면 현재 세션의 함수를 지운 뒤 다시 로드하세요.

```powershell
Remove-Item function:\devtunnel -ErrorAction SilentlyContinue
. $PROFILE
```

예를 들어 아래처럼 `HostAlias`가 빠진 것처럼 보이는 출력이나 `Bad local forwarding specification '.0.0.1:3123'` 오류가 나오면, 대부분 현재 세션에 예전 `devtunnel` 함수가 남아 있는 상태입니다.

```txt
http://localhost:3123 -> .0.0.1:3123
Bad local forwarding specification '.0.0.1:3123'
```

### `devtunnel` 명령을 찾을 수 없다고 나올 때

PowerShell을 재시작하거나 아래 명령을 실행하세요.

```powershell
. $PROFILE
```

### SSH alias를 찾을 수 없다고 나올 때

먼저 일반 SSH 접속이 되는지 확인하세요.

```powershell
ssh prox-dev-hoyoung
```

이 명령이 실패하면 `devtunnel` 문제가 아니라 SSH config나 SSH 연결 문제입니다.

### 포트가 이미 사용 중이라고 나올 때

Windows에서 해당 포트를 이미 사용 중일 수 있습니다. 다른 포트로 개발 서버를 띄우거나, 직접 SSH 명령으로 로컬 포트와 원격 포트를 다르게 연결하세요.

`devtunnel`은 요청한 포트 중 하나라도 초기 bind에 실패하면 터널 전체를
실패로 처리합니다. 일부 포트만 열린 상태를 성공으로 안내하지 않습니다.

```powershell
ssh -N -L 3001:127.0.0.1:3000 prox-dev-hoyoung
```

그러면 Windows에서는 아래 주소로 접속합니다.

```txt
http://localhost:3001
```

### SSH 연결은 되는데 브라우저에서 안 열릴 때

원격 개발 서버에서 먼저 확인하세요.

```bash
curl http://127.0.0.1:3123
```

이게 안 되면 터널 문제가 아니라 개발 서버가 원격 서버에서 제대로 실행되지 않은 상태입니다.
