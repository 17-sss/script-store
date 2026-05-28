param(
  [ValidateSet("install", "remove", "uninstall", "reinstall")]
  [string]$Action = "install",

  [switch]$Yes
)

if ([string]::IsNullOrWhiteSpace($env:DEVTUNNEL_PROFILE_PATH)) {
  $profilePath = $PROFILE
}
else {
  $profilePath = $env:DEVTUNNEL_PROFILE_PATH
}

$profileStartMarker = "# >>> devtunnel function >>>"
$profileEndMarker = "# <<< devtunnel function <<<"

function Ensure-File {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $dir = Split-Path $Path -Parent

  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  if (-not (Test-Path $Path)) {
    New-Item -ItemType File -Path $Path -Force | Out-Null
  }
}

function Get-FileText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    return ""
  }

  $content = Get-Content $Path -Raw

  if ($null -eq $content) {
    return ""
  }

  return $content
}

function Remove-ProfileBlock {
  if (-not (Test-Path $profilePath)) {
    return
  }

  $content = Get-FileText $profilePath
  $pattern = [regex]::Escape($profileStartMarker) + "[\s\S]*?" + [regex]::Escape($profileEndMarker) + "(\r?\n)?"
  $newContent = [regex]::Replace($content, $pattern, "")

  Set-Content -Path $profilePath -Value $newContent -Encoding UTF8
}

function Install-ProfileBlock {
  Ensure-File $profilePath
  Remove-ProfileBlock

  $functionBlock = @"
$profileStartMarker
function devtunnel {
<#
.SYNOPSIS
Opens SSH local port forwards to a remote development host.

.DESCRIPTION
Opens one or more Windows localhost ports and forwards them to the same ports on
127.0.0.1 behind the SSH config host alias passed at run time.

.PARAMETER Ports
Local ports to forward. Each local port maps to the same remote port.

.PARAMETER HostAlias
SSH config host alias to connect through.

.PARAMETER Help
Shows usage examples and exits.

.EXAMPLE
devtunnel 3123 prox-dev-hoyoung

.EXAMPLE
devtunnel 3000,5173,6006 prox-dev-hoyoung

.EXAMPLE
devtunnel -Ports 3123 -HostAlias prox-dev-hoyoung
#>
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)]
    [ValidateRange(1, 65535)]
    [int[]]`$Ports,

    [Parameter(Position = 1)]
    [string]`$HostAlias,

    [Alias("h")]
    [switch]`$Help
  )

  function Show-DevTunnelHelp {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  devtunnel <ports> <ssh-host-alias>"
    Write-Host "  devtunnel 3123 prox-dev-hoyoung"
    Write-Host "  devtunnel 3000,5173,6006 prox-dev-hoyoung"
    Write-Host "  devtunnel -Ports 3123 -HostAlias prox-dev-hoyoung"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  -Ports      One or more local ports. Multiple ports use commas."
    Write-Host "  -HostAlias  SSH config host alias."
    Write-Host "  -Help       Show this help. Also accepts -h."
    Write-Host ""
    Write-Host "Close:"
    Write-Host "  Press Ctrl + C in this terminal."
    Write-Host ""
    Write-Host "More:"
    Write-Host "  Get-Help devtunnel -Detailed"
  }

  if (`$Help) {
    Show-DevTunnelHelp
    return
  }

  if (`$null -eq `$Ports -or `$Ports.Count -eq 0 -or [string]::IsNullOrWhiteSpace(`$HostAlias)) {
    Write-Host "Ports and SSH host alias are required." -ForegroundColor Yellow
    Write-Host ""
    Show-DevTunnelHelp
    return
  }

  `$sshArgs = @("-N")

  foreach (`$port in `$Ports) {
    `$sshArgs += "-L"
    `$sshArgs += ("{0}:127.0.0.1:{0}" -f `$port)
  }

  `$sshArgs += `$HostAlias

  Write-Host ""
  Write-Host "Opening SSH tunnel..." -ForegroundColor Cyan

  foreach (`$port in `$Ports) {
    Write-Host ("  http://localhost:{0} -> {1}:127.0.0.1:{0}" -f `$port, `$HostAlias)
  }

  Write-Host ""
  Write-Host "Press Ctrl + C to close the tunnel." -ForegroundColor Yellow
  Write-Host ""

  ssh @sshArgs
}
$profileEndMarker
"@

  $content = Get-FileText $profilePath

  if (-not [string]::IsNullOrWhiteSpace($content) -and -not $content.EndsWith("`n")) {
    Add-Content -Path $profilePath -Value ""
  }

  Add-Content -Path $profilePath -Value $functionBlock -Encoding UTF8
}

function Install-All {
  Install-ProfileBlock

  Write-Host ""
  Write-Host "devtunnel installed." -ForegroundColor Green
  Write-Host ""
  Write-Host "PowerShell profile:"
  Write-Host "  $profilePath"
  Write-Host ""
  Write-Host "Load devtunnel in this PowerShell session:"
  Write-Host "  . `$PROFILE"
  Write-Host "Or restart PowerShell before running devtunnel."
  Write-Host ""
  Write-Host "Examples:"
  Write-Host "  devtunnel 3123 prox-dev-hoyoung"
  Write-Host "  devtunnel 3000,5173,6006 prox-dev-hoyoung"
  Write-Host "  devtunnel -Ports 3123 -HostAlias prox-dev-hoyoung"
}

function Remove-All {
  Remove-ProfileBlock
  Write-Host "devtunnel function removed." -ForegroundColor Green
}

switch ($Action) {
  "install" {
    Install-All
  }

  "remove" {
    Remove-All
  }

  "uninstall" {
    Remove-All
  }

  "reinstall" {
    Install-All
  }
}
