# Prueba SIN riesgo del plugin goride-rider-api: no crea reservas ni avisa a conductores.
# Uso:  powershell -ExecutionPolicy Bypass -File .\scripts\probar_rider_api.ps1
$ErrorActionPreference = 'Stop'
$base = 'https://goride.website/wp-json'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) GoRideTest'

function Show-Err($e) {
    Write-Host "  ERROR: $($e.Exception.Message)" -ForegroundColor Red
    if ($e.ErrorDetails -and $e.ErrorDetails.Message) { Write-Host "  $($e.ErrorDetails.Message)" -ForegroundColor Red; return }
    try {
        $resp = $e.Exception.Response
        if ($resp) {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $text = $reader.ReadToEnd()
            if ($text) { Write-Host "  Respuesta del servidor: $text" -ForegroundColor Red }
        }
    } catch {}
}

$email = Read-Host 'Correo de la cuenta de pasajero'
$sec = Read-Host 'Contrasena' -AsSecureString
$pwd = [System.Net.NetworkCredential]::new('', $sec).Password
$body = @{ email = $email; password = $pwd } | ConvertTo-Json -Compress

Write-Host '1) Login...'
try {
    $r = Invoke-RestMethod -Method Post -Uri "$base/goride/v2/auth/login" -ContentType 'application/json' -Body $body -UserAgent $ua
} catch { Show-Err $_; $pwd = $null; $body = $null; return }
$pwd = $null; $body = $null
$token = [string]$r.data.access_token
if ([string]::IsNullOrWhiteSpace($token)) { Write-Host '  El servidor no devolvio token.' -ForegroundColor Red; return }
Write-Host '  OK: token recibido (no se muestra).' -ForegroundColor Green
$h = @{ Authorization = "Bearer $token" }

Write-Host '2) /config ...'
try {
    Invoke-RestMethod -Uri "$base/goride-rider/v1/config" -Headers $h -UserAgent $ua | ConvertTo-Json -Depth 6
} catch { Show-Err $_ }

Write-Host '3) /quotes (Newark -> New York, 1 pasajero) ...'
$b = @{ pickup = @{ lat = 40.7357; lng = -74.1724; address = 'Newark, NJ' }; dropoff = @{ lat = 40.7128; lng = -74.0060; address = 'New York, NY' }; passengers = 1 } | ConvertTo-Json -Depth 6 -Compress
try {
    Invoke-RestMethod -Method Post -Uri "$base/goride-rider/v1/quotes" -Headers $h -ContentType 'application/json' -Body $b -UserAgent $ua | ConvertTo-Json -Depth 6
} catch { Show-Err $_ }

Write-Host '4) /trips/active ...'
try {
    Invoke-RestMethod -Uri "$base/goride-rider/v1/trips/active" -Headers $h -UserAgent $ua | ConvertTo-Json -Depth 6
} catch { Show-Err $_ }
