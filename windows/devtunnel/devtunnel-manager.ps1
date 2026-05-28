param(
  [ValidateSet("install", "remove", "reinstall")]
  [string]$Action = "install",

  [string]$HostAlias = "",

  [string]$HostName = "",

  [string]$SshUser = "",

  [int]$SshPort = 0,

  [ValidateSet("prompt", "new", "existing")]
  [string]$SshHostMode = "prompt",

  [AllowEmptyString()]
  [string]$IdentityFile = $null,

  [ValidateRange(1, 65535)]
  [int[]]$DefaultPorts = @(),

  [switch]$SkipIdentityFile,

  [switch]$Yes,

  [switch]$RemoveSshBlocks
)

if ([string]::IsNullOrWhiteSpace($env:DEVTUNNEL_PROFILE_PATH)) {
  $profilePath = $PROFILE
}
else {
  $profilePath = $env:DEVTUNNEL_PROFILE_PATH
}

if ([string]::IsNullOrWhiteSpace($env:DEVTUNNEL_SSH_DIR)) {
  $sshDir = Join-Path $env:USERPROFILE ".ssh"
}
else {
  $sshDir = $env:DEVTUNNEL_SSH_DIR
}

$sshConfigPath = Join-Path $sshDir "config"

$profileStartMarker = "# >>> devtunnel function >>>"
$profileEndMarker = "# <<< devtunnel function <<<"

$sshStartMarkerPrefix = "# >>> devtunnel ssh host:"
$sshEndMarkerPrefix = "# <<< devtunnel ssh host:"

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

function Read-WithDefault {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [string]$DefaultValue = ""
  )

  if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
    return Read-Host $Message
  }

  $inputValue = Read-Host "$Message [$DefaultValue]"

  if ([string]::IsNullOrWhiteSpace($inputValue)) {
    return $DefaultValue
  }

  return $inputValue
}

function Read-Required {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  while ($true) {
    $value = Read-Host $Message

    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $value
    }

    Write-Host "A value is required." -ForegroundColor Yellow
  }
}

function Read-Ports {
  param(
    [string]$DefaultValue = "3000"
  )

  $portsInput = Read-WithDefault "Default ports, comma separated" $DefaultValue

  try {
    $ports = $portsInput -split "," |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -ne "" } |
      ForEach-Object { [int]$_ }

    if ($ports.Count -eq 0) {
      throw "No ports"
    }

    foreach ($port in $ports) {
      if ($port -lt 1 -or $port -gt 65535) {
        throw "Invalid port: $port"
      }
    }

    return $ports
  }
  catch {
    Write-Host "Invalid port list. Using default port 3000." -ForegroundColor Yellow
    return @(3000)
  }
}

function Read-OptionalIdentityFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DefaultValue
  )

  $inputValue = Read-Host "IdentityFile [$DefaultValue] (type none to skip)"

  if ([string]::IsNullOrWhiteSpace($inputValue)) {
    return $DefaultValue
  }

  if ($inputValue -in @("none", "NONE", "None", "-")) {
    return ""
  }

  return $inputValue
}

function Read-SshPort {
  param(
    [int]$DefaultValue = 22
  )

  $portInput = Read-WithDefault "SSH Port" "$DefaultValue"

  try {
    $port = [int]$portInput

    if ($port -lt 1 -or $port -gt 65535) {
      throw "Invalid port: $port"
    }

    return $port
  }
  catch {
    Write-Host "Invalid SSH port. Using default port $DefaultValue." -ForegroundColor Yellow
    return $DefaultValue
  }
}

function Get-SshHostAliases {
  if (-not (Test-Path $sshConfigPath)) {
    return @()
  }

  $aliases = @()
  $lines = Get-Content -Path $sshConfigPath

  foreach ($line in $lines) {
    $trimmed = $line.Trim()

    if ($trimmed -match "(?i)^Host\s+(.+)$") {
      $tokens = $Matches[1] -split "\s+"

      foreach ($token in $tokens) {
        if ($token.StartsWith("#")) {
          break
        }

        if ([string]::IsNullOrWhiteSpace($token)) {
          continue
        }

        if ($token -match "[*?!]") {
          continue
        }

        if ($aliases -notcontains $token) {
          $aliases += $token
        }
      }
    }
  }

  return $aliases
}

