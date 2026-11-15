<#
.SYNOPSIS
  Executes the Complete Grepmind Near End-to-End UI and Platform Automation Suite.

.DESCRIPTION
  Automates the complete lifecycle:
  1. Authenticates/provisions Customer, Merchant, Rider via isolated QA OTP reader.
  2. Adds a new Product and new Service under Merchant catalog.
  3. Prepares Food and Grocery platform orders.
  4. Executes end-to-end delivery lifecycle for BOTH UPI and COD.
  5. Remits COD liability, deposits to safe, settles merchant payables, and verifies ledger invariants.
  6. Captures physical emulator UI states and generates a Markdown test report with Pass/Fail status.

.PARAMETER CustomerPhone
  Mobile number for Customer role (default: +919990000171).

.PARAMETER MerchantPhone
  Mobile number for Merchant role (default: +919990000172).

.PARAMETER RiderPhone
  Mobile number for Rider role (default: +919990000173).

.PARAMETER ProductName
  Name of the new product to create under Merchant.

.PARAMETER ProductPrice
  Price of the new product in INR (default: 245.0).

.PARAMETER ServiceName
  Name of the new service to create under Merchant.

.PARAMETER ServicePrice
  Indicative base price of the new service in INR (default: 399.0).

.PARAMETER SkipEmulators
  Skip ADB physical emulator screen capture.

.PARAMETER ReportFile
  Custom path for the generated markdown report.
#>
[CmdletBinding()]
param(
  [string]$CustomerPhone = '+919990000171',
  [string]$MerchantPhone = '+919990000172',
  [string]$RiderPhone = '+919990000173',
  [string]$ProductName = 'Artisanal Cardamom Chai Blend',
  [double]$ProductPrice = 245.0,
  [string]$ServiceName = 'Certified Appliance Safety Audit',
  [double]$ServicePrice = 399.0,
  [switch]$SkipEmulators,
  [string]$ReportFile
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  GREPMIND NEAR -- COMPLETE END-TO-END UI AND PLATFORM AUTOMATION SUITE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# Locate active QA runner environment file in WSL
$envFile = wsl -d Ubuntu bash -c "ls -t /home/grepmind/.cache/grepmind/qa-otp-runs/auth-otp-*.env 2>/dev/null | head -n 1"
$envFile = $envFile.Trim()
if (-not $envFile) {
  throw "No active QA OTP runner environment file found in WSL."
}
Write-Host "[INIT] Using active QA environment file: $envFile" -ForegroundColor Yellow

$nodeArgs = @(
  "--customer-phone", $CustomerPhone,
  "--merchant-phone", $MerchantPhone,
  "--rider-phone", $RiderPhone,
  "--product-name", "`"$ProductName`"",
  "--product-price", $ProductPrice,
  "--service-name", "`"$ServiceName`"",
  "--service-price", $ServicePrice
)

if ($SkipEmulators) {
  $nodeArgs += "--skip-emulators"
}

if ($ReportFile) {
  $nodeArgs += @("--report-file", "`"$ReportFile`"")
}

$argString = $nodeArgs -join ' '
$cmd = "set -a; source $envFile; set +a; cd /mnt/d/grepmind-near; node scripts/qa/run-complete-e2e-suite.mjs $argString"

Write-Host "[EXEC] Running test scenarios..." -ForegroundColor Cyan
wsl -d Ubuntu bash -c $cmd

if ($LASTEXITCODE -ne 0) {
  Write-Error "E2E Suite failed with exit code $LASTEXITCODE."
} else {
  Write-Host ""
  Write-Host "========================================================================" -ForegroundColor Green
  Write-Host "  [SUCCESS] All end-to-end scenarios and financial invariants passed!" -ForegroundColor Green
  Write-Host "========================================================================" -ForegroundColor Green
}
