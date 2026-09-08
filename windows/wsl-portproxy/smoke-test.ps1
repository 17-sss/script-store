param(
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Path $PSCommandPath -Parent
$setupPath = Join-Path $scriptDir "setup.ps1"
$uninstallPath = Join-Path $scriptDir "uninstall.ps1"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-Throws {
  param([scriptblock]$Script, [string]$Needle)
  $message = $null
  try { & $Script }
  catch { $message = $_.Exception.Message }
  Assert-True ($null -ne $message) "Expected failure containing: $Needle"
  Assert-True ($message.Contains($Needle)) "Unexpected failure: $message"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wsl-portproxy-smoke-" + [guid]::NewGuid().ToString("N"))
$tempUserProfile = Join-Path $tempRoot "user"
$stateRoot = Join-Path $tempRoot "state"
$previousTestMode = $env:WSL_PORTPROXY_TEST_MODE
$previousStateHome = $env:WSL_PORTPROXY_STATE_HOME
$previousUserProfile = $env:USERPROFILE
$previousLocalAppData = $env:LOCALAPPDATA
$previousStateWriteFailure = $env:WSL_PORTPROXY_TEST_FAIL_STATE_WRITE
$previousStateDeleteFailure = $env:WSL_PORTPROXY_TEST_FAIL_STATE_DELETE
$hadPreviousMockState = Test-Path Variable:\global:ScriptStoreWslPortProxyMock
$previousMockState = if ($hadPreviousMockState) {
  (Get-Variable -Scope Global -Name ScriptStoreWslPortProxyMock).Value
} else { $null }

$global:ScriptStoreWslPortProxyMock = @{
  WslOutput = "172.25.10.4"
  WslExitCode = 0
  NetshAddExitCode = 0
  NetshDeleteExitCode = 0
  FailFirewallCreate = $false
  FailFirewallRemove = $false
  ProxyRules = @{}
  FirewallRules = @{}
  NativeCalls = @()
}

function script:wsl.exe {
  $global:ScriptStoreWslPortProxyMock.NativeCalls += "wsl.exe " + ($args -join " ")
  $global:LASTEXITCODE = $global:ScriptStoreWslPortProxyMock.WslExitCode
  if ($global:ScriptStoreWslPortProxyMock.WslExitCode -eq 0) {
    $global:ScriptStoreWslPortProxyMock.WslOutput
  }
  else { "mock wsl failure" }
}

function script:netsh.exe {
  $global:ScriptStoreWslPortProxyMock.NativeCalls += "netsh.exe " + ($args -join " ")
  $verb = $args[2]

  if ($verb -eq "show") {
    $global:LASTEXITCODE = 0
    "Listen on ipv4:             Connect to ipv4:"
    "Address         Port        Address         Port"
    foreach ($rule in $global:ScriptStoreWslPortProxyMock.ProxyRules.Values) {
      "{0} {1} {2} {3}" -f $rule.ListenAddress, $rule.ListenPort, $rule.ConnectAddress, $rule.ConnectPort
    }
    return
  }

  $listenPortArg = @($args | Where-Object { $_ -like "listenport=*" })[0]
  $listenAddressArg = @($args | Where-Object { $_ -like "listenaddress=*" })[0]
  $port = [int]($listenPortArg -replace "^listenport=", "")
  $listenAddress = $listenAddressArg -replace "^listenaddress=", ""
  $key = "$listenAddress`:$port"

  if ($verb -eq "add") {
    $global:LASTEXITCODE = $global:ScriptStoreWslPortProxyMock.NetshAddExitCode
    if ($global:ScriptStoreWslPortProxyMock.NetshAddExitCode -ne 0) { "mock netsh add failure"; return }
    $connectAddress = (@($args | Where-Object { $_ -like "connectaddress=*" })[0]) -replace "^connectaddress=", ""
    $connectPort = [int]((@($args | Where-Object { $_ -like "connectport=*" })[0]) -replace "^connectport=", "")
    $global:ScriptStoreWslPortProxyMock.ProxyRules[$key] = [pscustomobject]@{
      ListenAddress = $listenAddress
      ListenPort = $port
      ConnectAddress = $connectAddress
      ConnectPort = $connectPort
    }
    return
  }

  if ($verb -eq "delete") {
    $global:LASTEXITCODE = $global:ScriptStoreWslPortProxyMock.NetshDeleteExitCode
    if ($global:ScriptStoreWslPortProxyMock.NetshDeleteExitCode -ne 0) { "mock netsh delete failure"; return }
    $global:ScriptStoreWslPortProxyMock.ProxyRules.Remove($key)
    return
  }

  $global:LASTEXITCODE = 99
  "unexpected mock netsh command"
}

function script:Get-Service {
  [CmdletBinding()]
  param([string]$Name)
  [pscustomobject]@{ Name = $Name; Status = "Running" }
}

function script:Get-NetFirewallRule {
  [CmdletBinding()]
  param([string]$Name)
  if ($global:ScriptStoreWslPortProxyMock.FirewallRules.ContainsKey($Name)) {
    $global:ScriptStoreWslPortProxyMock.FirewallRules[$Name]
  }
}

function script:New-NetFirewallRule {
  [CmdletBinding()]
  param(
    [string]$Name,
    [string]$DisplayName,
    [string]$Group,
    [string]$Direction,
    [string]$Action,
    [string]$Enabled,
    [string]$Profile,
    [string]$Protocol,
    [int]$LocalPort,
    [string]$RemoteAddress
  )
  if ($global:ScriptStoreWslPortProxyMock.FailFirewallCreate) { throw "mock firewall create failure" }
  $rule = [pscustomobject]@{
    Name = $Name
    DisplayName = $DisplayName
    Group = $Group
    Direction = $Direction
    Action = $Action
    Enabled = $Enabled
    Profile = $Profile
    PortFilter = [pscustomobject]@{ Protocol = $Protocol; LocalPort = $LocalPort }
    AddressFilter = [pscustomobject]@{ RemoteAddress = $RemoteAddress }
  }
  $global:ScriptStoreWslPortProxyMock.FirewallRules[$Name] = $rule
  return $rule
}

function script:Remove-NetFirewallRule {
  [CmdletBinding()]
  param([Parameter(ValueFromPipeline = $true)][object]$InputObject)
  process {
    if ($global:ScriptStoreWslPortProxyMock.FailFirewallRemove) { throw "mock firewall remove failure" }
    $global:ScriptStoreWslPortProxyMock.FirewallRules.Remove($InputObject.Name)
  }
}

function script:Get-NetFirewallPortFilter {
  [CmdletBinding()]
  param([Parameter(ValueFromPipeline = $true)][object]$InputObject)
  process { $InputObject.PortFilter }
}

function script:Get-NetFirewallAddressFilter {
  [CmdletBinding()]
  param([Parameter(ValueFromPipeline = $true)][object]$InputObject)
  process { $InputObject.AddressFilter }
}

function Get-StateFile {
  param([string]$Exposure, [int]$Port)
  Join-Path $stateRoot ("{0}-{1}.json" -f $Exposure.ToLowerInvariant(), $Port)
}

try {
  [System.IO.Directory]::CreateDirectory($tempUserProfile) | Out-Null
  $env:WSL_PORTPROXY_TEST_MODE = "1"
  $env:WSL_PORTPROXY_STATE_HOME = $stateRoot
  $env:USERPROFILE = $tempUserProfile
  $env:LOCALAPPDATA = Join-Path $tempRoot "local-app-data"

  # Safe default: loopback only, no firewall, exact ownership state.
  & $setupPath -Port 5173
  Assert-True ($global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("127.0.0.1:5173")) "Loopback proxy was not created"
  Assert-True ($global:ScriptStoreWslPortProxyMock.FirewallRules.Count -eq 0) "Loopback setup created a firewall rule"
  Assert-True ([System.IO.File]::Exists((Get-StateFile Loopback 5173))) "Loopback ownership state missing"
  Assert-True (-not (($global:ScriptStoreWslPortProxyMock.NativeCalls -join "`n") -match "show v4tov4 listen")) "netsh show used unsupported listener selectors"
  $addCount = @($global:ScriptStoreWslPortProxyMock.NativeCalls | Where-Object { $_ -like "netsh.exe interface portproxy add*listenport=5173*" }).Count
  & $setupPath -Port 5173
  $sameAddCount = @($global:ScriptStoreWslPortProxyMock.NativeCalls | Where-Object { $_ -like "netsh.exe interface portproxy add*listenport=5173*" }).Count
  Assert-True ($sameAddCount -eq $addCount) "Idempotent setup recreated an owned proxy"
  & $uninstallPath -Port 5173
  Assert-True (-not $global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("127.0.0.1:5173")) "Loopback proxy was not removed"
  Assert-True (-not [System.IO.File]::Exists((Get-StateFile Loopback 5173))) "Loopback state was not removed"

  # A foreign rule must remain unchanged during setup and uninstall.
  $global:ScriptStoreWslPortProxyMock.ProxyRules["127.0.0.1:6000"] = [pscustomobject]@{
    ListenAddress = "127.0.0.1"; ListenPort = 6000; ConnectAddress = "10.0.0.9"; ConnectPort = 6000
  }
  Assert-Throws { & $setupPath -Port 6000 } "ownership is not recorded"
  Assert-Throws { & $uninstallPath -Port 6000 } "without script-store ownership"
  Assert-True ($global:ScriptStoreWslPortProxyMock.ProxyRules["127.0.0.1:6000"].ConnectAddress -eq "10.0.0.9") "Foreign proxy changed"

  # Ambiguous IP and mirrored networking are rejected before mutation.
  $global:ScriptStoreWslPortProxyMock.WslOutput = "172.25.10.4 172.26.20.5"
  Assert-Throws { & $setupPath -Port 6001 } "exactly one usable WSL IPv4"
  Assert-True (-not $global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("127.0.0.1:6001")) "Ambiguous IP created a proxy"
  $global:ScriptStoreWslPortProxyMock.WslOutput = "172.25.10.4"
  [System.IO.File]::WriteAllText((Join-Path $tempUserProfile ".wslconfig"), "[wsl2]`r`nnetworkingMode=mirrored`r`n")
  Assert-Throws { & $setupPath -Port 6001 } "Only WSL NAT mode is supported"
  [System.IO.File]::Delete((Join-Path $tempUserProfile ".wslconfig"))

  # LAN scope is exact: Private profile and LocalSubnet only.
  & $setupPath -Port 6002 -Exposure Lan -Distro Ubuntu
  Assert-True ($global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("0.0.0.0:6002")) "LAN proxy was not created"
  $firewallName = "ScriptStore-WSL-PortProxy-TCP-Lan-6002"
  Assert-True ($global:ScriptStoreWslPortProxyMock.FirewallRules.ContainsKey($firewallName)) "Owned LAN firewall missing"
  $firewall = $global:ScriptStoreWslPortProxyMock.FirewallRules[$firewallName]
  Assert-True ($firewall.Profile -eq "Private" -and $firewall.AddressFilter.RemoteAddress -eq "LocalSubnet") "LAN firewall scope is too broad"
  Assert-True (($global:ScriptStoreWslPortProxyMock.NativeCalls -join "`n").Contains("wsl.exe -d Ubuntu -- hostname -I")) "Distro was not passed as argv"

  # Firewall drift blocks uninstall without touching either rule.
  $firewall.Profile = "Any"
  Assert-Throws { & $uninstallPath -Port 6002 -Exposure Lan } "firewall rule drifted"
  Assert-True ($global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("0.0.0.0:6002")) "Drift check removed proxy"
  $firewall.Profile = "Private"

  # Firewall removal failure rolls the already-deleted proxy back.
  $global:ScriptStoreWslPortProxyMock.FailFirewallRemove = $true
  Assert-Throws { & $uninstallPath -Port 6002 -Exposure Lan } "mock firewall remove failure"
  Assert-True ($global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("0.0.0.0:6002")) "Uninstall failure did not restore proxy"
  Assert-True ([System.IO.File]::Exists((Get-StateFile Lan 6002))) "Uninstall failure removed ownership state"
  $global:ScriptStoreWslPortProxyMock.FailFirewallRemove = $false
  & $uninstallPath -Port 6002 -Exposure Lan

  # Setup failures roll back every change made by the attempt.
  $global:ScriptStoreWslPortProxyMock.FailFirewallCreate = $true
  Assert-Throws { & $setupPath -Port 6003 -Exposure Lan } "mock firewall create failure"
  Assert-True (-not $global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("0.0.0.0:6003")) "Firewall failure left a proxy"
  Assert-True (-not [System.IO.File]::Exists((Get-StateFile Lan 6003))) "Firewall failure wrote ownership state"
  $global:ScriptStoreWslPortProxyMock.FailFirewallCreate = $false

  $global:ScriptStoreWslPortProxyMock.NetshAddExitCode = 5
  Assert-Throws { & $setupPath -Port 6004 } "exit code 5"
  Assert-True (-not $global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("127.0.0.1:6004")) "netsh failure created a proxy"
  $global:ScriptStoreWslPortProxyMock.NetshAddExitCode = 0

  $env:WSL_PORTPROXY_TEST_FAIL_STATE_WRITE = "1"
  Assert-Throws { & $setupPath -Port 6005 } "ownership state write failure"
  Assert-True (-not $global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("127.0.0.1:6005")) "State-write failure left a proxy"
  $env:WSL_PORTPROXY_TEST_FAIL_STATE_WRITE = $null

  & $setupPath -Port 6006
  $env:WSL_PORTPROXY_TEST_FAIL_STATE_DELETE = "1"
  Assert-Throws { & $uninstallPath -Port 6006 } "ownership state delete failure"
  Assert-True ($global:ScriptStoreWslPortProxyMock.ProxyRules.ContainsKey("127.0.0.1:6006")) "State-delete failure did not restore proxy"
  Assert-True ([System.IO.File]::Exists((Get-StateFile Loopback 6006))) "State-delete failure lost ownership state"
  $env:WSL_PORTPROXY_TEST_FAIL_STATE_DELETE = $null
  & $uninstallPath -Port 6006

  Write-Host "wsl-portproxy isolated mock smoke test passed." -ForegroundColor Green
  Write-Host "Temp root: $tempRoot"
}
finally {
  foreach ($name in @(
    "wsl.exe", "netsh.exe", "Get-Service", "Get-NetFirewallRule",
    "New-NetFirewallRule", "Remove-NetFirewallRule",
    "Get-NetFirewallPortFilter", "Get-NetFirewallAddressFilter"
  )) {
    Remove-Item -LiteralPath ("Function:\script:" + $name) -ErrorAction SilentlyContinue
  }
  $env:WSL_PORTPROXY_TEST_MODE = $previousTestMode
  $env:WSL_PORTPROXY_STATE_HOME = $previousStateHome
  $env:USERPROFILE = $previousUserProfile
  $env:LOCALAPPDATA = $previousLocalAppData
  $env:WSL_PORTPROXY_TEST_FAIL_STATE_WRITE = $previousStateWriteFailure
  $env:WSL_PORTPROXY_TEST_FAIL_STATE_DELETE = $previousStateDeleteFailure
  if ($hadPreviousMockState) {
    Set-Variable -Scope Global -Name ScriptStoreWslPortProxyMock -Value $previousMockState
  }
  else {
    Remove-Variable -Scope Global -Name ScriptStoreWslPortProxyMock -ErrorAction SilentlyContinue
  }
  if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