function Read-SshHostMode {
  param(
    [string[]]$ExistingAliases = @()
  )

  if ($SshHostMode -ne "prompt") {
    return $SshHostMode
  }

  if (-not [string]::IsNullOrWhiteSpace($HostName)) {
    return "new"
  }

  Write-Host "SSH host setup" -ForegroundColor Cyan
  Write-Host "  [1] Add a new devtunnel-managed SSH host"
  Write-Host "  [2] Use an existing SSH host from config"
  Write-Host ""

  if ($ExistingAliases.Count -gt 0) {
    $defaultMode = "2"
  }
  else {
    Write-Host "No existing SSH Host entries were found in $sshConfigPath." -ForegroundColor Yellow
    $defaultMode = "1"
  }

  while ($true) {
    $choice = Read-WithDefault "Choose SSH setup mode: 1 new, 2 existing" $defaultMode

    if ($choice -in @("1", "n", "N", "new", "NEW")) {
      return "new"
    }

    if ($choice -in @("2", "e", "E", "existing", "EXISTING")) {
      return "existing"
    }

    Write-Host "Please choose 1 or 2." -ForegroundColor Yellow
  }
}

function Read-ExistingHostAlias {
  param(
    [string[]]$ExistingAliases = @()
  )

  if (-not [string]::IsNullOrWhiteSpace($HostAlias)) {
    return $HostAlias
  }

  if ($ExistingAliases.Count -eq 0) {
    return Read-Required "Existing SSH Host alias"
  }

  Write-Host "Existing SSH hosts" -ForegroundColor Cyan

  for ($index = 0; $index -lt $ExistingAliases.Count; $index++) {
    $displayNumber = $index + 1
    Write-Host "  [$displayNumber] $($ExistingAliases[$index])"
  }

  Write-Host ""

  while ($true) {
    $choice = Read-WithDefault "Select SSH Host alias by number or name" $ExistingAliases[0]
    $choiceNumber = 0

    if ([int]::TryParse($choice, [ref]$choiceNumber)) {
      if ($choiceNumber -ge 1 -and $choiceNumber -le $ExistingAliases.Count) {
        return $ExistingAliases[$choiceNumber - 1]
      }
    }

    if ($ExistingAliases -contains $choice) {
      return $choice
    }

    Write-Host "Please choose a listed number or alias." -ForegroundColor Yellow
  }
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
  param(
    [Parameter(Mandatory = $true)]
    [string]$DefaultHostAlias,

    [Parameter(Mandatory = $true)]
    [int[]]$DefaultPorts
  )

  Ensure-File $profilePath
  Remove-ProfileBlock

  $portsLiteral = ($DefaultPorts -join ",")

  $functionBlock = @"
$profileStartMarker
function devtunnel {
<#
.SYNOPSIS
Opens SSH local port forwards to a remote development host.

.DESCRIPTION
Opens one or more Windows localhost ports and forwards them to the same ports on
127.0.0.1 behind the configured SSH host alias.

.PARAMETER Ports
Local ports to forward. Each local port maps to the same remote port.

.PARAMETER HostAlias
SSH config host alias to connect through.

.PARAMETER Help
Shows usage examples and exits.

.EXAMPLE
devtunnel

.EXAMPLE
devtunnel -Ports 3000,5173,6006

.EXAMPLE
devtunnel -Ports 3000 -HostAlias $DefaultHostAlias
#>
  [CmdletBinding()]
  param(
    [ValidateRange(1, 65535)]
    [int[]]`$Ports = @($portsLiteral),

    [string]`$HostAlias = "$DefaultHostAlias",

    [Alias("h")]
    [switch]`$Help
  )

  if (`$Help) {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  devtunnel"
    Write-Host "  devtunnel -Ports 3000"
    Write-Host "  devtunnel -Ports 3000,5173,6006"
    Write-Host "  devtunnel -Ports 3000 -HostAlias $DefaultHostAlias"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  -Ports      Local ports to forward to the same remote ports."
    Write-Host "  -HostAlias  SSH config host alias. Default: $DefaultHostAlias"
    Write-Host "  -Help       Show this help. Also accepts -h."
    Write-Host ""
    Write-Host "More:"
    Write-Host "  Get-Help devtunnel -Detailed"
    return
  }

  `$sshArgs = @("-N")

  foreach (`$port in `$Ports) {
    `$sshArgs += "-L"
    `$sshArgs += "`$port`:127.0.0.1:`$port"
  }

  `$sshArgs += `$HostAlias

  Write-Host ""
  Write-Host "Opening SSH tunnel..." -ForegroundColor Cyan

  foreach (`$port in `$Ports) {
    Write-Host "  http://localhost:`$port -> `$HostAlias`:127.0.0.1:`$port"
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

function Remove-SshHostBlock {
  param(
    [Parameter(Mandatory = $true)]
    [string]$HostAlias
  )

  if (-not (Test-Path $sshConfigPath)) {
    return
  }

  $content = Get-FileText $sshConfigPath

  $startMarker = "$sshStartMarkerPrefix $HostAlias >>>"
  $endMarker = "$sshEndMarkerPrefix $HostAlias <<<"

  $pattern = [regex]::Escape($startMarker) + "[\s\S]*?" + [regex]::Escape($endMarker) + "(\r?\n)?"
  $newContent = [regex]::Replace($content, $pattern, "")

  Set-Content -Path $sshConfigPath -Value $newContent -Encoding UTF8
}

function Install-SshHostBlock {
  param(
    [Parameter(Mandatory = $true)]
    [string]$HostAlias,

    [Parameter(Mandatory = $true)]
    [string]$HostName,

    [Parameter(Mandatory = $true)]
    [string]$User,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [string]$IdentityFile = ""
  )

  Ensure-File $sshConfigPath
  Remove-SshHostBlock -HostAlias $HostAlias

  $startMarker = "$sshStartMarkerPrefix $HostAlias >>>"
  $endMarker = "$sshEndMarkerPrefix $HostAlias <<<"

  $identityLine = ""

  if (-not [string]::IsNullOrWhiteSpace($IdentityFile)) {
    $identityLine = "  IdentityFile $IdentityFile"
  }

  $sshBlock = @"
$startMarker
Host $HostAlias
  HostName $HostName
  User $User
  Port $Port
$identityLine
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ExitOnForwardFailure yes
$endMarker
"@

  $content = Get-FileText $sshConfigPath

  if (-not [string]::IsNullOrWhiteSpace($content) -and -not $content.EndsWith("`n")) {
    Add-Content -Path $sshConfigPath -Value ""
  }

  Add-Content -Path $sshConfigPath -Value $sshBlock -Encoding UTF8
}

function Remove-AnyDevTunnelSshBlocks {
  if (-not (Test-Path $sshConfigPath)) {
    return
  }

  $content = Get-FileText $sshConfigPath

  $pattern = "(?m)^" + [regex]::Escape($sshStartMarkerPrefix) + " .+ >>>\r?\n[\s\S]*?^" + [regex]::Escape($sshEndMarkerPrefix) + " .+ <<<(\r?\n)?"
  $newContent = [regex]::Replace($content, $pattern, "")

  Set-Content -Path $sshConfigPath -Value $newContent -Encoding UTF8
}

function Install-All {
  param(
    [switch]$ReplaceManagedSshBlocks
  )

  Write-Host ""
  Write-Host "devtunnel setup" -ForegroundColor Cyan
  Write-Host ""

  $existingAliases = @(Get-SshHostAliases)
  $resolvedSshHostMode = Read-SshHostMode -ExistingAliases $existingAliases

  if ($resolvedSshHostMode -eq "existing") {
    $resolvedHostAlias = Read-ExistingHostAlias -ExistingAliases $existingAliases
  }
  else {
    if ([string]::IsNullOrWhiteSpace($HostAlias)) {
      $resolvedHostAlias = Read-WithDefault "SSH Host alias" "remote-ubuntu-dev"
    }
    else {
      $resolvedHostAlias = $HostAlias
    }

    if ([string]::IsNullOrWhiteSpace($HostName)) {
      $resolvedHostName = Read-Required "SSH HostName / IP"
    }
    else {
      $resolvedHostName = $HostName
    }

    if ([string]::IsNullOrWhiteSpace($SshUser)) {
      $resolvedSshUser = Read-WithDefault "SSH User" $env:USERNAME
    }
    else {
      $resolvedSshUser = $SshUser
    }

    if ($SshPort -gt 0 -and $SshPort -le 65535) {
      $resolvedSshPort = $SshPort
    }
    elseif ($SshPort -ne 0) {
      Write-Host "Invalid SSH port. Using default port 22." -ForegroundColor Yellow
      $resolvedSshPort = 22
    }
    else {
      $resolvedSshPort = Read-SshPort -DefaultValue 22
    }

    $defaultIdentity = Join-Path $env:USERPROFILE ".ssh\id_ed25519"

    if ($SkipIdentityFile) {
      $resolvedIdentityFile = ""
    }
    elseif ($null -ne $IdentityFile) {
      $resolvedIdentityFile = $IdentityFile
    }
    else {
      $resolvedIdentityFile = Read-OptionalIdentityFile -DefaultValue $defaultIdentity
    }
  }

  if ($DefaultPorts.Count -gt 0) {
    $resolvedPorts = $DefaultPorts
  }
  else {
    $resolvedPorts = Read-Ports -DefaultValue "3000"
  }

  Write-Host ""
  Write-Host "Configuration summary" -ForegroundColor Cyan
  Write-Host "  SSH mode     : $resolvedSshHostMode"
  Write-Host "  SSH alias    : $resolvedHostAlias"

  if ($resolvedSshHostMode -eq "existing") {
    Write-Host "  SSH config   : unchanged"
  }
  else {
    Write-Host "  HostName/IP  : $resolvedHostName"
    Write-Host "  User         : $resolvedSshUser"
    Write-Host "  Port         : $resolvedSshPort"
    Write-Host "  IdentityFile : $resolvedIdentityFile"
  }

  Write-Host "  Dev ports    : $($resolvedPorts -join ', ')"
  Write-Host ""

  if (-not $Yes) {
    $confirm = Read-WithDefault "Install with this config? y/n" "y"

    if ($confirm -notin @("y", "Y", "yes", "YES")) {
      Write-Host "Canceled." -ForegroundColor Yellow
      return
    }
  }

  if ($ReplaceManagedSshBlocks) {
    Remove-AnyDevTunnelSshBlocks
  }

  if ($resolvedSshHostMode -ne "existing") {
    Install-SshHostBlock `
      -HostAlias $resolvedHostAlias `
      -HostName $resolvedHostName `
      -User $resolvedSshUser `
      -Port $resolvedSshPort `
      -IdentityFile $resolvedIdentityFile
  }

  Install-ProfileBlock `
    -DefaultHostAlias $resolvedHostAlias `
    -DefaultPorts $resolvedPorts

  Write-Host ""
  Write-Host "devtunnel installed." -ForegroundColor Green
  Write-Host ""

  if ($resolvedSshHostMode -eq "existing") {
    Write-Host "SSH config unchanged:"
    Write-Host "  $sshConfigPath"
    Write-Host ""
  }
  else {
    Write-Host "SSH config:"
    Write-Host "  $sshConfigPath"
    Write-Host ""
  }

  Write-Host "PowerShell profile:"
  Write-Host "  $profilePath"
  Write-Host ""
  Write-Host "Restart PowerShell or run:"
  Write-Host "  . `$PROFILE"
  Write-Host ""
  Write-Host "Test commands:"
  Write-Host "  ssh $resolvedHostAlias"
  Write-Host "  devtunnel"
  Write-Host "  devtunnel -Ports 3000,5173,6006"
}

switch ($Action) {
  "install" {
    Install-All
  }

  "remove" {
    Remove-ProfileBlock

    $shouldRemoveSsh = $RemoveSshBlocks

    if (-not $shouldRemoveSsh -and -not $Yes) {
      $removeSsh = Read-WithDefault "Also remove devtunnel-managed SSH config blocks? y/n" "n"
      $shouldRemoveSsh = $removeSsh -in @("y", "Y", "yes", "YES")
    }

    if ($shouldRemoveSsh) {
      Remove-AnyDevTunnelSshBlocks
      Write-Host "devtunnel function and managed SSH blocks removed." -ForegroundColor Green
    }
    else {
      Write-Host "devtunnel function removed. SSH config kept." -ForegroundColor Green
    }
  }

  "reinstall" {
    Install-All -ReplaceManagedSshBlocks
  }
}
