param(
  [ValidateSet('Run','Cleanup')][string]$Action = 'Run',
  [ValidateSet('Cuttack','Jajpur')][string]$City = 'Cuttack',
  [string]$Locality,
  [string]$Address,
  [string]$PostalCode,
  [string]$BusinessName,
  [string]$BusinessDescription,
  [string]$CategorySlug,
  [string]$ProductName,
  [string]$ProductDescription,
  [double]$ProductPrice,
  [string]$ApiBaseUrl = 'http://127.0.0.1:8080/api/v1',
  [string]$EmulatorApiBaseUrl = 'http://10.0.2.2:80',
  [string]$DeviceId = 'localhost:5555',
  [int]$AdbServerPort = 58991,
  [switch]$KeepData,
  [switch]$SkipAppRestore
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$wslRepo = (& wsl.exe --exec wslpath -a $repo).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the repository path in WSL.' }
if (([Uri]$ApiBaseUrl).Host -notin @('127.0.0.1','localhost')) { throw 'This QA flow is restricted to the local development API.' }
if (([Uri]$EmulatorApiBaseUrl).Host -notin @('10.0.2.2','127.0.0.1','localhost')) { throw 'This QA flow is restricted to an Android emulator loopback API.' }
if ($Action -eq 'Run' -and ($BusinessName.Length -lt 2 -or $BusinessName.Length -gt 80 -or $ProductName.Length -lt 2 -or $ProductName.Length -gt 100)) { throw 'Business and product names must be meaningful and within supported lengths.' }
if ($Action -eq 'Run' -and ($Locality.Length -lt 2 -or $Address.Length -lt 5 -or $PostalCode -notmatch '^\d{6}$' -or $BusinessDescription.Length -lt 8 -or $ProductDescription.Length -lt 8 -or $ProductPrice -le 0 -or [string]::IsNullOrWhiteSpace($CategorySlug))) { throw 'Provide a realistic locality, address, PIN, descriptions, active category slug and positive product price for the QA listing.' }
$manifestPath = Join-Path $repo 'backend\merchant-onboarding-e2e.json'
$commonWsl = @('--cd',"$wslRepo/backend",'--exec','env','APP_ENV=local','DB_HOST=127.0.0.1','S3_ENDPOINT=http://127.0.0.1:9000')
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'D:\emulator\android-sdk\platform-tools\adb.exe' }

function Remove-TestAccount([string]$Phone) {
  if ($Phone -notmatch '^\+91[6-9]\d{9}$') { throw 'Recovery manifest contains an invalid generated phone.' }
  & wsl.exe @commonWsl 'go' 'run' './cmd/merchant-e2e-cleanup' $Phone
  if ($LASTEXITCODE -ne 0) { throw 'Generated merchant cleanup failed. Keep the recovery manifest and retry with -Action Cleanup.' }
  Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
}

if ($Action -eq 'Cleanup') {
  if (-not (Test-Path -LiteralPath $manifestPath)) { Write-Output 'No merchant onboarding recovery manifest found.'; exit 0 }
  $saved = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  Remove-TestAccount $saved.phone_e164
  exit 0
}
if (Test-Path -LiteralPath $manifestPath) { throw 'A previous run needs cleanup. Run this script with -Action Cleanup first.' }

