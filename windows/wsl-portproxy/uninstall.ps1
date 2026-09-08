param (
  [ValidateRange(1, 65535)]
  [int]$Port = 5173,

  [ValidateSet("Loopback", "Lan")]
  [string]$Exposure = "Loopback"
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
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string[]]$Arguments
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
    $state.firewall_name -cne $firewallName -or
    [string]::IsNullOrWhiteSpace($state.connect_address)
  ) {
    throw "Ownership state does not match this request: $Path"
  }
  return $state
}

function Get-PortProxyRule {
  # The show form has no per-listener selectors, so enumerate v4tov4 and
  # select only the exact address/port row ourselves.
  $output = Invoke-NativeChecked -Command "netsh.exe" -Arguments @(
    "interface", "portproxy", "show", "v4tov4"
  )
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

function New-OwnedFirewallRule {
  $parameters = @{
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
  New-NetFirewallRule @parameters | Out-Null
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
$statePath = Get-StatePath
$state = Read-OwnedState -Path $statePath
$existingProxy = Get-PortProxyRule
$existingFirewall = if ($Exposure -eq "Lan") {
  Get-NetFirewallRule -Name $firewallName -ErrorAction SilentlyContinue
} else { $null }

if ($null -eq $state) {
  if ($null -ne $existingProxy -or $null -ne $existingFirewall) {
    throw "Matching network state exists without script-store ownership. No changes made."
  }
  Write-Output "No owned WSL portproxy state for $listenAddress`:$Port; nothing changed."
  return
}

if (
  $null -eq $existingProxy -or
  $existingProxy.ConnectAddress -cne $state.connect_address -or
  $existingProxy.ConnectPort -ne [int]$state.connect_port
) {
  throw "The portproxy rule is missing or drifted from ownership state. No changes made."
}
if ($Exposure -eq "Lan" -and $null -eq $existingFirewall) {
  throw "The owned firewall rule is missing. No changes made."
}
if ($Exposure -eq "Lan") {
  Assert-OwnedFirewallRule -Rule $existingFirewall
}

Write-Output "=== WSL portproxy uninstall plan ==="
Write-Output "[INFO] Remove owned proxy $listenAddress`:$Port -> $($state.connect_address)`:$Port"
if ($Exposure -eq "Lan") {
  Write-Output "[INFO] Remove owned firewall rule $firewallName"
}
Write-Output "[INFO] Ownership state = $statePath"

$proxyRemoved = $false
$firewallRemoved = $false
try {
  Remove-PortProxyRule
  $proxyRemoved = $true
  if ($Exposure -eq "Lan") {
    $existingFirewall | Remove-NetFirewallRule -ErrorAction Stop
    $firewallRemoved = $true
  }
  if ($env:WSL_PORTPROXY_TEST_FAIL_STATE_DELETE -eq "1") {
    throw "test-only ownership state delete failure"
  }
  [System.IO.File]::Delete($statePath)
}
catch {
  $originalError = $_
  if ($firewallRemoved) {
    try { New-OwnedFirewallRule }
    catch { Write-Warning "Rollback failed while restoring firewall rule: $($_.Exception.Message)" }
  }
  if ($proxyRemoved) {
    try { Add-PortProxyRule -ConnectAddress $state.connect_address }
    catch { Write-Warning "Rollback failed while restoring portproxy: $($_.Exception.Message)" }
  }
  throw $originalError
}

Write-Output "=== Done ==="
Write-Output "[INFO] Removed only the exact script-store-owned $Exposure rule for port $Port."
