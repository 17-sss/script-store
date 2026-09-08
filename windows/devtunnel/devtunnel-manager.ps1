param(
  [ValidateSet("install", "remove", "uninstall", "reinstall")]
  [string]$Action = "install",

  [switch]$Yes
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:DEVTUNNEL_PROFILE_PATH)) {
  $profilePath = $PROFILE
}
else {
  $profilePath = $env:DEVTUNNEL_PROFILE_PATH
}

$profilePath = [System.IO.Path]::GetFullPath($profilePath)
$profileStartMarker = "# >>> devtunnel function >>>"
$profileEndMarker = "# <<< devtunnel function <<<"
$profileContractMarker = "# devtunnel-manager:2"

function Get-ProfileDocument {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LiteralPath
  )

  if (-not [System.IO.File]::Exists($LiteralPath)) {
    return [pscustomobject]@{
      Exists = $false
      Bytes = [byte[]]@()
      Text = ""
      Encoding = [System.Text.UTF8Encoding]::new($false, $true)
      Preamble = [byte[]]@()
      NewLine = [Environment]::NewLine
    }
  }

  $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
  $offset = 0
  $preamble = [byte[]]@()
  $encoding = $null

  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $encoding = [System.Text.UTF8Encoding]::new($true, $true)
    $offset = 3
  }
  elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
    $encoding = [System.Text.UTF32Encoding]::new($false, $true, $true)
    $offset = 4
  }
  elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
    $encoding = [System.Text.UTF32Encoding]::new($true, $true, $true)
    $offset = 4
  }
  elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    $encoding = [System.Text.UnicodeEncoding]::new($false, $true, $true)
    $offset = 2
  }
  elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
    $encoding = [System.Text.UnicodeEncoding]::new($true, $true, $true)
    $offset = 2
  }
  else {
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
  }

  if ($offset -gt 0) {
    $preamble = New-Object byte[] $offset
    [Array]::Copy($bytes, 0, $preamble, 0, $offset)
  }

  $payloadLength = $bytes.Length - $offset
  try {
    $text = $encoding.GetString($bytes, $offset, $payloadLength)
  }
  catch [System.Text.DecoderFallbackException] {
    if ($offset -ne 0) { throw }
    $encoding = [System.Text.Encoding]::Default
    $text = $encoding.GetString($bytes)
  }

  $newLineMatch = [regex]::Match($text, "`r`n|`n|`r")
  $newLine = if ($newLineMatch.Success) { $newLineMatch.Value } else { [Environment]::NewLine }

  return [pscustomobject]@{
    Exists = $true
    Bytes = $bytes
    Text = $text
    Encoding = $encoding
    Preamble = $preamble
    NewLine = $newLine
  }
}

function ConvertTo-ProfileBytes {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Document,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $body = $Document.Encoding.GetBytes($Text)
  $result = New-Object byte[] ($Document.Preamble.Length + $body.Length)
  if ($Document.Preamble.Length -gt 0) {
    [Array]::Copy($Document.Preamble, 0, $result, 0, $Document.Preamble.Length)
  }
  if ($body.Length -gt 0) {
    [Array]::Copy($body, 0, $result, $Document.Preamble.Length, $body.Length)
  }
  return $result
}

