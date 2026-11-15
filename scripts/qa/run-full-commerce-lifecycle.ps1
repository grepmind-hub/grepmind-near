<#
.SYNOPSIS
  Executes the automated Grepmind Near End-to-End Commerce, Delivery, COD and Settlement Lifecycle Suite.
#>
[CmdletBinding()]
param(
  [switch]$GroceryOnly,
  [switch]$FoodOnly
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  GREPMIND NEAR -- AUTOMATED END-TO-END COMMERCE AND SETTLEMENT SUITE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# Locate active QA runner environment file in WSL
$envFile = wsl -d Ubuntu bash -c "ls -t /home/grepmind/.cache/grepmind/qa-otp-runs/auth-otp-*.env 2>/dev/null | head -n 1"
$envFile = $envFile.Trim()
if (-not $envFile) {
  throw "No active QA OTP runner environment file found in WSL."
}
Write-Host "[INIT] Using active QA environment file: $envFile" -ForegroundColor Yellow

$nodeArgs = ""
if ($GroceryOnly) { $nodeArgs = "--grocery" }
if ($FoodOnly) { $nodeArgs = "--food" }

$cmd = "set -a; source $envFile; set +a; cd /mnt/d/grepmind-near; node scripts/qa/run-full-commerce-lifecycle.mjs $nodeArgs"

wsl -d Ubuntu bash -c $cmd
if ($LASTEXITCODE -ne 0) {
  Write-Error "Commerce lifecycle suite execution failed with exit code $LASTEXITCODE."
} else {
  Write-Host "[SUCCESS] Full end-to-end commerce and settlement lifecycle passed!" -ForegroundColor Green
}
