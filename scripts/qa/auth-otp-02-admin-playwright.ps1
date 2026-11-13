[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [switch]$Headed,

  [Parameter(Mandatory = $false)]
  [switch]$ManualEntry,

  [Parameter(Mandatory = $false)]
  [switch]$KeepBrowserOpen,

  [Parameter(Mandatory = $false)]
  [ValidateSet('+919990000174', '+919990000175', '+919990000176', '+919990000177')]
  [string]$AdminPhone = '+919990000174',

  [Parameter(Mandatory = $false)]
  [ValidatePattern('^http://(localhost|127\.0\.0\.1):[0-9]{2,5}$')]
  [string]$BaseUrl = 'http://localhost:3302',

  [Parameter(Mandatory = $false)]
  [ValidateSet('auth-otp-02.admin.spec.ts', 'phase4d-finance-access.qa.spec.ts')]
  [string]$TestFile = 'auth-otp-02.admin.spec.ts',

  [Parameter(Mandatory = $false)]
  [ValidateSet('request', 'approve', 'simulate', 'reconcile')]
  [string]$FinanceGrantAction,

  [Parameter(Mandatory = $false)]
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
  [string]$FinanceGrantTargetId,

  [Parameter(Mandatory = $false)]
  [ValidatePattern('^(df524271-3a13-4214-bbbf-24f568cb56be|5fc75df3-7192-43e8-842b-f2b3b126d170)(,(df524271-3a13-4214-bbbf-24f568cb56be|5fc75df3-7192-43e8-842b-f2b3b126d170))*$')]
  [string]$SettlementBatchIds,

  [Parameter(Mandatory = $false)]
  [string]$RunnerEnvFile
)

$ErrorActionPreference = 'Stop'
if ($ManualEntry -and -not $Headed) {
  throw 'ManualEntry requires -Headed so the OTP can be entered in the visible Admin UI.'
}
if ($KeepBrowserOpen -and -not $Headed) {
  throw 'KeepBrowserOpen requires -Headed so the authenticated Admin page remains visible.'
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$adminWeb = Join-Path $repoRoot 'apps\admin-web'

function Invoke-WslBashScript {
  param([Parameter(Mandatory = $true)][string]$ScriptText)

  # Windows PowerShell 5.1 otherwise splits a multiline -lc argument at shell
  # quotes before wsl.exe receives it. Base64 keeps the payload a single safe
  # argument; the script content is decoded and executed only inside WSL.
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ScriptText))
  $command = "printf '%s' '$encoded' | base64 --decode | bash"
  $output = @(& wsl.exe --exec bash -lc $command)
  $exitCode = $LASTEXITCODE
  return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
}

