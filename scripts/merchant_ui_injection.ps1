param(
    [ValidateSet('Run','Inject','Cleanup')][string]$Action = 'Inject',
    [string[]]$Cities = @('Cuttack','Jajpur'),
    [string]$DeviceId = '',
    [string]$ApiBaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$EmulatorApiBaseUrl = 'http://10.0.2.2:80',
    [string]$Manifest = 'ui-injection-run.json',
    [ValidateSet('Products','Availability','Workspace','Analytics')][string]$Scenario = 'Products',
    [switch]$SkipAppRestore
)
$ErrorActionPreference = 'Stop'
if (([Uri]$EmulatorApiBaseUrl).Host -notin @('10.0.2.2','127.0.0.1','localhost')) {throw 'UI fixtures require a local emulator API endpoint'}
if (($Cities | Sort-Object -Unique) -join ',' -ne 'Cuttack,Jajpur') {throw 'Only the approved fixture cities Cuttack and Jajpur are supported'}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$wslRepo = (& wsl --exec wslpath -a $repo).Trim()
if ($LASTEXITCODE -ne 0) {throw 'WSL path resolution failed'}
if ([System.IO.Path]::GetFileName($Manifest) -ne $Manifest) {throw 'Manifest must be a filename in backend/'}
$manifestPath = Join-Path (Join-Path $repo 'backend') $Manifest
$common = @('--api',$ApiBaseUrl,'--manifest',$Manifest,'--allow-local-fixtures')
function Remove-InjectedData {
    & wsl --cd "$wslRepo/backend" --exec env APP_ENV=local DB_HOST=127.0.0.1 go run ./cmd/validate-cities @common --cleanup
    if ($LASTEXITCODE -ne 0) {throw 'Cleanup failed; retain the manifest and rerun -Action Cleanup'}
}
if ($Action -eq 'Cleanup') {
    if (-not (Test-Path -LiteralPath $manifestPath)) {Write-Output 'No injection manifest found; nothing to clean.'; return}
    Remove-InjectedData; return
}
if (Test-Path -LiteralPath $manifestPath) {throw 'Existing injection manifest found. Run -Action Cleanup first.'}
$bridge = $null
$vmBridge = $null
$linuxBridge = $null
$stopName = ".ui-bridge-$([guid]::NewGuid()).stop"
$stopFile = Join-Path $repo $stopName
$success = $false
try {
    $adb = (Get-Command adb.exe -ErrorAction Stop).Source
    if (-not $DeviceId) {
        $devices = @(& $adb devices | Select-String '^\S+\s+device$' | ForEach-Object {($_.Line -split '\s+')[0]})
        if ($devices.Count -ne 1) {throw 'Provide -DeviceId when zero or multiple Android devices are connected'}
        $DeviceId = $devices[0]
    }
    $abi = (& $adb -s $DeviceId shell getprop ro.product.cpu.abi).Trim()
    $androidTarget = switch ($abi) {'x86_64' {'android-x64'} 'arm64-v8a' {'android-arm64'} 'armeabi-v7a' {'android-arm'} default {throw "Unsupported Android ABI: $abi"}}
    $runMobile = Get-Content -Raw (Join-Path $repo 'run_mobile.sh')
    if ($runMobile -notmatch 'export PATH="([^:]+)') {throw 'Flutter path was not found in run_mobile.sh'}
    $flutterBin = $Matches[1]
    $route = & wsl --exec ip route show default
    if ($route -notmatch 'default via (\S+)') {throw 'WSL Windows-host gateway not found'}
    $gateway = $Matches[1]
    # Separate, host-only listener: no existing ADB daemon is stopped or replaced.
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($gateway),0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
    $python = (Get-Command python -ErrorAction Stop).Source
    $bridgeScript = Join-Path $PSScriptRoot 'adb_bridge.py'
    $bridge = Start-Process -FilePath $python -ArgumentList @("`"$bridgeScript`"",'--bind-ip',$gateway,'--bind-port',$port,'--stop-file',"`"$stopFile`"") -WindowStyle Hidden -PassThru
    $vmListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $vmListener.Start(); $vmPort = $vmListener.LocalEndpoint.Port; $vmListener.Stop()
    # Reserve the Windows side before WSL listens on the same localhost port.
    # This prevents WSL localhost forwarding from taking ADB's listener port.
    & $adb -s $DeviceId forward "tcp:$vmPort" tcp:1
    if ($LASTEXITCODE -ne 0) {throw 'Unable to reserve the Windows ADB VM-service forward'}
    $gatewayListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($gateway),0)
    $gatewayListener.Start(); $vmGatewayPort = $gatewayListener.LocalEndpoint.Port; $gatewayListener.Stop()
    $vmBridge = Start-Process -FilePath $python -ArgumentList @("`"$bridgeScript`"",'--bind-ip',$gateway,'--bind-port',$vmGatewayPort,'--target-port',$vmPort,'--stop-file',"`"$stopFile`"") -WindowStyle Hidden -PassThru
    $linuxBridge = Start-Process -FilePath (Get-Command wsl.exe).Source -ArgumentList @('--exec','python3',"$wslRepo/scripts/adb_bridge.py",'--bind-ip','127.0.0.1','--bind-port',$vmPort,'--target-ip',$gateway,'--target-port',$vmGatewayPort,'--stop-file',"$wslRepo/$stopName") -WindowStyle Hidden -PassThru
    $socket = "ADB_SERVER_SOCKET=tcp:${gateway}:$port"
    $pathEnv = "PATH=${flutterBin}:/usr/local/bin:/usr/bin:/bin"
    & wsl --cd "$wslRepo/backend" --exec env APP_ENV=local DB_HOST=127.0.0.1 go run ./cmd/validate-cities @common --cities ($Cities -join ',') --prepare-ui --media-base-url "$EmulatorApiBaseUrl"
    if ($LASTEXITCODE -ne 0) {throw 'Fixture preparation failed'}
    $ledger = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $payload = @{Run=$ledger.Run;Cases=$ledger.Cases;CustomerPhone=$ledger.CustomerPhone} | ConvertTo-Json -Depth 8 -Compress
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $compressedPayload = [IO.MemoryStream]::new()
    $gzipPayload = [IO.Compression.GZipStream]::new($compressedPayload,[IO.Compression.CompressionMode]::Compress)
    $gzipPayload.Write($payloadBytes,0,$payloadBytes.Length)
    $gzipPayload.Dispose()
    $encoded = [Convert]::ToBase64String($compressedPayload.ToArray())
    $compressedPayload.Dispose()
    $target = switch ($Scenario) {
        'Availability' {'integration_test/merchant_availability_e2e_test.dart'}
        'Workspace' {'integration_test/merchant_workspace_e2e_test.dart'}
        'Analytics' {'integration_test/merchant_views_e2e_test.dart'}
        default {'integration_test/merchant_ui_injection_test.dart'}
    }
    $mode = if ($Scenario -eq 'Availability') {'availability'} elseif ($Scenario -eq 'Workspace') {'workspace'} elseif ($Scenario -eq 'Analytics') {'analytics'} elseif ($Action -eq 'Inject') {'inject'} else {'cycle'}
    try {
        # Flutter driver emits informational VM-service lines on stderr. In
        # PowerShell with Stop preference they become terminating native errors
        # before Flutter's real exit code is checked; allow the process to finish
        # and evaluate its exit code explicitly instead.
        $ErrorActionPreference = 'Continue'
        & wsl --cd "$wslRepo/apps/mobile" --exec env $pathEnv $socket flutter drive --driver=test_driver/merchant_ui_driver.dart "--target=$target" -d $DeviceId --no-dds "--host-vmservice-port=$vmPort" "--dart-define=API_BASE_URL=$EmulatorApiBaseUrl" "--dart-define=UI_FIXTURES_GZIP=$encoded" "--dart-define=UI_MODE=$mode"
        $driveExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    if ($driveExitCode -ne 0) {throw 'Merchant UI injection validation failed'}
    $success = $true
} finally {
    try {
        if ((Test-Path -LiteralPath $manifestPath) -and ($Action -eq 'Run' -or -not $success)) {Remove-InjectedData}
    } finally {
        $null = New-Item -ItemType File -Path $stopFile -Force
        Start-Sleep -Milliseconds 1500
        foreach ($process in @($bridge,$vmBridge,$linuxBridge)) {if ($process -and -not $process.HasExited) {Stop-Process -Id $process.Id}}
        if ($vmPort -and $adb) {
            $forwards = & $adb -s $DeviceId forward --list
            if ($forwards -match "tcp:$vmPort\s") { & $adb -s $DeviceId forward --remove "tcp:$vmPort" }
        }
        Remove-Item -LiteralPath $stopFile -ErrorAction SilentlyContinue
        if (-not $SkipAppRestore -and $flutterBin -and $DeviceId) {
            & wsl --cd "$wslRepo/apps/mobile" --exec env $pathEnv flutter build apk --debug "--target-platform=$androidTarget" "--dart-define=API_BASE_URL=$EmulatorApiBaseUrl"
            if ($LASTEXITCODE -ne 0) {throw 'Fixture cleanup ran, but the normal app rebuild failed'}
            & $adb -s $DeviceId install -r (Join-Path $repo 'apps/mobile/build/app/outputs/flutter-apk/app-debug.apk')
            if ($LASTEXITCODE -ne 0) {throw 'Fixture cleanup ran, but normal app reinstall failed'}
        }
    }
}
if ($Action -eq 'Inject') {
    if ($Scenario -eq 'Workspace') {Write-Output 'Workspace QA requests/profile changes retained for inspection. Remove generated fixture data with this script -Action Cleanup.'}
    elseif ($Scenario -eq 'Analytics') {Write-Output 'View analytics QA fixtures retained for inspection. Remove generated fixture data with this script -Action Cleanup.'}
    else {Write-Output 'Injected products retained for inspection. Remove only these entries with this script -Action Cleanup.'}
}
