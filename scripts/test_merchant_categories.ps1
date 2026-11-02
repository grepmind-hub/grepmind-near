param(
    [string[]]$Cities = @('Cuttack', 'Jajpur'),
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$Manifest = 'city-validation-run.json',
    [switch]$Cleanup
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$wslRepo = (& wsl --exec wslpath -a $repo).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository in WSL' }
$runnerArgs = @('--api', $BaseUrl, '--manifest', $Manifest, '--allow-local-fixtures')
if ($Cleanup) { $runnerArgs += '--cleanup' }
else { $runnerArgs += @('--cities', ($Cities -join ',')) }
& wsl --cd "$wslRepo/backend" --exec env APP_ENV=local DB_HOST=127.0.0.1 go run ./cmd/validate-cities @runnerArgs
if ($LASTEXITCODE -ne 0) { throw 'City/category validation failed. Review output; retain the manifest if cleanup failed.' }