# Resolve the private runner file against the currently running API and inbox.
# The QA setup generates a fresh random run ID, so a fixed default path becomes
# stale after every reader rotation. Only the matching file path is returned;
# run IDs, runner IDs, and secrets stay inside WSL and PowerShell memory.
if ([string]::IsNullOrWhiteSpace($RunnerEnvFile)) {
  $discoverRunner = @'
set -euo pipefail
api=grepmind_4c_qa_api
inbox=grepmind_4c_qa_otp_inbox
runner_dir=/home/grepmind/.cache/grepmind/qa-otp-runs
getenv() { printf "%s\n" "$1" | awk -F= -v key="$2" '$1==key {sub(/^[^=]*=/, ""); print; exit}'; }
api_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$api")
inbox_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$inbox")
api_run=$(getenv "$api_env" QA_OTP_RUN_ID)
inbox_run=$(getenv "$inbox_env" QA_OTP_RUN_ID)
api_allowlist=$(getenv "$api_env" QA_OTP_ALLOWLIST)
reader_runner=$(getenv "$inbox_env" QA_OTP_RUNNER_ID)
reader_secret=$(getenv "$inbox_env" QA_OTP_RUNNER_SECRET)
[[ "$(docker inspect --format '{{.State.Status}}' "$api")" == running ]]
[[ "$(docker inspect --format '{{.State.Status}}' "$inbox")" == running ]]
[[ "$(getenv "$api_env" APP_ENV)" == qa && "$(getenv "$api_env" OTP_PROVIDER)" == qa_http ]]
[[ "$(getenv "$api_env" QA_OTP_DELIVERY_ENABLED)" == true ]]
[[ "$(getenv "$inbox_env" APP_ENV)" == qa && "$(getenv "$inbox_env" QA_OTP_READER_ENABLED)" == true ]]
[[ -n "$api_run" && "$api_run" == "$inbox_run" ]]
[[ ",${api_allowlist}," == *",+919990000174,"* ]]
[[ "$(curl --max-time 3 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:18085/healthz)" == 204 ]]
matches=()
for candidate in "$runner_dir"/*.env; do
  [[ -f "$candidate" ]] || continue
  [[ "$(stat -c '%a' "$candidate")" == 600 && "$(stat -c '%u' "$candidate")" == "$(id -u)" ]] || continue
  set -a
  . "$candidate"
  set +a
  if [[ "${QA_OTP_RUN_ID:-}" == "$api_run" && "${QA_OTP_RUNNER_ID:-}" == "$reader_runner" && "${QA_OTP_RUNNER_SECRET:-}" == "$reader_secret" && "${QA_OTP_READER_URL:-}" == http://127.0.0.1:18085 ]]; then
    matches+=("$candidate")
  fi
  unset QA_OTP_READER_URL QA_OTP_RUN_ID QA_OTP_RUNNER_ID QA_OTP_RUNNER_SECRET QA_API_BASE
done
[[ "${#matches[@]}" == 1 ]]
printf 'RUNNER_ENV_FILE=%s\n' "${matches[0]}"
'@
  $discovery = Invoke-WslBashScript -ScriptText $discoverRunner
  $runnerPathOutput = $discovery.Output
  if ($discovery.ExitCode -ne 0) {
    throw 'No private runner file matches the isolated QA API and OTP inbox. No OTP was requested.'
  }
  $runnerPathLine = @($runnerPathOutput | Where-Object { $_ -like 'RUNNER_ENV_FILE=*' })
  if ($runnerPathLine.Count -ne 1) {
    throw 'The isolated QA runner did not return one matching private runner file. No OTP was requested.'
  }
  $RunnerEnvFile = $runnerPathLine[0].Substring('RUNNER_ENV_FILE='.Length)
}
if ($RunnerEnvFile -notmatch '^/home/grepmind/\.cache/grepmind/qa-otp-runs/[A-Za-z0-9._-]+\.env$') {
  throw 'RunnerEnvFile must be inside the protected isolated QA runner directory.'
}
$bash = @'
set -euo pipefail
set -a
. '__RUNNER_ENV_FILE__'
set +a
printf 'QA_OTP_READER_URL=%s\nQA_OTP_RUN_ID=%s\nQA_OTP_RUNNER_ID=%s\nQA_OTP_RUNNER_SECRET=%s\n' \
  "$QA_OTP_READER_URL" "$QA_OTP_RUN_ID" "$QA_OTP_RUNNER_ID" "$QA_OTP_RUNNER_SECRET"
'@.Replace('__RUNNER_ENV_FILE__', $RunnerEnvFile)

$runnerConfig = Invoke-WslBashScript -ScriptText $bash
$lines = $runnerConfig.Output
if ($runnerConfig.ExitCode -ne 0) { throw 'Unable to load the protected QA runner configuration from WSL.' }

$qa = @{}
foreach ($line in $lines) {
  $separator = $line.IndexOf('=')
  if ($separator -gt 0) { $qa[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
}
foreach ($key in @('QA_OTP_READER_URL', 'QA_OTP_RUN_ID', 'QA_OTP_RUNNER_ID', 'QA_OTP_RUNNER_SECRET')) {
  if (-not $qa.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($qa[$key])) {
    $qa.Clear()
    throw 'The protected QA runner configuration is incomplete.'
  }
}

$reader = $null
if (-not [Uri]::TryCreate($qa.QA_OTP_READER_URL, [UriKind]::Absolute, [ref]$reader) -or
    $reader.Scheme -ne 'http' -or $reader.Host -notin @('127.0.0.1', 'localhost') -or
    $reader.UserInfo -or $reader.Query -or $reader.Fragment) {
  $qa.Clear()
  throw 'The QA OTP reader must use an authenticated loopback-only HTTP origin.'
}

$names = @('PLAYWRIGHT_BASE_URL', 'E2E_ADMIN_PHONE_E164', 'QA_OTP_READER_URL', 'QA_OTP_RUN_ID', 'QA_OTP_RUNNER_ID', 'QA_OTP_RUNNER_SECRET', 'QA_OTP_MANUAL_ENTRY', 'QA_ADMIN_KEEP_BROWSER_OPEN', 'E2E_FINANCE_GRANT_ACTION', 'E2E_FINANCE_GRANT_TARGET_ID', 'E2E_SETTLEMENT_BATCH_IDS')
$isGrantTest = $TestFile -eq 'phase4d-finance-access.qa.spec.ts'
if ($isGrantTest -and -not $FinanceGrantAction) {
  throw 'The finance access UI test requires FinanceGrantAction.'
}
if ($isGrantTest -and $FinanceGrantAction -in @('request', 'approve') -and (-not $FinanceGrantTargetId -or $SettlementBatchIds)) {
  throw 'Request/approval requires only FinanceGrantTargetId.'
}
if ($isGrantTest -and $FinanceGrantAction -in @('simulate', 'reconcile') -and (-not $SettlementBatchIds -or $FinanceGrantTargetId)) {
  throw 'Simulation/reconciliation requires only the explicitly approved SettlementBatchIds.'
}
if (-not $isGrantTest -and ($FinanceGrantAction -or $FinanceGrantTargetId -or $SettlementBatchIds)) {
  throw 'Finance grant parameters are only valid with phase4d-finance-access.qa.spec.ts.'
}
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
  $env:PLAYWRIGHT_BASE_URL = $BaseUrl
  $env:E2E_ADMIN_PHONE_E164 = $AdminPhone
  if ($isGrantTest) {
    $env:E2E_FINANCE_GRANT_ACTION = $FinanceGrantAction
    if ($FinanceGrantTargetId) { $env:E2E_FINANCE_GRANT_TARGET_ID = $FinanceGrantTargetId }
    else { Remove-Item Env:E2E_FINANCE_GRANT_TARGET_ID -ErrorAction SilentlyContinue }
    if ($SettlementBatchIds) { $env:E2E_SETTLEMENT_BATCH_IDS = $SettlementBatchIds }
    else { Remove-Item Env:E2E_SETTLEMENT_BATCH_IDS -ErrorAction SilentlyContinue }
  } else {
    Remove-Item Env:E2E_FINANCE_GRANT_ACTION -ErrorAction SilentlyContinue
    Remove-Item Env:E2E_FINANCE_GRANT_TARGET_ID -ErrorAction SilentlyContinue
    Remove-Item Env:E2E_SETTLEMENT_BATCH_IDS -ErrorAction SilentlyContinue
  }
  if ($ManualEntry) { $env:QA_OTP_MANUAL_ENTRY = '1' }
  else { Remove-Item Env:QA_OTP_MANUAL_ENTRY -ErrorAction SilentlyContinue }
  if ($KeepBrowserOpen) { $env:QA_ADMIN_KEEP_BROWSER_OPEN = '1' }
  else { Remove-Item Env:QA_ADMIN_KEEP_BROWSER_OPEN -ErrorAction SilentlyContinue }
  foreach ($key in @('QA_OTP_READER_URL', 'QA_OTP_RUN_ID', 'QA_OTP_RUNNER_ID', 'QA_OTP_RUNNER_SECRET')) {
    Set-Item -Path "Env:$key" -Value $qa[$key]
  }

  Push-Location $adminWeb
  try {
    $playwrightArgs = @('exec', '--', 'playwright', 'test', '-c', 'playwright.codex.local.config.ts', "e2e/$TestFile")
    if ($Headed) {
      # Launch the configured Windows Chrome visibly so the operator can watch
      # the normal OTP login flow; the OTP still stays in runner memory.
      $playwrightArgs += '--headed'
      Write-Output 'Admin QA browser mode: visible Chrome.'
    } else {
      Write-Output 'Admin QA browser mode: headless Chrome.'
    }
    if ($KeepBrowserOpen) { Write-Output 'Admin session will remain open until you close the Chrome window.' }
    if ($ManualEntry) { Write-Warning 'Manual OTP mode is enabled: a short-lived QA OTP will be displayed in this PowerShell session.' }
    npm.cmd @playwrightArgs
    if ($LASTEXITCODE -ne 0) { throw "Admin Playwright failed with exit code $LASTEXITCODE." }
  } finally {
    Pop-Location
  }
} finally {
  foreach ($name in $names) {
    if ($null -eq $previous[$name]) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
    else { Set-Item -Path "Env:$name" -Value $previous[$name] }
  }
  $qa.Clear()
  $previous.Clear()
  $lines = $null
}
