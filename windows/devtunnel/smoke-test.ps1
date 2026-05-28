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
$previousSshDir = $env:DEVTUNNEL_SSH_DIR

try {
  New-Item -ItemType Directory -Path $tempUserProfile -Force | Out-Null
  New-Item -ItemType Directory -Path $tempSshDir -Force | Out-Null

  $env:USERPROFILE = $tempUserProfile
  $env:DEVTUNNEL_PROFILE_PATH = $tempProfilePath
  $env:DEVTUNNEL_SSH_DIR = $tempSshDir

  & $managerPath install `
    -HostAlias "smoke-dev" `
    -HostName "127.0.0.1" `
    -SshUser "devuser" `
    -SshPort 2222 `
    -SkipIdentityFile `
    -DefaultPorts 3000,5173 `
    -Yes

  $profileContent = Get-FileText $tempProfilePath
  $sshConfigPath = Join-Path $tempSshDir "config"
  $sshConfigContent = Get-FileText $sshConfigPath

  Assert-Contains $profileContent "function devtunnel"
  Assert-Contains $profileContent "[Alias(""h"")]"
  Assert-Contains $profileContent "Get-Help devtunnel -Detailed"
  Assert-Contains $sshConfigContent "# >>> devtunnel ssh host: smoke-dev >>>"
  Assert-Contains $sshConfigContent "Host smoke-dev"
  Assert-Contains $sshConfigContent "HostName 127.0.0.1"
  Assert-Contains $sshConfigContent "User devuser"
  Assert-Contains $sshConfigContent "Port 2222"
  Assert-NotContains $sshConfigContent "IdentityFile"

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

  & $managerPath reinstall `
    -HostAlias "smoke-dev-next" `
    -HostName "127.0.0.2" `
    -SshUser "devuser2" `
    -SshPort 22 `
    -IdentityFile (Join-Path $tempUserProfile ".ssh\id_ed25519") `
    -DefaultPorts 6006 `
    -Yes

  $profileContent = Get-FileText $tempProfilePath
  $sshConfigContent = Get-FileText $sshConfigPath

  Assert-NotContains $sshConfigContent "# >>> devtunnel ssh host: smoke-dev >>>"
  Assert-Contains $sshConfigContent "# >>> devtunnel ssh host: smoke-dev-next >>>"
  Assert-Contains $sshConfigContent "Host smoke-dev-next"
  Assert-Contains $sshConfigContent "HostName 127.0.0.2"
  Assert-Contains $sshConfigContent "User devuser2"
  Assert-Contains $sshConfigContent "IdentityFile"
  Assert-Contains $profileContent '[int[]]$Ports = @(6006)'
  Assert-Contains $profileContent '[string]$HostAlias = "smoke-dev-next"'

  & $managerPath remove -RemoveSshBlocks -Yes

  $profileContent = Get-FileText $tempProfilePath
  $sshConfigContent = Get-FileText $sshConfigPath

  Assert-NotContains $profileContent "# >>> devtunnel function >>>"
  Assert-NotContains $sshConfigContent "# >>> devtunnel ssh host:"

  Write-Host "devtunnel smoke test passed." -ForegroundColor Green
  Write-Host "Temp root: $tempRoot"
}
finally {
  $env:USERPROFILE = $previousUserProfile
  $env:DEVTUNNEL_PROFILE_PATH = $previousProfilePath
  $env:DEVTUNNEL_SSH_DIR = $previousSshDir

  if (-not $KeepTemp -and (Test-Path $tempRoot)) {
    Remove-Item -Path $tempRoot -Recurse -Force
  }
}
