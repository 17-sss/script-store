param (
  [ValidateRange(1, 65535)]
  [int]$Port = 5173
)

$ruleNames = @(
  "WSL PortProxy $Port",
  "Vite $Port"
)

Write-Output "=== WSL portproxy uninstall ==="
Write-Output "[INFO] Target port = $Port"

Write-Output "[STEP] Remove portproxy rule"
$proxyResult = netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>&1
if ($LASTEXITCODE -eq 0) {
  Write-Output "[INFO] Portproxy rule removed if it existed"
}
else {
  Write-Output "[WARN] Could not remove portproxy rule"
  Write-Output "[WARN] Run PowerShell as Administrator if this was unexpected"
  $proxyResult | ForEach-Object { Write-Output "       $_" }
}

Write-Output "[STEP] Remove firewall rules"
foreach ($ruleName in $ruleNames) {
  $rules = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

  if ($rules) {
    $rules | Remove-NetFirewallRule
    Write-Output "[INFO] Firewall rule removed: $ruleName"
  }
  else {
    Write-Output "[INFO] No firewall rule found: $ruleName"
  }
}

Write-Output "=== Done ==="
Write-Output "[INFO] WSL portproxy cleanup complete for port $Port"
