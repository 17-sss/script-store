# devtunnel-manager

Windows PowerShell에서 SSH 포트 포워딩을 쉽게 실행하기 위한 `devtunnel` 함수를 설치/제거/재설치하는 스크립트입니다.

Proxmox 위 Ubuntu VM 같은 원격 개발 서버에서 `pnpm dev`, `npm run dev`, `vite`, `next dev`, `storybook` 등을 실행한 뒤, Windows 로컬 브라우저에서 `http://localhost:3000` 같은 주소로 접속하고 싶을 때 사용합니다.

## 구성 파일

```txt
devtunnel-manager.ps1
smoke-test.ps1
README.md
```

## 지원 기능

- PowerShell `$PROFILE`에 `devtunnel` 함수 설치
- Windows `~/.ssh/config`에 SSH host block 등록
- 설치 시 SSH 값 입력
  - Host alias
  - HostName / IP
  - User
  - Port
  - IdentityFile
  - 기본 포워딩 포트
- 재설치 지원
- 제거 지원
- 여러 포트 동시 포워딩 지원
- `devtunnel` 도움말 출력 지원

## 설치 전 준비

PowerShell에서 원격 Ubuntu VM에 SSH 접속이 가능한지 먼저 확인하세요.

```powershell
ssh user@server-ip
```

이미 `~/.ssh/config`에 host alias가 있다면 아래처럼 접속되는지도 확인합니다.

```powershell
ssh remote-ubuntu-dev
```

## 실행 정책 때문에 막힐 때

PowerShell 스크립트 실행이 막히면 현재 세션에서만 다음 명령을 실행하세요.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

그 뒤 스크립트를 실행하면 됩니다.

## 실제 설치 전 스모크 테스트

실제 PowerShell profile이나 SSH config를 건드리기 전에 임시 디렉터리에서 설치/재설치/제거 흐름을 검증할 수 있습니다.

```powershell
.\smoke-test.ps1
```

실패한 임시 파일을 확인하고 싶으면:

```powershell
.\smoke-test.ps1 -KeepTemp
```

테스트는 아래 항목을 확인합니다.

- 임시 profile에 `devtunnel` 함수가 설치되는지
- 임시 SSH config에 managed host block이 생성되는지
- `devtunnel -Help`, `devtunnel -h`, `Get-Help devtunnel -Detailed`이 동작하는지
- `reinstall`이 이전 managed SSH block을 제거하고 새 설정을 쓰는지
- `remove -RemoveSshBlocks`가 managed block을 제거하는지

## 설치

```powershell
.\devtunnel-manager.ps1 install
```

설치 중 아래 값들을 입력합니다.

```txt
SSH Host alias [remote-ubuntu-dev]
SSH HostName / IP
SSH User [현재 Windows 사용자명]
SSH Port [22]
IdentityFile [C:\Users\...\ .ssh\id_ed25519] (type none to skip)
Default ports, comma separated [3000]
```

예시:

```txt
SSH Host alias [remote-ubuntu-dev]: dev-vm
SSH HostName / IP: 192.168.0.120
SSH User [windows-user]: devuser
SSH Port [22]: 22
IdentityFile [C:\Users\devuser\.ssh\id_ed25519] (type none to skip):
Default ports, comma separated [3000]: 3000,5173,6006
```

설치 후 PowerShell을 재시작하거나 아래 명령을 실행하세요.

```powershell
. $PROFILE
```

## 사용법

기본 포트로 터널 열기:

```powershell
devtunnel
```

특정 포트 하나만 열기:

```powershell
devtunnel -Ports 3000
```

여러 포트 열기:

```powershell
devtunnel -Ports 3000,5173,6006
```

다른 SSH host alias로 열기:

```powershell
devtunnel -Ports 3000 -HostAlias remote-ubuntu-dev
```

도움말 확인:

```powershell
devtunnel -Help
devtunnel -h
Get-Help devtunnel -Detailed
```

터널을 닫으려면 해당 터미널에서 `Ctrl + C`를 누르면 됩니다.

## 동작 예시

원격 Ubuntu VM에서 개발 서버 실행:

```bash
pnpm dev
```

Windows PowerShell에서 터널 실행:

```powershell
devtunnel -Ports 3000
```

Windows 브라우저에서 접속:

```txt
http://localhost:3000
```

동작 구조:

```txt
Windows localhost:3000
  -> SSH tunnel
    -> Ubuntu VM 127.0.0.1:3000
```

## 재설치

IP, 기본 포트, SSH user 등을 다시 입력받아 덮어쓰고 싶으면:

```powershell
.\devtunnel-manager.ps1 reinstall
```

기존에 이 스크립트가 설치한 `devtunnel` 함수 블록과 SSH config block을 새 설정으로 다시 설치합니다.

## 제거

`devtunnel` 함수만 제거:

```powershell
.\devtunnel-manager.ps1 remove
```

실행 중 다음 질문이 나옵니다.

```txt
Also remove devtunnel-managed SSH config blocks? y/n [n]
```

- `n`: PowerShell 함수만 제거하고 SSH config는 유지
- `y`: 이 스크립트가 관리하는 SSH config block도 제거

## 설치되는 PowerShell 함수

설치 후 PowerShell에서 아래 함수가 사용 가능해집니다.

```powershell
devtunnel -Ports 3000,5173,6006 -HostAlias remote-ubuntu-dev
```

내부적으로는 다음 SSH 명령과 유사하게 동작합니다.

```powershell
ssh -N -L 3000:127.0.0.1:3000 -L 5173:127.0.0.1:5173 -L 6006:127.0.0.1:6006 remote-ubuntu-dev
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

이 스크립트는 아래 marker 사이의 내용만 관리합니다.

PowerShell profile:

```powershell
# >>> devtunnel function >>>
# <<< devtunnel function <<<
```

SSH config:

```sshconfig
# >>> devtunnel ssh host: <alias> >>>
# <<< devtunnel ssh host: <alias> <<<
```

기존 SSH config 전체를 덮어쓰지는 않습니다.

## 문제 해결

### `devtunnel` 명령을 찾을 수 없다고 나올 때

PowerShell을 재시작하거나 아래 명령을 실행하세요.

```powershell
. $PROFILE
```

### 포트가 이미 사용 중이라고 나올 때

Windows에서 해당 포트를 이미 사용 중일 수 있습니다. 다른 로컬 포트를 쓰려면 현재 스크립트의 `devtunnel`은 같은 포트끼리만 연결하므로, 임시로 직접 SSH 명령을 쓰는 편이 빠릅니다.

```powershell
ssh -N -L 3001:127.0.0.1:3000 remote-ubuntu-dev
```

그러면 Windows에서는 아래 주소로 접속합니다.

```txt
http://localhost:3001
```

### SSH 연결은 되는데 브라우저에서 안 열릴 때

원격 Ubuntu VM에서 먼저 확인하세요.

```bash
curl http://127.0.0.1:3000
```

이게 안 되면 터널 문제가 아니라 개발 서버가 원격 VM에서 제대로 실행되지 않은 상태입니다.