function Write-ProfileBytesAtomically {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LiteralPath,

    [Parameter(Mandatory = $true)]
    [byte[]]$Bytes
  )

  $directory = [System.IO.Path]::GetDirectoryName($LiteralPath)
  if ([string]::IsNullOrWhiteSpace($directory)) {
    throw "Profile path must have a parent directory: $LiteralPath"
  }
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null

  $temporary = [System.IO.Path]::Combine(
    $directory,
    "." + [System.IO.Path]::GetFileName($LiteralPath) + ".devtunnel." + [guid]::NewGuid().ToString("N") + ".tmp"
  )
  $backup = $temporary + ".backup"
  $replaced = $false

  try {
    [System.IO.File]::WriteAllBytes($temporary, $Bytes)
    if ($env:DEVTUNNEL_TEST_FAIL_BEFORE_REPLACE -eq "1") {
      throw "test-only profile replacement failure"
    }

    if ([System.IO.File]::Exists($LiteralPath)) {
      [System.IO.File]::Replace($temporary, $LiteralPath, $backup, $true)
      $replaced = $true
      if ([System.IO.File]::Exists($backup)) {
        try { [System.IO.File]::Delete($backup) }
        catch { Write-Warning "Atomic profile backup could not be removed: $backup" }
      }
    }
    else {
      [System.IO.File]::Move($temporary, $LiteralPath)
      $replaced = $true
    }
  }
  finally {
    if (-not $replaced -and [System.IO.File]::Exists($temporary)) {
      [System.IO.File]::Delete($temporary)
    }
  }
}

function Get-ManagedBlock {
  param(
    [Parameter(Mandatory = $true)]
    [string]$NewLine,

    [Parameter(Mandatory = $true)]
    [bool]$OwnsPrefixNewLine
  )

  $prefixPolicy = if ($OwnsPrefixNewLine) { "inserted" } else { "existing" }
  $block = @"
$profileStartMarker
$profileContractMarker prefix-newline=$prefixPolicy
function devtunnel {
<#
.SYNOPSIS
Opens SSH local port forwards to a remote development host.

.DESCRIPTION
Opens one or more Windows loopback ports and forwards them to the same ports on
127.0.0.1 behind the SSH config host alias passed at run time. SSH must create
every requested forward successfully or the command fails.

.PARAMETER Ports
Local ports to forward. Each local port maps to the same remote port.

.PARAMETER HostAlias
SSH config host alias to connect through. Values beginning with '-' or
containing whitespace are rejected.

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
    Write-Host "  -HostAlias  SSH config host alias; option-like values are rejected."
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

  if (`$HostAlias.StartsWith("-") -or `$HostAlias -match "\s") {
    throw "SSH host alias must not begin with '-' or contain whitespace."
  }
  if ((`$Ports | Select-Object -Unique).Count -ne `$Ports.Count) {
    throw "Duplicate local ports are not allowed."
  }

  `$sshArgs = @("-o", "ExitOnForwardFailure=yes", "-N")
  foreach (`$port in `$Ports) {
    `$sshArgs += "-L"
    `$sshArgs += ("127.0.0.1:{0}:127.0.0.1:{0}" -f `$port)
  }
  `$sshArgs += `$HostAlias

  Write-Host ""
  Write-Host "Opening SSH tunnel..." -ForegroundColor Cyan
  foreach (`$port in `$Ports) {
    Write-Host ("  http://127.0.0.1:{0} -> {1}:127.0.0.1:{0}" -f `$port, `$HostAlias)
  }
  Write-Host ""
  Write-Host "Press Ctrl + C to close the tunnel." -ForegroundColor Yellow
  Write-Host ""

  ssh @sshArgs
  `$sshExitCode = `$LASTEXITCODE
  if (`$null -eq `$sshExitCode) { `$sshExitCode = 0 }
  if (`$sshExitCode -ne 0) {
    throw "ssh failed with exit code `$sshExitCode. No tunnel is active."
  }
}
$profileEndMarker
"@

  $block = $block.TrimEnd("`r", "`n")
  return [regex]::Replace($block, "`r`n|`n|`r", $NewLine)
}

