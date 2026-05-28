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
ssh -N -L 3123:127.0.0.1:3123 prox-dev-hoyoung
```

여러 포트를 열면 `-L` 인자가 포트 수만큼 추가됩니다.

```powershell
ssh -N `
  -L 3000:127.0.0.1:3000 `
  -L 5173:127.0.0.1:5173 `
  -L 6006:127.0.0.1:6006 `
  prox-dev-hoyoung
```

## 재설치

`devtunnel` 함수를 다시 덮어쓰고 싶으면:

```powershell
.\devtunnel-manager.ps1 reinstall
```

`install`도 기존 managed function block을 제거한 뒤 다시 쓰기 때문에 사실상 재설치처럼 동작합니다.

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

SSH config는 읽거나 쓰지 않습니다.

## 문제 해결

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
