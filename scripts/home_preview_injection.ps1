param(
    [ValidateSet('Prepare','Inject','BuildRun','Cleanup')][string]$Action = 'Inject',
    [string]$Manifest = 'home-preview-injection.json',
    [string]$ApiBaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$EmulatorApiBaseUrl = 'http://10.0.2.2:80',
    [ValidateRange(1024,65535)][int]$AdbServerPort = 5037
)

$ErrorActionPreference = 'Stop'
if (([Uri]$EmulatorApiBaseUrl).Host -notin @('10.0.2.2','127.0.0.1','localhost')) {
    throw 'Home preview fixtures require a local Android emulator API endpoint.'
}
if ([System.IO.Path]::GetFileName($Manifest) -ne $Manifest) {
    throw 'Manifest must be a filename inside backend/.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$wslRepo = (& wsl --exec wslpath -a $repo).Trim()
if ($LASTEXITCODE -ne 0) { throw 'WSL path resolution failed.' }
$manifestPath = Join-Path (Join-Path $repo 'backend') $Manifest
$common = @('--api',$ApiBaseUrl,'--manifest',$Manifest,'--allow-local-fixtures')

function Invoke-Cleanup {
    & wsl --cd "$wslRepo/backend" --exec env APP_ENV=local DB_HOST=127.0.0.1 go run ./cmd/validate-cities @common --cleanup
    if ($LASTEXITCODE -ne 0) { throw 'Cleanup failed; keep the manifest and retry -Action Cleanup.' }
}

if ($Action -eq 'Cleanup') {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Output 'No Home preview manifest found; nothing was changed.'
        return
    }
    Invoke-Cleanup
    return
}

if ($Action -eq 'BuildRun') {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw 'Home preview fixtures are missing. Run -Action Inject first.'
    }
    & (Join-Path $PSScriptRoot 'mobile_emulator.ps1') -Action BuildRun -ApiBaseUrl $EmulatorApiBaseUrl -AdbServerPort $AdbServerPort
    if ($LASTEXITCODE -ne 0) { throw 'Emulator build/run failed; preview fixtures remain for retry or cleanup.' }
    return
}

if (Test-Path -LiteralPath $manifestPath) {
    throw 'Home preview manifest already exists. Review it and use -Action Cleanup before another injection.'
}
& wsl --cd "$wslRepo/backend" --exec env APP_ENV=local DB_HOST=127.0.0.1 go run ./cmd/validate-cities @common --cities Cuttack,Jajpur --prepare-home-preview --media-base-url $EmulatorApiBaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Home preview data preparation failed; inspect the manifest for safe recovery.' }
if ($Action -eq 'Prepare') {
    Write-Output "Home preview fixtures are ready for inspection. Fixture ledger: $manifestPath. Launch the app with -Action BuildRun; remove only these fixtures later with -Action Cleanup."
    return
}
& (Join-Path $PSScriptRoot 'mobile_emulator.ps1') -Action BuildRun -ApiBaseUrl $EmulatorApiBaseUrl -AdbServerPort $AdbServerPort
if ($LASTEXITCODE -ne 0) { throw 'Emulator build/run failed; preview fixtures remain for retry or cleanup.' }
Write-Output "Home preview is ready on the emulator. Fixture ledger: $manifestPath. Remove only these fixtures later with -Action Cleanup."
