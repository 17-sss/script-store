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
  if (-not $Condition) { throw $Message }
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

function Assert-Throws {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Script,

    [Parameter(Mandatory = $true)]
    [string]$Needle
  )

  $message = $null
  try { & $Script }
  catch { $message = $_.Exception.Message }
  Assert-True -Condition ($null -ne $message) -Message "Expected command to fail: $Needle"
  Assert-Contains -Text $message -Needle $Needle
}

function Assert-BytesEqual {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Expected,

    [Parameter(Mandatory = $true)]
    [byte[]]$Actual,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $equal = [System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($Expected, $Actual)
  Assert-True -Condition $equal -Message $Message
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devtunnel-smoke-" + [guid]::NewGuid().ToString("N"))
$tempUserProfile = Join-Path $tempRoot "user"
$tempProfilePath = Join-Path $tempRoot "profile[fixture].ps1"
$tempSshDir = Join-Path $tempRoot ".ssh"

$previousUserProfile = $env:USERPROFILE
$previousProfilePath = $env:DEVTUNNEL_PROFILE_PATH
$previousFailureInjection = $env:DEVTUNNEL_TEST_FAIL_BEFORE_REPLACE

try {
  [System.IO.Directory]::CreateDirectory($tempUserProfile) | Out-Null
  $env:USERPROFILE = $tempUserProfile
  $env:DEVTUNNEL_PROFILE_PATH = $tempProfilePath

  # UTF-8 BOM, CRLF, Korean text, wildcard-looking path, and no final newline.
  $originalText = "# 기존 사용자 profile`r`n`$global:DevTunnelSentinel = '보존'"
  $utf8Bom = [System.Text.UTF8Encoding]::new($true, $true)
  [System.IO.File]::WriteAllText($tempProfilePath, $originalText, $utf8Bom)
  $originalBytes = [System.IO.File]::ReadAllBytes($tempProfilePath)

  & $managerPath install -Yes
  $installedBytes = [System.IO.File]::ReadAllBytes($tempProfilePath)
  $profileContent = [System.IO.File]::ReadAllText($tempProfilePath, $utf8Bom)
  $sshConfigPath = Join-Path $tempSshDir "config"

  Assert-Contains $profileContent "function devtunnel"
  Assert-Contains $profileContent "# devtunnel-manager:2 prefix-newline=inserted"
  Assert-Contains $profileContent "[Parameter(Position = 0)]"
  Assert-Contains $profileContent "[Parameter(Position = 1)]"
  Assert-Contains $profileContent "[Alias(""h"")]"
  Assert-Contains $profileContent "ExitOnForwardFailure=yes"
  Assert-Contains $profileContent "127.0.0.1:{0}:127.0.0.1:{0}"
  Assert-Contains $profileContent "Get-Help devtunnel -Detailed"
  Assert-True -Condition ($installedBytes[0] -eq 0xEF -and $installedBytes[1] -eq 0xBB -and $installedBytes[2] -eq 0xBF) -Message "UTF-8 BOM was not preserved"
  Assert-True -Condition ($profileContent.Contains("`r`n")) -Message "CRLF was not preserved"
  Assert-True -Condition (-not (Test-Path -LiteralPath $sshConfigPath)) -Message "Install should not create SSH config"

  & $managerPath reinstall -Yes
  Assert-BytesEqual -Expected $installedBytes -Actual ([System.IO.File]::ReadAllBytes($tempProfilePath)) -Message "Idempotent reinstall changed profile bytes"

  . $tempProfilePath
  $syntax = Get-Command devtunnel -Syntax | Out-String
  Assert-Contains $syntax "-Ports"
  Assert-Contains $syntax "-HostAlias"
  Assert-Contains $syntax "-Help"

  $detailedHelp = Get-Help devtunnel -Detailed | Out-String
  Assert-Contains $detailedHelp "Opens SSH local port forwards"
  Assert-Contains (& { devtunnel -Help } *>&1 | Out-String) "Usage:"
  Assert-Contains (& { devtunnel -h } *>&1 | Out-String) "Usage:"
  Assert-Contains (& { devtunnel } *>&1 | Out-String) "Ports and SSH host alias are required."

  $script:CapturedSshArgs = @()
  $script:MockSshExitCode = 0
  function ssh {
    $script:CapturedSshArgs = $args
    $global:LASTEXITCODE = $script:MockSshExitCode
  }

  devtunnel 3000,5173 smoke-dev
  $captured = $script:CapturedSshArgs -join "|"
  Assert-Contains $captured "-o|ExitOnForwardFailure=yes|-N|-L|127.0.0.1:3000:127.0.0.1:3000|-L|127.0.0.1:5173:127.0.0.1:5173|smoke-dev"

  $beforeRejectedCall = $script:CapturedSshArgs -join "|"
  Assert-Throws -Script { devtunnel 3000 "-Fbad" } -Needle "must not begin"
  Assert-Throws -Script { devtunnel 3000 "bad alias" } -Needle "contain whitespace"
  Assert-Throws -Script { devtunnel 3000,3000 smoke-dev } -Needle "Duplicate local ports"
  Assert-True -Condition (($script:CapturedSshArgs -join "|") -ceq $beforeRejectedCall) -Message "Rejected input reached ssh"

  $script:MockSshExitCode = 23
  Assert-Throws -Script { devtunnel 6006 smoke-fail } -Needle "exit code 23"
  Assert-True -Condition ($global:LASTEXITCODE -eq 23) -Message "ssh exit code was not preserved"
  $script:MockSshExitCode = 0

  & $managerPath uninstall -Yes
  Assert-BytesEqual -Expected $originalBytes -Actual ([System.IO.File]::ReadAllBytes($tempProfilePath)) -Message "Uninstall did not restore original profile bytes"
  Assert-True -Condition (-not (Test-Path -LiteralPath $sshConfigPath)) -Message "Uninstall should not create SSH config"

  # Unknown edits inside the managed block must fail closed without rewriting.
  & $managerPath install -Yes
  $changedText = [System.IO.File]::ReadAllText($tempProfilePath, $utf8Bom).Replace("Opening SSH tunnel...", "Opening edited tunnel...")
  [System.IO.File]::WriteAllText($tempProfilePath, $changedText, $utf8Bom)
  $changedBytes = [System.IO.File]::ReadAllBytes($tempProfilePath)
  Assert-Throws -Script { & $managerPath uninstall -Yes } -Needle "Modified devtunnel managed block"
  Assert-BytesEqual -Expected $changedBytes -Actual ([System.IO.File]::ReadAllBytes($tempProfilePath)) -Message "Modified managed block was rewritten"

  # Duplicate/conflicting markers must also leave the file byte-identical.
  $duplicateText = $originalText + "`r`n# >>> devtunnel function >>>`r`n# <<< devtunnel function <<<`r`n# >>> devtunnel function >>>`r`n# <<< devtunnel function <<<"
  [System.IO.File]::WriteAllText($tempProfilePath, $duplicateText, $utf8Bom)
  $duplicateBytes = [System.IO.File]::ReadAllBytes($tempProfilePath)
  Assert-Throws -Script { & $managerPath install -Yes } -Needle "Conflicting devtunnel profile markers"
  Assert-BytesEqual -Expected $duplicateBytes -Actual ([System.IO.File]::ReadAllBytes($tempProfilePath)) -Message "Conflicting markers were rewritten"

  # A failure before atomic replacement must preserve the original bytes.
  [System.IO.File]::WriteAllBytes($tempProfilePath, $originalBytes)
  $env:DEVTUNNEL_TEST_FAIL_BEFORE_REPLACE = "1"
  Assert-Throws -Script { & $managerPath install -Yes } -Needle "test-only profile replacement failure"
  Assert-BytesEqual -Expected $originalBytes -Actual ([System.IO.File]::ReadAllBytes($tempProfilePath)) -Message "Failed atomic install changed profile bytes"
  $env:DEVTUNNEL_TEST_FAIL_BEFORE_REPLACE = $null

  Write-Host "devtunnel isolated smoke test passed." -ForegroundColor Green
  Write-Host "Temp root: $tempRoot"
}
finally {
  Remove-Item Function:\devtunnel -ErrorAction SilentlyContinue
  Remove-Item Function:\ssh -ErrorAction SilentlyContinue
  $env:USERPROFILE = $previousUserProfile
  $env:DEVTUNNEL_PROFILE_PATH = $previousProfilePath
  $env:DEVTUNNEL_TEST_FAIL_BEFORE_REPLACE = $previousFailureInjection

  if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
