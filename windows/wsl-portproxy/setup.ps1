param (
  [ValidateRange(1, 65535)]
  [int]$Port = 5173,

  [ValidateSet("Loopback", "Lan")]
  [string]$Exposure = "Loopback",

  [string]$Distro
)

$ErrorActionPreference = "Stop"
$owner = "script-store/wsl-portproxy"
$listenAddress = if ($Exposure -eq "Lan") { "0.0.0.0" } else { "127.0.0.1" }
$firewallName = "ScriptStore-WSL-PortProxy-TCP-$Exposure-$Port"
$firewallDisplayName = "script-store WSL PortProxy TCP $Exposure $Port"

function Assert-Administrator {
  if ($env:WSL_PORTPROXY_TEST_MODE -eq "1") { return }
  if ($env:OS -ne "Windows_NT") { throw "This script only supports Windows." }
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an Administrator PowerShell."
  }
}

function Invoke-NativeChecked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $output = & $Command @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode) { $exitCode = 0 }
  if ($exitCode -ne 0) {
    throw "$Command failed with exit code $exitCode`: $($output -join [Environment]::NewLine)"
  }
  return ,$output
}

function Get-StatePath {
  $root = $env:WSL_PORTPROXY_STATE_HOME
  if ([string]::IsNullOrWhiteSpace($root)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
      throw "LOCALAPPDATA is not set; set WSL_PORTPROXY_STATE_HOME explicitly."
    }
    $root = Join-Path $env:LOCALAPPDATA "script-store\wsl-portproxy"
  }
  $root = [System.IO.Path]::GetFullPath($root)
  return Join-Path $root ("{0}-{1}.json" -f $Exposure.ToLowerInvariant(), $Port)
}

function Read-OwnedState {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not [System.IO.File]::Exists($Path)) { return $null }
  try { $state = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
  catch { throw "Could not read ownership state $Path`: $($_.Exception.Message)" }
  if (
    $state.schema_version -ne 1 -or
    $state.owner -cne $owner -or
    [int]$state.port -ne $Port -or
    $state.exposure -cne $Exposure -or
    $state.listen_address -cne $listenAddress -or
    [int]$state.connect_port -ne $Port -or
    $state.firewall_name -cne $firewallName
  ) {
    throw "Ownership state does not match this request: $Path"
  }
  return $state
}

function Write-OwnedStateAtomically {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$State
  )
  $directory = [System.IO.Path]::GetDirectoryName($Path)
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = Join-Path $directory (".state-" + [guid]::NewGuid().ToString("N") + ".tmp")
  $backup = $temporary + ".backup"
  try {
    $json = $State | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    if ($env:WSL_PORTPROXY_TEST_FAIL_STATE_WRITE -eq "1") {
      throw "test-only ownership state write failure"
    }
    if ([System.IO.File]::Exists($Path)) {
      [System.IO.File]::Replace($temporary, $Path, $backup, $true)
      if ([System.IO.File]::Exists($backup)) {
        try { [System.IO.File]::Delete($backup) }
        catch { Write-Warning "Atomic ownership-state backup could not be removed: $backup" }
      }
    }
    else {
      [System.IO.File]::Move($temporary, $Path)
    }
  }
  finally {
    if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-NatMode {
  if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return }
  $wslConfig = Join-Path $env:USERPROFILE ".wslconfig"
  if (-not [System.IO.File]::Exists($wslConfig)) { return }
  $modes = @()
  foreach ($line in [System.IO.File]::ReadAllLines($wslConfig)) {
    $withoutComment = ($line -split "#", 2)[0]
    if ($withoutComment -match "^\s*networkingMode\s*=\s*([^\s]+)\s*$") {
      $modes += $Matches[1].ToLowerInvariant()
    }
  }
  if ($modes.Count -gt 1) { throw "Multiple networkingMode values found in $wslConfig" }
  if ($modes.Count -eq 1 -and $modes[0] -ne "nat") {
    throw "Only WSL NAT mode is supported; configured networkingMode=$($modes[0])."
  }
}

