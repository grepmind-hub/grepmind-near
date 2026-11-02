param([string]$BaseUrl = 'http://localhost:8080/api/v1')
$ErrorActionPreference = 'Stop'
# Local OTP stub only. Never use against production.
function Login-Local([string]$Phone) {
    $otp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/otp/request" -ContentType application/json -Body (@{phone_e164=$Phone} | ConvertTo-Json)
    $session = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/otp/verify" -ContentType application/json -Body (@{phone_e164=$Phone;otp_code=$otp.data.otp_code} | ConvertTo-Json)
    return @{Authorization="Bearer $($session.data.access_token)"}
}
$manager = Login-Local '+919861000005'
$staff = Login-Local '+919861000006'
$customer = Login-Local '+919999999999'
$category = $null
try {
    $category = Invoke-RestMethod -Method Post -Uri "$BaseUrl/merchant/catalog-categories" -Headers $manager -ContentType application/json -Body (@{name="Validation $([guid]::NewGuid())"} | ConvertTo-Json)
    $id = $category.data.id
    $null = Invoke-RestMethod -Method Patch -Uri "$BaseUrl/merchant/catalog-categories/$id" -Headers $manager -ContentType application/json -Body '{"name":"Updated validation category"}'
    $list = Invoke-RestMethod -Uri "$BaseUrl/merchant/catalog-categories" -Headers $manager
    if (-not ($list.data | Where-Object { $_.id -eq $id -and $_.name -eq 'Updated validation category' })) { throw 'Persistence assertion failed' }
    foreach ($headers in @($staff, $customer)) {
        $response = Invoke-WebRequest -Method Delete -Uri "$BaseUrl/merchant/catalog-categories/$id" -Headers $headers -SkipHttpErrorCheck
        if ($response.StatusCode -ne 403) { throw "Expected forbidden mutation, got $($response.StatusCode)" }
    }
    $anonymous = Invoke-WebRequest -Uri "$BaseUrl/merchant/catalog-categories" -SkipHttpErrorCheck
    if ($anonymous.StatusCode -ne 401) { throw 'Anonymous access was not rejected' }
    Write-Output 'PASS: create, update, persisted list, staff/customer denial, anonymous denial'
} finally {
    if ($category) { $null = Invoke-RestMethod -Method Delete -Uri "$BaseUrl/merchant/catalog-categories/$($category.data.id)" -Headers $manager }
}
Write-Output 'PASS: delete validation category'
