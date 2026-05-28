param(
  [ValidateSet("install", "remove", "reinstall")]
  [string]$Action = "install"
)

$profilePath = $PROFILE
$profileDir = Split-Path $profilePath -Parent

$sshDir = Join-Path $env:USERPROFILE ".ssh"
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

    Write-Host "값을 입력해야 합니다." -ForegroundColor Yellow
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
    Write-Host "포트 형식이 올바르지 않아 기본값 3000을 사용합니다." -ForegroundColor Yellow
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
    Write-Host "SSH 포트가 올바르지 않아 기본값 $DefaultValue를 사용합니다." -ForegroundColor Yellow
    return $DefaultValue
  }
}

function Remove-ProfileBlock {
  if (-not (Test-Path $profilePath)) {
    return
  }

  $content = Get-Content $profilePath -Raw
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
  param(
    [int[]]`$Ports = @($portsLiteral),
    [string]`$HostAlias = "$DefaultHostAlias"
  )

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

  $content = Get-Content $profilePath -Raw

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

  $content = Get-Content $sshConfigPath -Raw

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

  $content = Get-Content $sshConfigPath -Raw

  if (-not [string]::IsNullOrWhiteSpace($content) -and -not $content.EndsWith("`n")) {
    Add-Content -Path $sshConfigPath -Value ""
  }

  Add-Content -Path $sshConfigPath -Value $sshBlock -Encoding UTF8
}

function Remove-AnyDevTunnelSshBlocks {
  if (-not (Test-Path $sshConfigPath)) {
    return
  }

  $content = Get-Content $sshConfigPath -Raw

  $pattern = "(?m)^" + [regex]::Escape($sshStartMarkerPrefix) + " .+ >>>\r?\n[\s\S]*?^" + [regex]::Escape($sshEndMarkerPrefix) + " .+ <<<(\r?\n)?"
  $newContent = [regex]::Replace($content, $pattern, "")

  Set-Content -Path $sshConfigPath -Value $newContent -Encoding UTF8
}

function Install-All {
  param(
    [switch]$ReplaceManagedSshBlocks
  )

  Write-Host ""
  Write-Host "devtunnel 설치 설정" -ForegroundColor Cyan
  Write-Host ""

  $hostAlias = Read-WithDefault "SSH Host alias" "remote-ubuntu-dev"
  $hostName = Read-Required "SSH HostName / IP"
  $sshUser = Read-WithDefault "SSH User" $env:USERNAME

  $sshPort = Read-SshPort -DefaultValue 22

  $defaultIdentity = Join-Path $env:USERPROFILE ".ssh\id_ed25519"
  $identityFile = Read-OptionalIdentityFile -DefaultValue $defaultIdentity

  $ports = Read-Ports -DefaultValue "3000"

  Write-Host ""
  Write-Host "설정 요약" -ForegroundColor Cyan
  Write-Host "  SSH alias    : $hostAlias"
  Write-Host "  HostName/IP  : $hostName"
  Write-Host "  User         : $sshUser"
  Write-Host "  Port         : $sshPort"
  Write-Host "  IdentityFile : $identityFile"
  Write-Host "  Dev ports    : $($ports -join ', ')"
  Write-Host ""

  $confirm = Read-WithDefault "Install with this config? y/n" "y"

  if ($confirm -notin @("y", "Y", "yes", "YES")) {
    Write-Host "취소했습니다." -ForegroundColor Yellow
    return
  }

  if ($ReplaceManagedSshBlocks) {
    Remove-AnyDevTunnelSshBlocks
  }

  Install-SshHostBlock `
    -HostAlias $hostAlias `
    -HostName $hostName `
    -User $sshUser `
    -Port $sshPort `
    -IdentityFile $identityFile

  Install-ProfileBlock `
    -DefaultHostAlias $hostAlias `
    -DefaultPorts $ports

  Write-Host ""
  Write-Host "devtunnel installed." -ForegroundColor Green
  Write-Host ""
  Write-Host "SSH config:"
  Write-Host "  $sshConfigPath"
  Write-Host ""
  Write-Host "PowerShell profile:"
  Write-Host "  $profilePath"
  Write-Host ""
  Write-Host "PowerShell을 재시작하거나 아래 명령을 실행하세요:"
  Write-Host "  . `$PROFILE"
  Write-Host ""
  Write-Host "테스트:"
  Write-Host "  ssh $hostAlias"
  Write-Host "  devtunnel"
  Write-Host "  devtunnel -Ports 3000,5173,6006"
}

switch ($Action) {
  "install" {
    Install-All
  }

  "remove" {
    Remove-ProfileBlock

    $removeSsh = Read-WithDefault "Also remove devtunnel-managed SSH config blocks? y/n" "n"

    if ($removeSsh -in @("y", "Y", "yes", "YES")) {
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