function Get-SingleWslIPv4 {
  $arguments = @()
  if (-not [string]::IsNullOrWhiteSpace($Distro)) {
    $arguments += "-d"
    $arguments += $Distro
    $arguments += "--"
  }
  $arguments += "hostname"
  $arguments += "-I"
  $output = Invoke-NativeChecked -Command "wsl.exe" -Arguments $arguments
  $candidates = @()
  foreach ($token in (($output -join " ") -split "\s+")) {
    if ([string]::IsNullOrWhiteSpace($token)) { continue }
    $parsed = $null
    $isPrivate = $false
    $parsedOk = [System.Net.IPAddress]::TryParse($token, [ref]$parsed)
    if ($parsedOk -and $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
      $octets = $parsed.GetAddressBytes()
      $first = [int]$octets[0]
      $second = [int]$octets[1]
      $isPrivate = (
        $first -eq 10 -or
        ($first -eq 172 -and $second -ge 16 -and $second -le 31) -or
        ($first -eq 192 -and $second -eq 168)
      )
    }
    if (
      $parsedOk -and
      $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
      $isPrivate
    ) {
      $candidates += $parsed.ToString()
    }
  }
  $candidates = @($candidates | Select-Object -Unique)
  if ($candidates.Count -ne 1) {
    throw "Expected exactly one usable WSL IPv4 address; found $($candidates.Count): $($candidates -join ', ')"
  }
  return $candidates[0]
}

function Get-PortProxyRule {
  # The show form has no per-listener selectors, so enumerate v4tov4 and
  # select only the exact address/port row ourselves.
  $arguments = @("interface", "portproxy", "show", "v4tov4")
  $output = Invoke-NativeChecked -Command "netsh.exe" -Arguments $arguments
  $rows = @()
  foreach ($line in $output) {
    if ($line -match "^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s+(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s*$") {
      if ($Matches[1] -eq $listenAddress -and [int]$Matches[2] -eq $Port) {
        $rows += [pscustomobject]@{
          ListenAddress = $Matches[1]
          ListenPort = [int]$Matches[2]
          ConnectAddress = $Matches[3]
          ConnectPort = [int]$Matches[4]
        }
      }
    }
  }
  if ($rows.Count -gt 1) { throw "Multiple matching portproxy rules were returned." }
  if ($rows.Count -eq 0) { return $null }
  return $rows[0]
}

function Add-PortProxyRule {
  param([Parameter(Mandatory = $true)][string]$ConnectAddress)
  Invoke-NativeChecked -Command "netsh.exe" -Arguments @(
    "interface", "portproxy", "add", "v4tov4",
    "listenport=$Port", "listenaddress=$listenAddress",
    "connectaddress=$ConnectAddress", "connectport=$Port"
  ) | Out-Null
}

function Remove-PortProxyRule {
  Invoke-NativeChecked -Command "netsh.exe" -Arguments @(
    "interface", "portproxy", "delete", "v4tov4",
    "listenport=$Port", "listenaddress=$listenAddress"
  ) | Out-Null
}

function Assert-OwnedFirewallRule {
  param([Parameter(Mandatory = $true)][object]$Rule)
  $rules = @($Rule)
  if ($rules.Count -ne 1) { throw "Expected exactly one owned firewall rule: $firewallName" }
  $item = $rules[0]
  if (
    $item.Name -cne $firewallName -or
    $item.DisplayName -cne $firewallDisplayName -or
    $item.Group -cne $owner -or
    $item.Direction.ToString() -cne "Inbound" -or
    $item.Action.ToString() -cne "Allow" -or
    $item.Enabled.ToString() -cne "True" -or
    $item.Profile.ToString() -cne "Private"
  ) {
    throw "The firewall rule drifted from its recorded script-store identity. No changes made."
  }
  $portFilters = @($item | Get-NetFirewallPortFilter -ErrorAction Stop)
  $addressFilters = @($item | Get-NetFirewallAddressFilter -ErrorAction Stop)
  if (
    $portFilters.Count -ne 1 -or
    $portFilters[0].Protocol.ToString() -cne "TCP" -or
    $portFilters[0].LocalPort.ToString() -cne $Port.ToString() -or
    $addressFilters.Count -ne 1 -or
    (@($addressFilters[0].RemoteAddress) -join ",") -cne "LocalSubnet"
  ) {
    throw "The firewall filters drifted from the owned TCP/LocalSubnet scope. No changes made."
  }
}

Assert-Administrator
Assert-NatMode
$service = Get-Service -Name "iphlpsvc" -ErrorAction Stop
if ($service.Status -ne "Running") {
  throw "IP Helper (iphlpsvc) is not running. This script will not start or reconfigure the service."
}

$wslIp = Get-SingleWslIPv4
$statePath = Get-StatePath
$state = Read-OwnedState -Path $statePath
$existingProxy = Get-PortProxyRule
$existingFirewall = if ($Exposure -eq "Lan") {
  Get-NetFirewallRule -Name $firewallName -ErrorAction SilentlyContinue
} else { $null }

