<#
.SYNOPSIS
    Starts, stops, builds, and runs the Grepmind Near Android app.
.EXAMPLE
    ./scripts/mobile_emulator.ps1 -Action Start
.EXAMPLE
    ./scripts/mobile_emulator.ps1 -Action Build
.EXAMPLE
    ./scripts/mobile_emulator.ps1 -Action Run
.EXAMPLE
    ./scripts/mobile_emulator.ps1 -Action BuildRun
#>
param(
    [ValidateSet('Start', 'Stop', 'Restart', 'Build', 'Run', 'BuildRun', 'Status')]
    [string]$Action = 'Status',
    [string]$AvdName = 'Pixel_8',
    [string]$DeviceId = 'emulator-5554',
    [string]$ApiBaseUrl = 'http://172.18.160.150:80',
    [ValidateRange(1024,65535)][int]$AdbServerPort = 5037,
    [string]$WindowsSdk = 'D:\emulator\android-sdk',
    [string]$WslFlutter = '/home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter',
    [string]$WslAndroidSdk = '/home/grepmind/Android/Sdk'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mobileRoot = Join-Path $repoRoot 'apps\mobile'
$adb = Join-Path $WindowsSdk 'platform-tools\adb.exe'
$emulator = Join-Path $WindowsSdk 'emulator\emulator.exe'
$packageName = 'local.grepmind.grepmind_mobile'
$env:ADB_SERVER_PORT = "$AdbServerPort"

if ($ApiBaseUrl -notmatch '^https?://[A-Za-z0-9.\-:\[\]]+(:[0-9]{1,5})?(/[^\s]*)?$') {
    throw "API_BASE_URL must be an http(s) URL without whitespace: $ApiBaseUrl"
}
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw "ADB not found: $adb" }
if (-not (Test-Path -LiteralPath $emulator -PathType Leaf)) { throw "Emulator not found: $emulator" }

function Invoke-Adb {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & $adb -P $AdbServerPort @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ADB failed ($LASTEXITCODE): adb $($Arguments -join ' ')" }
}

function Get-EmulatorState {
    $output = & $adb -P $AdbServerPort devices 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not query ADB devices. Start or repair the Windows ADB server first. $($output -join ' ')" }
    $line = $output | Select-String -Pattern "^$([regex]::Escape($DeviceId))\s+(.+)$" | Select-Object -First 1
    if (-not $line) { return 'absent' }
    return $line.Matches[0].Groups[1].Value.Trim()
}

function Connect-TcpEmulatorIfNeeded {
    if ($DeviceId -ne 'emulator-5554') { return }
    $emulatorProcess = Get-Process -Name 'qemu-system-x86_64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $emulatorProcess) { return }
    $devices = & $adb -P $AdbServerPort devices 2>&1
    if ($devices | Select-String -Pattern '^emulator-5554\s+device(?:\s|$)') { return }

    # With a non-default ADB server port the emulator may not auto-register.
    # Connect its standard local transport port and use the resulting serial.
    $connectOutput = & $adb -P $AdbServerPort connect localhost:5555 2>&1
    if ($LASTEXITCODE -ne 0) { return }
    $devices = & $adb -P $AdbServerPort devices 2>&1
    if ($devices | Select-String -Pattern '^localhost:5555\s+device(?:\s|$)') {
        $script:DeviceId = 'localhost:5555'
        Write-Host 'Connected Pixel AVD through localhost:5555 (alternate ADB server port).'
    }
}

function Start-Emulator {
    # -a makes the Windows ADB server reachable from WSL2.
    $serverOutput = & $adb -P $AdbServerPort -a start-server 2>&1
    if ($LASTEXITCODE -ne 0) {
        # ADB can report a startup handshake error while its daemon is still exiting.
        Start-Sleep -Seconds 2
        $serverOutput = & $adb -P $AdbServerPort -a start-server 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not start the Windows ADB server after retrying. $($serverOutput -join ' ')"
        }
    }
    $state = Get-EmulatorState
    if ($state -eq 'absent') {
        $emulatorProcess = Get-Process -Name 'qemu-system-x86_64' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $emulatorProcess) {
            Start-Process -FilePath $emulator -ArgumentList @('-avd', $AvdName, '-no-snapshot-load') -WindowStyle Normal
        } else {
            Write-Host "An emulator process is already running; waiting for ADB to reconnect."
        }
    } elseif ($state -notin @('device', 'offline')) {
        throw "Emulator $DeviceId is '$state'. Resolve its ADB state before continuing."
    }

    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 2
        Connect-TcpEmulatorIfNeeded
        $state = Get-EmulatorState
        if ($state -eq 'device') {
            try {
                $bootOutput = & $adb -P $AdbServerPort -s $DeviceId shell getprop sys.boot_completed 2>$null
                $booted = if ($bootOutput) { "$($bootOutput | Select-Object -Last 1)".Trim() } else { '' }
            } catch {
                $booted = ''
            }
            if ($booted -eq '1') {
                Write-Host "Android ready: $DeviceId ($AvdName)"
                return
            }
        } elseif ($state -notin @('absent', 'offline')) {
            throw "Emulator $DeviceId entered unexpected ADB state '$state'."
        }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $DeviceId to finish booting. Current ADB state: $state"
}