function Get-ManagedBlockMatch {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $startOccurrences = ([regex]::Matches($Text, [regex]::Escape($profileStartMarker))).Count
  $endOccurrences = ([regex]::Matches($Text, [regex]::Escape($profileEndMarker))).Count
  $lineStart = "(?:\A|(?<=[`r`n]))"
  $lineEnding = "(?:`r`n|`n|`r)"
  $pattern = "(?s)" + $lineStart + [regex]::Escape($profileStartMarker) + $lineEnding + ".*?" + $lineStart + [regex]::Escape($profileEndMarker) + "(?=" + $lineEnding + "|\z)"
  $matches = [regex]::Matches($Text, $pattern)

  if ($startOccurrences -eq 0 -and $endOccurrences -eq 0) { return $null }
  if ($startOccurrences -ne 1 -or $endOccurrences -ne 1 -or $matches.Count -ne 1) {
    throw "Conflicting devtunnel profile markers detected; profile was not changed."
  }

  $match = $matches[0]
  $normalized = [regex]::Replace($match.Value, "`r`n|`r", "`n")
  $metadataPattern = "(?m)^" + [regex]::Escape($profileContractMarker) + " prefix-newline=(inserted|existing)$"
  $metadata = [regex]::Match($normalized, $metadataPattern)
  if (-not $metadata.Success) {
    throw "Unknown or modified devtunnel managed block; profile was not changed."
  }

  $ownsPrefix = $metadata.Groups[1].Value -eq "inserted"
  $expected = Get-ManagedBlock -NewLine "`n" -OwnsPrefixNewLine $ownsPrefix
  if ($normalized -cne $expected) {
    throw "Modified devtunnel managed block; profile was not changed."
  }

  return [pscustomobject]@{
    Match = $match
    OwnsPrefixNewLine = $ownsPrefix
  }
}

function Remove-ProfileBlock {
  $document = Get-ProfileDocument -LiteralPath $profilePath
  if (-not $document.Exists) { return $false }

  $managed = Get-ManagedBlockMatch -Text $document.Text
  if ($null -eq $managed) { return $false }

  $start = $managed.Match.Index
  $end = $start + $managed.Match.Length
  if ($end -lt $document.Text.Length) {
    if ($document.Text.Substring($end).StartsWith("`r`n")) { $end += 2 }
    elseif ($document.Text[$end] -eq "`n" -or $document.Text[$end] -eq "`r") { $end += 1 }
  }

  if ($managed.OwnsPrefixNewLine -and $start -gt 0) {
    if ($start -ge 2 -and $document.Text.Substring($start - 2, 2) -eq "`r`n") { $start -= 2 }
    elseif ($document.Text[$start - 1] -eq "`n" -or $document.Text[$start - 1] -eq "`r") { $start -= 1 }
  }

  $newText = $document.Text.Substring(0, $start) + $document.Text.Substring($end)
  $newBytes = ConvertTo-ProfileBytes -Document $document -Text $newText
  Write-ProfileBytesAtomically -LiteralPath $profilePath -Bytes $newBytes
  return $true
}

function Install-ProfileBlock {
  $document = Get-ProfileDocument -LiteralPath $profilePath
  $managed = Get-ManagedBlockMatch -Text $document.Text
  if ($null -ne $managed) { return $false }

  $ownsPrefixNewLine = $document.Text.Length -gt 0 -and -not (
    $document.Text.EndsWith("`n") -or $document.Text.EndsWith("`r")
  )
  $separator = if ($ownsPrefixNewLine) { $document.NewLine } else { "" }
  $block = Get-ManagedBlock -NewLine $document.NewLine -OwnsPrefixNewLine $ownsPrefixNewLine
  $newText = $document.Text + $separator + $block + $document.NewLine
  $newBytes = ConvertTo-ProfileBytes -Document $document -Text $newText
  Write-ProfileBytesAtomically -LiteralPath $profilePath -Bytes $newBytes
  return $true
}

function Install-All {
  $changed = Install-ProfileBlock
  Write-Host ""
  if ($changed) { Write-Host "devtunnel installed." -ForegroundColor Green }
  else { Write-Host "devtunnel already installed; profile unchanged." -ForegroundColor Green }
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
  $changed = Remove-ProfileBlock
  if ($changed) { Write-Host "devtunnel function removed." -ForegroundColor Green }
  else { Write-Host "devtunnel function not present; profile unchanged." -ForegroundColor Green }
}

switch ($Action) {
  "install" { Install-All }
  "remove" { Remove-All }
  "uninstall" { Remove-All }
  "reinstall" { Install-All }
}