if ($null -ne $existingProxy) {
  if ($null -eq $state) {
    throw "A portproxy rule already owns $listenAddress`:$Port, but script-store ownership is not recorded. No changes made."
  }
  if (
    $existingProxy.ConnectAddress -cne $state.connect_address -or
    $existingProxy.ConnectPort -ne [int]$state.connect_port
  ) {
    throw "The existing portproxy rule drifted from recorded ownership. No changes made."
  }
}
elseif ($null -ne $state) {
  throw "Ownership state exists but the recorded portproxy rule is missing. No changes made."
}

if ($Exposure -eq "Lan") {
  if ($null -ne $existingFirewall -and $null -eq $state) {
    throw "Firewall rule name already exists without script-store ownership: $firewallName"
  }
  if ($null -eq $existingFirewall -and $null -ne $state) {
    throw "Ownership state exists but the recorded firewall rule is missing. No changes made."
  }
  if ($null -ne $existingFirewall -and $null -ne $state) {
    Assert-OwnedFirewallRule -Rule $existingFirewall
  }
}

Write-Output "=== WSL portproxy setup plan ==="
Write-Output "[INFO] Scope = WSL NAT only"
Write-Output "[INFO] Exposure = $Exposure"
Write-Output "[INFO] Listen = $listenAddress`:$Port"
Write-Output "[INFO] Connect = $wslIp`:$Port"
if ($Exposure -eq "Lan") {
  Write-Warning "LAN exposure allows TCP $Port from LocalSubnet on Private profiles."
}
else {
  Write-Output "[INFO] No inbound firewall rule is created for loopback-only exposure."
}

$oldConnectAddress = if ($null -ne $existingProxy) { $existingProxy.ConnectAddress } else { $null }
$proxyChanged = $false
$firewallCreated = $false
try {
  if ($null -eq $existingProxy -or $existingProxy.ConnectAddress -cne $wslIp) {
    if ($null -ne $existingProxy) { Remove-PortProxyRule }
    try { Add-PortProxyRule -ConnectAddress $wslIp }
    catch {
      if ($null -ne $oldConnectAddress) {
        try { Add-PortProxyRule -ConnectAddress $oldConnectAddress }
        catch { Write-Warning "Rollback failed while restoring portproxy: $($_.Exception.Message)" }
      }
      throw
    }
    $proxyChanged = $true
  }

  if ($Exposure -eq "Lan" -and $null -eq $existingFirewall) {
    $firewallParameters = @{
      Name = $firewallName
      DisplayName = $firewallDisplayName
      Group = $owner
      Direction = "Inbound"
      Action = "Allow"
      Enabled = "True"
      Profile = "Private"
      Protocol = "TCP"
      LocalPort = $Port
      RemoteAddress = "LocalSubnet"
      ErrorAction = "Stop"
    }
    New-NetFirewallRule @firewallParameters | Out-Null
    $firewallCreated = $true
  }

  $newState = [ordered]@{
    schema_version = 1
    owner = $owner
    port = $Port
    exposure = $Exposure
    listen_address = $listenAddress
    connect_address = $wslIp
    connect_port = $Port
    firewall_name = $firewallName
    firewall_created = ($Exposure -eq "Lan")
    distro = $Distro
    updated_at = [DateTimeOffset]::Now.ToString("o")
  }
  Write-OwnedStateAtomically -Path $statePath -State $newState
}
catch {
  $originalError = $_
  if ($firewallCreated) {
    try { Get-NetFirewallRule -Name $firewallName -ErrorAction Stop | Remove-NetFirewallRule -ErrorAction Stop }
    catch { Write-Warning "Rollback failed while removing firewall rule: $($_.Exception.Message)" }
  }
  if ($proxyChanged) {
    try { Remove-PortProxyRule }
    catch { Write-Warning "Rollback failed while removing new portproxy: $($_.Exception.Message)" }
    if ($null -ne $oldConnectAddress) {
      try { Add-PortProxyRule -ConnectAddress $oldConnectAddress }
      catch { Write-Warning "Rollback failed while restoring old portproxy: $($_.Exception.Message)" }
    }
  }
  throw $originalError
}

Write-Output "=== Done ==="
Write-Output "[INFO] Owned state = $statePath"
Write-Output "[INFO] Portproxy: $listenAddress`:$Port -> $wslIp`:$Port"
if ($Exposure -eq "Lan") {
  Write-Output "[INFO] LAN URL uses a Windows Private-profile address and LocalSubnet access only."
}
