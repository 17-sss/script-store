param(
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Path $PSCommandPath -Parent
$managerPath = Join-Path $scriptDir "devtunnel-manager.ps1"

function Assert-True {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
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

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [string]$Needle
  )

  Assert-True -Condition $Text.Contains($Needle) -Message "Expected text to contain: $Needle"
}

function Assert-NotContains {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [string]$Needle
  )

  Assert-True -Condition (-not $Text.Contains($Needle)) -Message "Expected text not to contain: $Needle"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devtunnel-smoke-" + [guid]::NewGuid().ToString("N"))
$tempUserProfile = Join-Path $tempRoot "user"
$tempProfilePath = Join-Path $tempRoot "profile.ps1"
$tempSshDir = Join-Path $tempRoot ".ssh"

$previousUserProfile = $env:USERPROFILE
$previousProfilePath = $env:DEVTUNNEL_PROFILE_PATH

try {
  New-Item -ItemType Directory -Path $tempUserProfile -Force | Out-Null

  $env:USERPROFILE = $tempUserProfile
  $env:DEVTUNNEL_PROFILE_PATH = $tempProfilePath

  & $managerPath install -Yes

  $profileContent = Get-FileText $tempProfilePath
  $sshConfigPath = Join-Path $tempSshDir "config"

  Assert-Contains $profileContent "function devtunnel"
  Assert-Contains $profileContent "[Parameter(Position = 0)]"
  Assert-Contains $profileContent "[Parameter(Position = 1)]"
  Assert-Contains $profileContent "[Alias(""h"")]"
  Assert-Contains $profileContent "Get-Help devtunnel -Detailed"
  Assert-Contains $profileContent "devtunnel 3000,5173,6006 prox-dev-hoyoung"
  Assert-True -Condition (-not (Test-Path $sshConfigPath)) -Message "Install should not create SSH config"

  . $tempProfilePath

  $syntax = Get-Command devtunnel -Syntax | Out-String
  Assert-Contains $syntax "-Ports"
  Assert-Contains $syntax "-HostAlias"
  Assert-Contains $syntax "-Help"

  $detailedHelp = Get-Help devtunnel -Detailed | Out-String
  Assert-Contains $detailedHelp "Opens SSH local port forwards"

  $helpOutput = & { devtunnel -Help } *>&1 | Out-String
  Assert-Contains $helpOutput "Usage:"

  $shortHelpOutput = & { devtunnel -h } *>&1 | Out-String
  Assert-Contains $shortHelpOutput "Usage:"

  $missingArgsOutput = & { devtunnel } *>&1 | Out-String
  Assert-Contains $missingArgsOutput "Ports and SSH host alias are required."

  $script:CapturedSshArgs = @()

  function ssh {
    $script:CapturedSshArgs = $args
  }

  devtunnel 3000,5173 smoke-dev
  $captured = $script:CapturedSshArgs -join "|"
  Assert-Contains $captured "-N|-L|3000:127.0.0.1:3000|-L|5173:127.0.0.1:5173|smoke-dev"

  devtunnel -Ports 6006 -HostAlias smoke-dev-next
  $captured = $script:CapturedSshArgs -join "|"
  Assert-Contains $captured "-N|-L|6006:127.0.0.1:6006|smoke-dev-next"

  & $managerPath reinstall -Yes

  $profileContent = Get-FileText $tempProfilePath
  Assert-Contains $profileContent "function devtunnel"
  Assert-True -Condition (-not (Test-Path $sshConfigPath)) -Message "Reinstall should not create SSH config"

  & $managerPath uninstall -Yes

  $profileContent = Get-FileText $tempProfilePath

  Assert-NotContains $profileContent "# >>> devtunnel function >>>"
  Assert-True -Condition (-not (Test-Path $sshConfigPath)) -Message "Uninstall should not create SSH config"

  Write-Host "devtunnel smoke test passed." -ForegroundColor Green
  Write-Host "Temp root: $tempRoot"
}
finally {
  $env:USERPROFILE = $previousUserProfile
  $env:DEVTUNNEL_PROFILE_PATH = $previousProfilePath

  if (-not $KeepTemp -and (Test-Path $tempRoot)) {
    Remove-Item -Path $tempRoot -Recurse -Force
  }
}
