param (
  [ValidateRange(1, 65535)]
  [int]$Port = 5173
)

$ErrorActionPreference = "Stop"

$ruleName = "WSL PortProxy $Port"

Write-Output "=== WSL portproxy setup ==="
Write-Output "[INFO] Target port = $Port"

$wslIpOutput = wsl hostname -I 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "Could not get WSL IP. Is WSL running? $wslIpOutput"
}

$wslIp = ($wslIpOutput -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($wslIp)) {
  throw "Could not parse WSL IP from: $wslIpOutput"
}

Write-Output "[INFO] WSL IP = $wslIp"

Write-Output "[STEP] Remove old portproxy rule if it exists"
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>$null | Out-Null

Write-Output "[STEP] Add portproxy rule"
netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectaddress=$wslIp connectport=$Port

Write-Output "[STEP] Check firewall rule"
$rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($rule) {
  Write-Output "[INFO] Firewall rule already exists: $ruleName"
}
else {
  New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
  Write-Output "[INFO] Firewall rule added: $ruleName"
}

$winIp = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object {
    $_.IPAddress -notmatch "^127\." -and
    $_.IPAddress -notmatch "^169\.254\." -and
    $_.PrefixOrigin -ne "WellKnown"
  } |
  Select-Object -First 1 -ExpandProperty IPAddress

Write-Output "=== Done ==="
if (-not [string]::IsNullOrWhiteSpace($winIp)) {
  Write-Output "[INFO] Open from another device: http://$winIp`:$Port/"
}
Write-Output "[INFO] Local portproxy: 0.0.0.0:$Port -> $wslIp`:$Port"