$bridge = $null; $vmBridge = $null; $linuxBridge = $null; $stopFile = $null; $vmPort = 0; $success = $false
try {
  $health = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') -replace '/api/v1$','/healthz') -TimeoutSec 5
  if ($health.status -ne 'ok') { throw 'Local API health check failed.' }
  $categories = (Invoke-RestMethod -Uri "$($ApiBaseUrl.TrimEnd('/'))/categories" -TimeoutSec 10).data
  if (-not ($categories | Where-Object { $_.slug -eq $CategorySlug })) { throw "Category '$CategorySlug' is not active in the local API taxonomy." }
  $locations = (Invoke-RestMethod -Uri "$($ApiBaseUrl.TrimEnd('/'))/locations" -TimeoutSec 10).data
  $location = $locations | Where-Object { $_.city -ieq $City } | Select-Object -First 1
  if (-not $location) { throw "No approved $City city center is available from the API for the test location." }

  # Generate a fresh local-only account and ensure it has never existed in this database.
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  do {
    $bytes = New-Object byte[] 10
    $rng.GetBytes($bytes)
    $first = 6 + ($bytes[0] % 4)
    $digits = [string]$first + (($bytes[1..9] | ForEach-Object { [string]($_ % 10) }) -join '')
    $phone = "+91$digits"
    $exists = (& wsl.exe --cd "$wslRepo" --exec docker compose exec -T postgres psql -U grepmind -d grepmind_near -Atqc "SELECT EXISTS(SELECT 1 FROM users WHERE phone_e164='$phone')")
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the generated phone against the local database.' }
  } while ("$exists".Trim() -eq 't')
  $rng.Dispose()
  @{ phone_e164 = $phone; generated_at_utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8

  # Start/reconnect only the configured development emulator; no SMS or real number is used.
  & (Join-Path $PSScriptRoot 'mobile_emulator.ps1') -Action Start -DeviceId $DeviceId -AdbServerPort $AdbServerPort -ApiBaseUrl $EmulatorApiBaseUrl
  $adbStarted = $false
  for ($attempt = 0; $attempt -lt 3 -and -not $adbStarted; $attempt++) {
    & $adb -P $AdbServerPort -a start-server 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      & $adb -P $AdbServerPort connect localhost:5555 2>$null | Out-Null
      $devices = & $adb -P $AdbServerPort devices 2>$null
      $adbStarted = ($LASTEXITCODE -eq 0 -and ($devices | Select-String '^localhost:5555\s+device'))
    }
    if (-not $adbStarted) { Start-Sleep -Seconds 2 }
  }
  if (-not $adbStarted) { throw 'Could not stabilize the Windows ADB server/emulator connection.' }

  $flutter = '/home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter'
  $sdk = '/home/grepmind/Android/Sdk'
  $route = (& wsl.exe --exec ip route show default | Select-String 'default via (\S+)' | Select-Object -First 1)
  if (-not $route) { throw 'WSL Windows-host gateway could not be found for the emulator bridge.' }
  $gateway = $route.Matches[0].Groups[1].Value
  # Windows relays use the Windows filesystem path; only the Linux relay below
  # receives the WSL /mnt path. Passing /mnt/... to Windows Python exits early.
  $routePath = (Resolve-Path (Join-Path $PSScriptRoot 'adb_bridge.py')).Path
  $stopName = ".merchant-e2e-$([guid]::NewGuid()).stop"
  $stopFile = Join-Path $repo $stopName
  $python = (Get-Command python -ErrorAction Stop).Source
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($gateway),0); $listener.Start(); $adbBridgePort = $listener.LocalEndpoint.Port; $listener.Stop()
  # This bridge must target the configured Windows ADB port. The bridge
  # utility defaults to 5037, which is wrong when the emulator uses 58991.
  $bridge = Start-Process -FilePath $python -ArgumentList @("`"$routePath`"",'--bind-ip',$gateway,'--bind-port',$adbBridgePort,'--target-port',$AdbServerPort,'--stop-file',"`"$stopFile`"") -WindowStyle Hidden -PassThru
  $portListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0); $portListener.Start(); $vmPort = $portListener.LocalEndpoint.Port; $portListener.Stop()
  & $adb -P $AdbServerPort -s $DeviceId forward "tcp:$vmPort" tcp:1
  if ($LASTEXITCODE -ne 0) { throw 'Unable to reserve the temporary integration-test service port.' }
  $hostListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($gateway),0); $hostListener.Start(); $vmGatewayPort = $hostListener.LocalEndpoint.Port; $hostListener.Stop()
  $vmBridge = Start-Process -FilePath $python -ArgumentList @("`"$routePath`"",'--bind-ip',$gateway,'--bind-port',$vmGatewayPort,'--target-port',$vmPort,'--stop-file',"`"$stopFile`"") -WindowStyle Hidden -PassThru
  $wslBridgePath = "$wslRepo/scripts/adb_bridge.py"
  $linuxBridge = Start-Process -FilePath (Get-Command wsl.exe).Source -ArgumentList @('--exec','python3',$wslBridgePath,'--bind-ip','127.0.0.1','--bind-port',$vmPort,'--target-ip',$gateway,'--target-port',$vmGatewayPort,'--stop-file',"$wslRepo/$stopName") -WindowStyle Hidden -PassThru
  $socket = "ADB_SERVER_SOCKET=tcp:${gateway}:$adbBridgePort"
  $pathEnv = "PATH=/home/grepmind/projects/flutter-setup/develop/flutter/bin:$sdk/platform-tools:/usr/local/bin:/usr/bin:/bin"
  $wslDevices = & wsl.exe --cd "$wslRepo/apps/mobile" --exec env $pathEnv $socket adb devices 2>&1
  if ($LASTEXITCODE -ne 0 -or -not ($wslDevices | Select-String '^localhost:5555\s+device$')) {
    throw "WSL cannot reach the configured Windows ADB server through its bridge. Device output: $($wslDevices -join ' ')"
  }
  $defines = @(
    "--dart-define=API_BASE_URL=$EmulatorApiBaseUrl",
    "--dart-define=TEST_PHONE_E164=$phone",
    "--dart-define=TEST_CITY=$City",
    "--dart-define=TEST_LOCALITY=$Locality",
    "--dart-define=TEST_POSTAL_CODE=$PostalCode",
    "--dart-define=TEST_ADDRESS=$Address",
    "--dart-define=TEST_CATEGORY_SLUG=$CategorySlug",
    "--dart-define=TEST_LATITUDE=$($location.latitude)",
    "--dart-define=TEST_LONGITUDE=$($location.longitude)",
    "--dart-define=TEST_BUSINESS_NAME=$BusinessName",
    "--dart-define=TEST_BUSINESS_DESCRIPTION=$BusinessDescription",
    "--dart-define=TEST_PRODUCT_NAME=$ProductName",
    "--dart-define=TEST_PRODUCT_DESCRIPTION=$ProductDescription",
    "--dart-define=TEST_PRODUCT_PRICE=$ProductPrice"
  )
  $flutterArgs = @('drive','--no-pub','--driver=test_driver/merchant_ui_driver.dart','--target=integration_test/merchant_onboarding_e2e_test.dart','-d',$DeviceId,'--no-dds',"--host-vmservice-port=$vmPort") + $defines
  & wsl.exe --cd "$wslRepo/apps/mobile" --exec env $pathEnv $socket $flutter @flutterArgs
  if ($LASTEXITCODE -ne 0) { throw 'Merchant onboarding UI/API automation failed.' }
  $success = $true
  Write-Output "PASS: fresh OTP merchant registered in $City, profile image uploaded, and product created with a retrievable category sample image."
} finally {
  if ($stopFile) { $null = New-Item -ItemType File -Path $stopFile -Force; Start-Sleep -Milliseconds 800 }
  foreach ($process in @($bridge,$vmBridge,$linuxBridge)) { if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue } }
  if ($vmPort -gt 0 -and (Test-Path $adb)) { & $adb -P $AdbServerPort -s $DeviceId forward --remove "tcp:$vmPort" 2>$null | Out-Null }
  if ($stopFile) { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue }
  if ((Test-Path -LiteralPath $manifestPath) -and (-not $KeepData -or -not $success)) {
    $saved = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    Remove-TestAccount $saved.phone_e164
  }
  if (-not $SkipAppRestore -and $Action -eq 'Run' -and (Test-Path $adb)) {
    & (Join-Path $PSScriptRoot 'mobile_emulator.ps1') -Action BuildRun -DeviceId $DeviceId -AdbServerPort $AdbServerPort -ApiBaseUrl $EmulatorApiBaseUrl
    if ($LASTEXITCODE -ne 0) { throw 'Fixture cleanup completed, but restoring the normal app build failed.' }
  }
}

if ($KeepData -and $success) { Write-Output 'QA account/media retained. Remove only this run with -Action Cleanup.' }
