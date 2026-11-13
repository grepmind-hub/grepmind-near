[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('customer', 'merchant', 'rider')][string]$Role,
  [Parameter(Mandatory = $true)][ValidatePattern('^emulator-\d+$')][string]$Serial,
  [Parameter(Mandatory = $false)][switch]$ManualEntry,
  [Parameter(Mandatory = $false)][switch]$KeepAppRunning,
  [Parameter(Mandatory = $false)][string]$AdbPath = 'D:\emulator\android-sdk\platform-tools\adb.exe',
  [Parameter(Mandatory = $false)][string]$RunnerEnvFile
)

$ErrorActionPreference = 'Stop'
$script:operation = 'initialization'
$expected = @{
  customer = @{ Avd = 'Pixel_8'; Phone = '+919990000171'; Workspace = 'Home' }
  merchant = @{ Avd = 'Pixel_8_Merchant_QA'; Phone = '+919990000172'; Workspace = 'Merchant Workspace' }
  rider = @{ Avd = 'Pixel_8_Rider_QA'; Phone = '+919990000173'; Workspace = 'Rider Dashboard' }
}
$target = $expected[$Role]
if (-not (Test-Path -LiteralPath $AdbPath)) { throw 'Windows-host ADB executable is unavailable.' }

function Invoke-WslBashScript([string]$ScriptText) {
  # Keep multiline shell text as one argument under Windows PowerShell 5.1.
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ScriptText))
  $command = "printf '%s' '$encoded' | base64 --decode | bash"
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& wsl.exe --exec bash -lc $command 2>&1)
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
}

