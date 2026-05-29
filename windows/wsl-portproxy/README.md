# wsl-portproxy

Windows `portproxy`로 WSL 개발 서버 포트를 Windows/LAN 쪽에 노출하거나 제거하는 스크립트입니다.

`devtunnel`처럼 SSH tunnel이 로컬 포트를 직접 바인딩해야 할 때, 기존 `portproxy`가 같은 포트를 잡고 있으면 `bind ... Permission denied`가 날 수 있습니다. 이 폴더의 `uninstall.ps1`로 그런 규칙을 정리할 수 있습니다.

## 파일

```txt
setup.ps1
uninstall.ps1
README.md
```

## 하는 일

`setup.ps1`:

- WSL IP를 `wsl hostname -I`로 확인
- 기존 동일 포트 `portproxy` 규칙 제거
- Windows `0.0.0.0:<port>`를 WSL `<ip>:<port>`로 연결
- Windows 방화벽 inbound 허용 규칙 추가

`uninstall.ps1`:

- 해당 포트의 `portproxy` 규칙 제거
- 방화벽 규칙 제거
- 예전 스크립트가 만든 `"Vite <port>"` 방화벽 규칙도 같이 제거

## 관리자 PowerShell 필요

`netsh interface portproxy`와 방화벽 규칙을 수정하므로 관리자 PowerShell에서 실행하세요.

관리자 권한이 아니면 추가/삭제가 실패할 수 있습니다.

## 사용법

repo 루트에서 실행하는 예:

```powershell
.\windows\wsl-portproxy\setup.ps1 -Port 5173
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173
```

절대 경로로 실행하는 예:

```powershell
C:\Users\User\Documents\Code\Projects\Personal\script-store\windows\wsl-portproxy\setup.ps1 -Port 5173
C:\Users\User\Documents\Code\Projects\Personal\script-store\windows\wsl-portproxy\uninstall.ps1 -Port 5173
```

자주 쓰는 포트:

```powershell
.\windows\wsl-portproxy\setup.ps1 -Port 3000
.\windows\wsl-portproxy\setup.ps1 -Port 5173
.\windows\wsl-portproxy\setup.ps1 -Port 6006
```

정리:

```powershell
.\windows\wsl-portproxy\uninstall.ps1 -Port 3000
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173
.\windows\wsl-portproxy\uninstall.ps1 -Port 5174
.\windows\wsl-portproxy\uninstall.ps1 -Port 6006
```

## 현재 portproxy 확인

```powershell
netsh interface portproxy show all
```

출력이 아래처럼 나오면 Windows의 `IP Helper` 서비스가 해당 로컬 포트를 잡고 있을 수 있습니다.

```txt
Listen on ipv4:             Connect to ipv4:

Address         Port        Address         Port
--------------- ----------  --------------- ----------
0.0.0.0         5173        172.xx.xx.xx    5173
0.0.0.0         3000        172.xx.xx.xx    3000
```

## devtunnel에서 Permission denied가 날 때

예:

```txt
bind [127.0.0.1]:5173: Permission denied
bind [127.0.0.1]:3000: Permission denied
```

이 경우 로컬 PC에서 해당 포트를 이미 사용 중일 가능성이 큽니다. 특히 `portproxy`가 잡고 있으면 `svchost` / `IP Helper`가 `0.0.0.0:<port>` 형태로 리슨합니다.

확인:

```powershell
Get-NetTCPConnection -LocalPort 5173 -State Listen
Get-NetTCPConnection -LocalPort 3000 -State Listen
```

프로세스까지 확인:

```powershell
$port = 5173
$conn = Get-NetTCPConnection -LocalPort $port -State Listen
Get-Process -Id $conn.OwningProcess
```

`ProcessName`이 `svchost`이고 서비스가 `IP Helper`라면 보통 `portproxy` 규칙 때문입니다.

```powershell
Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -eq $conn.OwningProcess }
```

해결:

```powershell
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173
.\windows\wsl-portproxy\uninstall.ps1 -Port 3000
```

그 다음 다시 확인:

```powershell
netsh interface portproxy show all
```

## Windsurf 같은 앱이 포트를 잡고 있을 때

`3001`처럼 특정 앱이 직접 잡고 있는 포트는 `uninstall.ps1`로 해결되지 않습니다. 예를 들어 `Windsurf.exe`가 `127.0.0.1:3001`을 리슨 중이면 앱을 종료하거나 다른 포트를 사용해야 합니다.

확인:

```powershell
Get-NetTCPConnection -LocalPort 3001 -State Listen
```

## devtunnel과 같이 쓸 때

`devtunnel`은 로컬 포트를 직접 바인딩합니다.

```powershell
devtunnel 5173 prox-dev-hoyoung
```

따라서 같은 포트가 `portproxy`, Windsurf, Vite, Next.js 등에서 이미 사용 중이면 실패합니다.

먼저 해당 포트를 비운 뒤 실행하세요.

```powershell
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173
devtunnel 5173 prox-dev-hoyoung
```

여러 포트를 열 때는 사용 중인 포트 하나만 있어도 해당 포트 바인딩이 실패할 수 있습니다.

```powershell
devtunnel 3000,5173,6006 prox-dev-hoyoung
```

필요 없는 `portproxy`를 정리하거나, 비어 있는 포트만 골라서 실행하세요.

## 직접 netsh로 삭제하기

스크립트 없이 직접 삭제할 수도 있습니다.

```powershell
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=5173
```

방화벽 규칙까지 지우려면:

```powershell
Remove-NetFirewallRule -DisplayName "WSL PortProxy 5173"
Remove-NetFirewallRule -DisplayName "Vite 5173"
```

## 주의

`portproxy` 규칙은 WSL의 개발 서버를 Windows/LAN에서 접근하려고 일부러 만든 규칙일 수 있습니다. 지우면 해당 포트의 외부 접근이 끊깁니다.

확실하지 않을 때는 먼저 현재 규칙을 확인하세요.

```powershell
netsh interface portproxy show all
```
