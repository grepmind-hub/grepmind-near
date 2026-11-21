<# Creates a new Android signing key once. The password is protected with
   Windows DPAPI for the current Windows account and is never printed. #>
$ErrorActionPreference = 'Stop'
$keytool = (Get-Command keytool -ErrorAction Stop).Source
$signingDir = Join-Path $env:USERPROFILE 'AbashyakaSigning'
$keyPath = Join-Path $signingDir 'abashyaka-release.jks'
$passwordPath = Join-Path $signingDir 'abashyaka-release-password.dpapi'
if (Test-Path -LiteralPath $signingDir) {
    throw 'The signing directory already exists; inspect it before creating a key.'
}
New-Item -ItemType Directory -Path $signingDir | Out-Null
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $signingDir /inheritance:r /grant:r "*${identity}:(OI)(CI)F" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not secure the signing directory; no key generated.' }
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$env:ABASHYAKA_SIGNING_PASSWORD = [Convert]::ToHexString($bytes)
try {
    $securePassword = ConvertTo-SecureString $env:ABASHYAKA_SIGNING_PASSWORD -AsPlainText -Force
    $encryptedPassword = ConvertFrom-SecureString $securePassword
    [System.IO.File]::WriteAllText($passwordPath, $encryptedPassword)
    & $keytool -genkeypair -v -keystore $keyPath -storetype PKCS12 -alias abashyaka-release `
        -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=Abashyaka' `
        -storepass:env ABASHYAKA_SIGNING_PASSWORD -keypass:env ABASHYAKA_SIGNING_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Key generation failed; preserve the directory for inspection.' }
    & $keytool -list -keystore $keyPath -storetype PKCS12 -alias abashyaka-release `
        -storepass:env ABASHYAKA_SIGNING_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Key verification failed; preserve the directory for inspection.' }
    Write-Output "Signing key generated and verified at $keyPath; password is DPAPI-protected for the current Windows account."
} finally {
    Remove-Item Env:ABASHYAKA_SIGNING_PASSWORD -ErrorAction SilentlyContinue
    [Array]::Clear($bytes, 0, $bytes.Length)
}