function Resolve-RunnerEnvFile([string]$ExpectedPhone) {
  # QA setup rotates run IDs. Discover the single private runner file that
  # matches the currently running isolated API and inbox before requesting OTP.
  $scriptText = @'
set -uo pipefail
api=grepmind_4c_qa_api
inbox=grepmind_4c_qa_otp_inbox
runner_dir=/home/grepmind/.cache/grepmind/qa-otp-runs
expected_phone='__EXPECTED_PHONE__'
getenv() { printf '%s\n' "$1" | awk -F= -v key="$2" '$1==key {sub(/^[^=]*=/, ""); print; exit}'; }
api_state=$(docker inspect --format '{{.State.Status}}' "$api" 2>/dev/null || printf missing)
inbox_state=$(docker inspect --format '{{.State.Status}}' "$inbox" 2>/dev/null || printf missing)
api_running=no; [[ "$api_state" == running ]] && api_running=yes
inbox_running=no; [[ "$inbox_state" == running ]] && inbox_running=yes
api_env=''; inbox_env=''
[[ "$api_running" == yes ]] && api_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$api" 2>/dev/null || true)
[[ "$inbox_running" == yes ]] && inbox_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$inbox" 2>/dev/null || true)
api_run=$(getenv "$api_env" QA_OTP_RUN_ID)
inbox_run=$(getenv "$inbox_env" QA_OTP_RUN_ID)
api_allowlist=$(getenv "$api_env" QA_OTP_ALLOWLIST)
reader_runner=$(getenv "$inbox_env" QA_OTP_RUNNER_ID)
reader_secret=$(getenv "$inbox_env" QA_OTP_RUNNER_SECRET)
config_ok=no
if [[ "$api_running" == yes && "$inbox_running" == yes &&
  "$(getenv "$api_env" APP_ENV)" == qa && "$(getenv "$api_env" OTP_PROVIDER)" == qa_http &&
  "$(getenv "$api_env" QA_OTP_DELIVERY_ENABLED)" == true &&
  "$(getenv "$inbox_env" APP_ENV)" == qa && "$(getenv "$inbox_env" QA_OTP_READER_ENABLED)" == true ]]; then config_ok=yes; fi
run_match=no; [[ -n "$api_run" && "$api_run" == "$inbox_run" ]] && run_match=yes
phone_allowed=no; [[ ",${api_allowlist}," == *",${expected_phone},"* ]] && phone_allowed=yes
reader_health=$(curl --max-time 3 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:18085/healthz 2>/dev/null || printf unreachable)
matches=()
protected_files=0
[[ -d "$runner_dir" ]] && shopt -s nullglob
for candidate in "$runner_dir"/*.env; do
  [[ -f "$candidate" ]] || continue
  [[ "$(stat -c '%a' "$candidate")" == 600 && "$(stat -c '%u' "$candidate")" == "$(id -u)" ]] || continue
  protected_files=$((protected_files+1))
  if (
    set -a
    . "$candidate"
    set +a
    [[ "${QA_OTP_RUN_ID:-}" == "$api_run" && "${QA_OTP_RUNNER_ID:-}" == "$reader_runner" && "${QA_OTP_RUNNER_SECRET:-}" == "$reader_secret" && "${QA_OTP_READER_URL:-}" == http://127.0.0.1:18085 ]]
  ); then matches+=("$candidate"); fi
done
printf 'QA_PREFLIGHT=api_running=%s inbox_running=%s qa_config=%s run_id_match=%s account_allowed=%s reader_health=%s protected_env_files=%s matching_env_files=%s\n' \
  "$api_running" "$inbox_running" "$config_ok" "$run_match" "$phone_allowed" "$reader_health" "$protected_files" "${#matches[@]}"
[[ "$config_ok" == yes && "$run_match" == yes && "$phone_allowed" == yes && "$reader_health" == 204 && "${#matches[@]}" == 1 ]] || exit 2
printf 'RUNNER_ENV_FILE=%s\n' "${matches[0]}"
'@.Replace('__EXPECTED_PHONE__', $ExpectedPhone)
  $discovery = Invoke-WslBashScript $scriptText
  if ($discovery.ExitCode -ne 0) {
    $preflight = @($discovery.Output | ForEach-Object { $_.ToString() } | Where-Object { $_ -like 'QA_PREFLIGHT=*' })
    if ($preflight.Count -eq 1) {
      throw "Protected QA reader preflight failed ($($preflight[0])). No OTP was requested."
    }
    throw 'Protected QA reader preflight failed; isolated API/inbox diagnostics were incomplete. No OTP was requested.'
  }
  $pathLines = @($discovery.Output | ForEach-Object { $_.ToString() } | Where-Object { $_ -like 'RUNNER_ENV_FILE=*' })
  if ($pathLines.Count -ne 1) {
    throw 'The isolated QA environment did not resolve one matching protected runner file. No OTP was requested.'
  }
  return $pathLines[0].Substring('RUNNER_ENV_FILE='.Length)
}

$resolvedRunnerEnvFile = Resolve-RunnerEnvFile $target.Phone
if (-not [string]::IsNullOrWhiteSpace($RunnerEnvFile) -and $RunnerEnvFile -ne $resolvedRunnerEnvFile) {
  throw 'The supplied runner file does not match the active isolated QA API and OTP inbox. No OTP was requested.'
}
$RunnerEnvFile = $resolvedRunnerEnvFile
if ($RunnerEnvFile -notmatch '^/home/grepmind/\.cache/grepmind/qa-otp-runs/[A-Za-z0-9._-]+\.env$') {
  throw 'Resolved QA runner file is outside the protected runner directory.'
}

function Invoke-Adb([string[]]$Arguments) {
  # PowerShell 5.1 treats native stderr as an ErrorRecord. Some successful ADB
  # commands (notably `monkey`) write status text there, so prevent that text
  # from terminating the runner while still checking the actual process exit.
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $AdbPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  if ($exitCode -ne 0) { throw "ADB command failed during $script:operation; sensitive input is suppressed." }
  return (($output | ForEach-Object { $_.ToString() }) -join "`n")
}

function Get-UiXml {
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      $script:operation = 'accessibility-tree capture'
      [void](Invoke-Adb @('-s', $Serial, 'shell', 'uiautomator', 'dump', '/sdcard/auth-otp-ui.xml'))
      $script:operation = 'accessibility-tree read'
      return Invoke-Adb @('-s', $Serial, 'shell', 'cat', '/sdcard/auth-otp-ui.xml')
    } catch {
      if ($attempt -eq 3) { throw }
      Start-Sleep -Milliseconds 800
    }
  }
  throw 'Accessibility tree was unavailable after bounded retries.'
}

function Get-NodeCenter([string]$Xml, [string]$Pattern) {
  try { [xml]$tree = $Xml } catch { return $null }
  $best = $null
  foreach ($node in $tree.SelectNodes('//node')) {
    $label = @($node.GetAttribute('text'), $node.GetAttribute('content-desc'), $node.GetAttribute('hint')) -join ' '
    if ($label -match $Pattern) {
      # Flutter semantics often expose a non-clickable TextView inside the
      # clickable tab/button. Resolve the nearest actionable ancestor instead
      # of falling back to stale coordinates (important for duplicate labels
      # such as Merchant's nested Profile and workspace Profile tabs).
      $targetNode = $node
      while ($targetNode -is [System.Xml.XmlElement] -and
        $targetNode.GetAttribute('enabled') -ne 'false' -and
        $targetNode.GetAttribute('clickable') -ne 'true' -and
        $targetNode.GetAttribute('class') -notmatch 'EditText') {
        $targetNode = $targetNode.ParentNode
      }
      if ($targetNode -isnot [System.Xml.XmlElement] -or $targetNode.GetAttribute('enabled') -eq 'false') { continue }
      if ($targetNode.GetAttribute('bounds') -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
        $left = [int]$Matches[1]; $top = [int]$Matches[2]
        $right = [int]$Matches[3]; $bottom = [int]$Matches[4]
        $candidate = @{ X = [int](($left + $right) / 2); Y = [int](($top + $bottom) / 2) }
        if ($null -eq $best -or $candidate.Y -gt $best.Y) { $best = $candidate }
      }
    }
  }
  return $best
}
function Tap-Pattern([string]$Pattern, [string]$Fallback) {
  $xml = Get-UiXml
  $point = Get-NodeCenter $xml $Pattern
  if ($null -eq $point) {
    $parts = $Fallback.Split(',')
    $point = @{ X = [int]$parts[0]; Y = [int]$parts[1] }
  }
  $script:operation = 'visible UI tap'
  [void](Invoke-Adb @('-s', $Serial, 'shell', 'input', 'tap', "$($point.X)", "$($point.Y)"))
  Start-Sleep -Milliseconds 700
}

function Type-Text([string]$Value) {
  $script:operation = 'UI text entry'
  [void](Invoke-Adb @('-s', $Serial, 'shell', 'input', 'text', $Value))
}

function Continue-RoleSelection {
  for ($i = 0; $i -lt 8; $i++) {
    $xml = Get-UiXml
    if ($xml -match 'Continue to workspace|Switch workspace') {
      Tap-Pattern 'Continue to workspace|Switch workspace' '540,2300'
      return
    }
    $script:operation = 'scroll role selection to continue button'
    [void](Invoke-Adb @('-s', $Serial, 'shell', 'input', 'swipe', '540', '2050', '540', '650', '500'))
    Start-Sleep -Milliseconds 350
  }
  throw 'Role selection continue action was not visible after scrolling.'
}
function Get-ChallengeIdsFromLog {
  $log = Invoke-Adb @('-s', $Serial, 'logcat', '-d', '-v', 'brief', '-s', 'flutter')
  $matches = [regex]::Matches($log, 'QA_OTP_CHALLENGE \{"challenge_id":"([0-9a-f-]{36})","expires_at":"([^"]+)"\}')
  return @($matches | ForEach-Object { $_.Groups[1].Value })
}

function Get-ChallengeFromLog([string[]]$ExcludeChallengeIds) {
  $log = Invoke-Adb @('-s', $Serial, 'logcat', '-d', '-v', 'brief', '-s', 'flutter')
  $matches = [regex]::Matches($log, 'QA_OTP_CHALLENGE \{"challenge_id":"([0-9a-f-]{36})","expires_at":"([^"]+)"\}')
  for ($i = $matches.Count - 1; $i -ge 0; $i--) {
    $match = $matches[$i]
    $id = $match.Groups[1].Value
    if ($ExcludeChallengeIds -contains $id) { continue }
    $expiry = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($match.Groups[2].Value, [ref]$expiry) -or $expiry -le [DateTimeOffset]::UtcNow) { continue }
    return @{ challenge_id = $id; expires_at = $match.Groups[2].Value }
  }
  return $null
}

$avd = (Invoke-Adb @('-s', $Serial, 'emu', 'avd', 'name')).Split("`n")[0].Trim()
if ($avd -ne $target.Avd) { throw "Expected $($target.Avd), found $avd; refusing login." }
$state = (Invoke-Adb @('-s', $Serial, 'get-state')).Trim()
if ($state -ne 'device') { throw "Emulator $Serial is not online." }

# Route emulator loopback only to the isolated QA API on the Windows host.
$script:operation = 'QA API reverse route'
[void](Invoke-Adb @('-s', $Serial, 'reverse', 'tcp:18083', 'tcp:18083'))
if ($KeepAppRunning) {
  $script:operation = 'verify existing login screen'
  $xml = Get-UiXml
  if ($xml -notmatch 'Mobile number|Continue securely|otp-step|Verification code') {
    throw 'KeepAppRunning requires the normal login screen; no OTP was requested.'
  }
} else {
  $script:operation = 'app relaunch'
  [void](Invoke-Adb @('-s', $Serial, 'shell', 'am', 'force-stop', 'local.grepmind.grepmind_mobile'))
  [void](Invoke-Adb @('-s', $Serial, 'shell', 'monkey', '-p', 'local.grepmind.grepmind_mobile', '1'))
  Start-Sleep -Seconds 12
  $xml = Get-UiXml
}

# If a restored session has no active workspace yet, enter the backend-approved
# role via the normal picker so that logout can be performed from Profile.
if ($xml -match 'Select Portal Experience|Customer / Explorer|Merchant & Service Pro|Platform Administrator') {
  Tap-Pattern $Role '540,900'
  Continue-RoleSelection
  Start-Sleep -Seconds 5
  $xml = Get-UiXml
}

# Sign out through the actual app UI if a previous QA session was restored.
if ($xml -match 'Merchant Workspace|Rider dashboard|Home|Explore|Dashboard') {
  # Match the workspace-level Profile destination only. Merchant and Rider
  # screens can also contain nested Profile tabs with the same plain label.
  Tap-Pattern 'Profile\s*Tab 5 of 5' '970,2250'
  $xml = Get-UiXml
  for ($i = 0; $i -lt 4 -and $xml -notmatch 'Log out|Sign out'; $i++) {
    [void](Invoke-Adb @('-s', $Serial, 'shell', 'input', 'swipe', '540', '1900', '540', '750', '450'))
    Start-Sleep -Milliseconds 400
    $xml = Get-UiXml
  }
  if ($xml -match 'Log out|Sign out') {
    Tap-Pattern 'Log out|Sign out' '540,2100'
    Start-Sleep -Seconds 1
    $xml = Get-UiXml
    if ($xml -match 'Are you sure you want to log out') { Tap-Pattern 'LOG OUT' '700,1400' }
    Start-Sleep -Seconds 3
    $xml = Get-UiXml
  }
}

# If the auth restore is still in progress, wait for its normal completion.
for ($i = 0; $i -lt 20 -and $xml -notmatch 'Mobile number|Continue securely|otp-step|Verification code'; $i++) {
  Start-Sleep -Seconds 1
  $xml = Get-UiXml
}
if ($xml -notmatch 'Mobile number|Continue securely|otp-step|Verification code') {
  throw 'The normal OTP login screen did not become available; no OTP was requested.'
}

Tap-Pattern 'Mobile number|Phone number' '500,950'
Type-Text $target.Phone.Substring(3)
$previousChallengeIds = @(Get-ChallengeIdsFromLog)
Tap-Pattern 'Continue securely' '540,1140'

$challenge = $null
 $otpUiVisible = $false
for ($i = 0; $i -lt 20 -and ($null -eq $challenge -or -not $otpUiVisible); $i++) {
  Start-Sleep -Milliseconds 500
  $xml = Get-UiXml
  $otpUiVisible = $xml -match 'Verify and sign in|6-digit verification code|Six-digit verification code'
  if ($xml -match 'Please wait before requesting another OTP|verification is currently unavailable|Could not send a verification code') {
    throw 'The normal OTP request was rejected or rate-limited; the scoped reader was not called.'
  }
  $challenge = Get-ChallengeFromLog $previousChallengeIds
}
if ($null -eq $challenge) { throw 'No fresh challenge metadata appeared; no OTP reader call was made.' }
if (-not $otpUiVisible) { throw 'The actual OTP input UI was not visible; the scoped reader was not called.' }

$scopePath = Join-Path $env:TEMP ("grepmind-otp-scope-{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
  $scope = @{ challenge_id = $challenge.challenge_id; expires_at = $challenge.expires_at; phone_e164 = $target.Phone; purpose = 'login' }
  $scope | ConvertTo-Json -Compress | Set-Content -LiteralPath $scopePath -Encoding Ascii
  $wslScope = (wsl.exe --exec wslpath -a $scopePath 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $wslScope.StartsWith('/mnt/')) { throw 'Challenge metadata could not be passed to the protected QA reader.' }
  $linuxEnv = $RunnerEnvFile.Replace('\', '/')
  $readerCommand = "set -e; cd /mnt/d/grepmind-near; set -a; source '$linuxEnv'; set +a; node scripts/qa/qa-otp-read-scope.mjs '$wslScope'"
  $readerResult = Invoke-WslBashScript "set -e; cd /mnt/d/grepmind-near; set -a; source '$linuxEnv'; set +a; node scripts/qa/qa-otp-read-scope.mjs '$wslScope'"
  $codeLines = $readerResult.Output
  if ($readerResult.ExitCode -ne 0) { throw 'The scoped QA reader rejected this challenge. No OTP was entered; confirm that the active QA reader still matches the isolated API run.' }
  $otp = ($codeLines -join '').Trim()
  $codeLines = $null
  if ($otp -notmatch '^\d{6}$') { throw 'The scoped QA OTP response was invalid.' }

  if ($ManualEntry) {
    # Explicit trusted-host operator mode for isolated synthetic QA only. The
    # code is not sent to the app, backend response, file, or application log.
    # The operator types it into the already-open normal OTP screen.
    Write-Host "Manual QA OTP for $Role (one-time; expires $($challenge.expires_at)): $otp"
    Write-Host 'Enter this code in the emulator OTP field and submit through the normal Verify action.'
    $otp = $null
    return
  }

  # OTP exists only in this process memory and the ADB input buffer; never log it.
  # The OTP TextField is autofocus on this screen. Enter through that focused
  # real Flutter field, dismiss the keyboard, then tap its normal Verify action.
  Type-Text $otp
  $otp = $null
  $script:operation = 'dismiss OTP keyboard'
  [void](Invoke-Adb @('-s', $Serial, 'shell', 'input', 'keyevent', '4'))
  Tap-Pattern 'Verify and sign in' '540,1220'
  Start-Sleep -Seconds 6

  # Select the backend-authorized role through the normal role picker if shown.
  $xml = Get-UiXml
  if ($xml -match 'Select Portal Experience|Customer / Explorer|Merchant & Service Pro|Platform Administrator') {
    Tap-Pattern $Role '540,900'
    Continue-RoleSelection
    Start-Sleep -Seconds 5
  }
  $xml = Get-UiXml
  if ($xml -notmatch [regex]::Escape($target.Workspace)) {
    throw "Authenticated $Role workspace was not observed in the actual emulator UI."
  }

  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $evidenceDir = Join-Path $repoRoot 'docs\phases\evidence\auth-otp-02'
  New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
  $screenshot = Join-Path $evidenceDir "$Role-workspace.png"
  [void](Invoke-Adb @('-s', $Serial, 'shell', 'screencap', '-p', '/sdcard/auth-otp-02.png'))
  [void](Invoke-Adb @('-s', $Serial, 'pull', '/sdcard/auth-otp-02.png', $screenshot))
  Write-Output "PASS: fresh challenge auto-entered by Windows QA runner; $Role workspace authenticated on $avd ($Serial)."
} finally {
  Remove-Item -LiteralPath $scopePath -Force -ErrorAction SilentlyContinue
  $otp = $null
}