function Stop-Emulator {
    $state = Get-EmulatorState
    if ($state -eq 'absent') {
        Write-Host "Emulator $DeviceId is already stopped."
        return
    }
    if ($state -ne 'device') {
        throw "Emulator $DeviceId is '$state'; ADB cannot shut it down cleanly. Close its window or restore ADB connectivity."
    }
    Invoke-Adb -Arguments @('-s', $DeviceId, 'emu', 'kill')
    Write-Host "Shutdown requested for $DeviceId."
}

function Invoke-WslFlutter {
    param([Parameter(Mandatory)][ValidateSet('build', 'run')][string]$FlutterAction)
    if ($repoRoot -notmatch '^([A-Za-z]):\\(.+)$') { throw "Expected a drive-mounted Windows repository path: $repoRoot" }
    $wslRoot = "/mnt/$($Matches[1].ToLowerInvariant())/$($Matches[2].Replace('\', '/'))"
    $flutterWsl = $WslFlutter.Replace("'", "'\''")
    $sdkWsl = $WslAndroidSdk.Replace("'", "'\''")
    $rootWsl = $wslRoot.Replace("'", "'\''")
    $apiWsl = $ApiBaseUrl.Replace("'", "'\''")
    $flutterArgs = if ($FlutterAction -eq 'build') {
        "build apk --debug --no-pub --dart-define=API_BASE_URL=$apiWsl"
    } else {
        "run --no-pub -d '$DeviceId' --dart-define=API_BASE_URL=$apiWsl"
    }
    $flutterBin = $WslFlutter.Substring(0, $WslFlutter.LastIndexOf('/'))
    $bashStatements = @(
        "export ANDROID_HOME='$sdkWsl'",
        'export ANDROID_SDK_ROOT="$ANDROID_HOME"',
        "export PATH='${flutterBin}:$sdkWsl/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'",
        ('export ADB_SERVER_SOCKET="tcp:$(ip route show default | awk ''/^default/ {print $3; exit}''):' + $AdbServerPort + '"'),
        $(if ($FlutterAction -eq 'run') {
            "adb -s '$DeviceId' get-state 2>/dev/null | grep -qx 'device' || { echo 'WSL cannot reach the emulator through Windows ADB. Check adb -a start-server and the private WSL firewall.' >&2; exit 3; }"
        }),
        "cd '$rootWsl/apps/mobile'",
        "'$flutterWsl' $flutterArgs"
    )
    $command = $bashStatements -join "`n"
    Write-Host "Running Flutter $FlutterAction in WSL for $DeviceId..."
    & wsl.exe --exec bash -lc $command
    if ($LASTEXITCODE -ne 0) { throw "Flutter $FlutterAction failed ($LASTEXITCODE)." }
}

switch ($Action) {
    'Status' {
        try { $state = Get-EmulatorState }
        catch { $state = "ADB unavailable - $($_.Exception.Message)" }
        Write-Host "Repository: $repoRoot"
        Write-Host "AVD: $AvdName ($DeviceId) - $state"
        Write-Host "Windows ADB: $adb (server port $AdbServerPort)"
        Write-Host "WSL Flutter: $WslFlutter"
        Write-Host "API base URL: $ApiBaseUrl"
    }
    'Start' { Start-Emulator }
    'Stop' { Stop-Emulator }
    'Restart' { Stop-Emulator; Start-Emulator }
    'Build' { Invoke-WslFlutter -FlutterAction build }
    'Run' { Start-Emulator; Invoke-WslFlutter -FlutterAction run }
    'BuildRun' {
        Start-Emulator
        Invoke-WslFlutter -FlutterAction build
        $apk = Join-Path $mobileRoot 'build\app\outputs\flutter-apk\app-debug.apk'
        if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "Build succeeded but APK was not found: $apk" }
        Invoke-Adb -Arguments @('-s', $DeviceId, 'install', '-r', $apk)
        Invoke-Adb -Arguments @('-s', $DeviceId, 'shell', 'am', 'start', '-n', "$packageName/.MainActivity")
    }
}
