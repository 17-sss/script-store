# wsl-portproxy

Windows `portproxy`로 WSL 개발 서버 포트를 Windows/LAN 쪽에 노출하거나 제거하는 스크립트입니다.

`devtunnel`처럼 SSH tunnel이 로컬 포트를 직접 바인딩해야 할 때, 기존 `portproxy`가 같은 포트를 잡고 있으면 `bind ... Permission denied`가 날 수 있습니다. 이 폴더의 `uninstall.ps1`로 그런 규칙을 정리할 수 있습니다.

## 파일

```txt
setup.ps1
uninstall.ps1
smoke-test.ps1
README.md
```

## 하는 일

`setup.ps1`:

- WSL IP를 argv 배열의 `wsl.exe ... hostname -I`로 확인
- 정확히 하나인 private IPv4만 허용하고 다중 후보·공인/잘못된 IP를 거부
- 기본 `Loopback`은 Windows `127.0.0.1:<port>`만 WSL `<ip>:<port>`로 연결
- 명시적 `Lan`은 `0.0.0.0:<port>`와 Private profile/LocalSubnet 방화벽 규칙을 생성
- 생성한 proxy/firewall의 정확한 identity를 로컬 ownership state에 기록
- 기존 규칙 충돌·native 실패·부분 실패 시 중단하고 이번 실행의 변경을 rollback

`uninstall.ps1`:

- ownership state와 현재 proxy/firewall가 정확히 일치할 때만 제거
- proxy 제거 뒤 firewall 제거가 실패하면 proxy를 원래 값으로 rollback
- 소유권 불명 규칙과 예전 `"Vite <port>"` 규칙은 변경하지 않음

## 관리자 PowerShell 필요

`netsh interface portproxy`와 방화벽 규칙을 수정하므로 관리자 PowerShell에서 실행하세요.

관리자 권한이 아니면 추가/삭제가 실패할 수 있습니다.

## 사용법

repo 루트에서 실행하는 예:

```powershell
.\windows\wsl-portproxy\setup.ps1 -Port 5173
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173

# LAN의 다른 기기에서도 접근해야 할 때만 명시
.\windows\wsl-portproxy\setup.ps1 -Port 5173 -Exposure Lan
.\windows\wsl-portproxy\uninstall.ps1 -Port 5173 -Exposure Lan
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
127.0.0.1       5173        172.xx.xx.xx    5173
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

해당 규칙이 이 도구의 ownership state와 일치할 때만 다음처럼 제거합니다.

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

여러 포트를 열 때는 사용 중인 포트 하나만 있어도 `devtunnel` 전체가 실패합니다.

```powershell
devtunnel 3000,5173,6006 prox-dev-hoyoung
```

필요 없는 `portproxy`를 정리하거나, 비어 있는 포트만 골라서 실행하세요.

## 소유권 상태와 충돌 정책

기본 ownership state 위치는 다음과 같습니다.

```text
%LOCALAPPDATA%\script-store\wsl-portproxy\<exposure>-<port>.json
```

테스트나 별도 관리 환경에서는 `WSL_PORTPROXY_STATE_HOME`으로 바꿀 수 있습니다.
state에는 owner, port, exposure, listen/connect 주소, firewall identity를
기록합니다. 같은 listen address/port에 기존 proxy가 있는데 이 state가 없거나,
기록과 현재 규칙이 다르면 setup/uninstall 모두 아무것도 변경하지 않고
중단합니다. firewall도 고정 `Name`, display name, group, direction, action,
Private profile, TCP port, LocalSubnet 범위가 모두 일치해야 제거합니다.

이전 스크립트가 만든 state 없는 `0.0.0.0:<port>` 또는 `"Vite <port>"`
방화벽 규칙은 자동 이관·삭제하지 않습니다. 아래 수동 명령은 소유권과 영향
범위를 직접 확인한 경우에만 사용하세요.

## 직접 netsh로 삭제하기

스크립트 없이 직접 삭제할 수도 있습니다.

```powershell
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=5173
```

방화벽 규칙까지 지우려면:

```powershell
Get-NetFirewallRule -DisplayName "WSL PortProxy 5173"
Get-NetFirewallRule -DisplayName "Vite 5173"
```

## 지원 범위와 공개 경계

이 도구는 Windows의 WSL2 NAT 환경에서 TCP `v4tov4`만 지원합니다. 사용자
`.wslconfig`에 `networkingMode=mirrored` 또는 NAT가 아닌 값이 명시돼 있으면
중단하며 mode나 `IP Helper` 서비스를 자동 변경하지 않습니다. `iphlpsvc`가
실행 중이 아니면 진단만 출력하고 중단합니다.

기본 `Loopback`은 Windows 자신에서만 접근하게 하며 inbound firewall 규칙을
만들지 않습니다. `-Exposure Lan`은 `0.0.0.0`에 listen하므로 같은 LAN의 다른
기기에 공개될 수 있습니다. 이 경우에도 방화벽은 `Private` profile과
`LocalSubnet`으로 제한합니다. VPN·다중 NIC·Public profile·mirrored networking,
IPv6은 자동 추정하지 않습니다.

특정 distro를 선택하려면 이름을 별도 argv로 전달합니다.

```powershell
.\setup.ps1 -Port 5173 -Exposure Loopback -Distro Ubuntu
```

## 격리 smoke test

실제 WSL, portproxy, firewall을 호출하지 않는 전체 mock 테스트입니다.

```powershell
powershell.exe -NoProfile -File .\smoke-test.ps1
pwsh -NoProfile -File .\smoke-test.ps1
```

mock은 소유권 불명 규칙 보존, 다중 IP/mirrored mode 거부, native 실패,
Private/LocalSubnet 범위, setup/uninstall 부분 실패 rollback을 검사합니다.
실제 관리자 권한, NAT, bind, firewall/GPO 동작은 별도 Windows 통합 검증입니다.

## 주의

`portproxy` 규칙은 WSL의 개발 서버를 Windows/LAN에서 접근하려고 일부러 만든 규칙일 수 있습니다. 지우면 해당 포트의 외부 접근이 끊깁니다. 이 도구는 state로 소유권을 입증하지 못한 규칙을 지우지 않습니다.

확실하지 않을 때는 먼저 현재 규칙을 확인하세요.

```powershell
netsh interface portproxy show all
```
