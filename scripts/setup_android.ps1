<#
 GoRide Rider - prepara la carpeta android/ (una sola vez).
 Uso (PowerShell):
   powershell -ExecutionPolicy Bypass -File .\scripts\setup_android.ps1 -MapsApiKey "TU_LLAVE"
 - Todo se prepara y se valida en una carpeta TEMPORAL. Solo si termina bien se copia android/ al proyecto.
   Si algo falla, el proyecto queda intacto y puedes volver a ejecutar el script.
 - NO toca lib/, test/ ni pubspec.yaml. NO toca ningun otro proyecto.
 - Si android/ ya existe, se detiene sin sobrescribir.
#>
param(
  [string]$MapsApiKey = '',
  [int]$JavaVersion = 0,
  [int]$CompileSdk = 36
)

$ErrorActionPreference = 'Stop'
if ($JavaVersion -ne 0) { Write-Warning '-JavaVersion ya no se usa: se conserva la configuracion Java que genera tu Flutter.' }
$project = Split-Path -Parent $PSScriptRoot
$noBom = New-Object System.Text.UTF8Encoding($false)

function Write-NoBom {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  [System.IO.File]::WriteAllText($Path, $Text, $noBom)
}

if (-not (Test-Path (Join-Path $project 'pubspec.yaml'))) { throw 'No encuentro pubspec.yaml. Ejecuta el script dentro de goride_rider_app.' }
if (Test-Path (Join-Path $project 'android')) { throw 'La carpeta android ya existe. Si quieres rehacerla, renombrala y vuelve a ejecutar.' }
if (-not (Select-String -Path (Join-Path $project 'pubspec.yaml') -Pattern '^name:\s*goride_rider_app\s*$' -Quiet)) { throw 'pubspec.yaml no es el de goride_rider_app.' }

$work = Join-Path $env:TEMP ('goride_rider_setup_' + [guid]::NewGuid().ToString('N'))
$scaffold = Join-Path $work 'scaffold'
$ok = $false

try {
  New-Item -ItemType Directory -Force -Path $work | Out-Null

  # 1) Esqueleto Android con tu Flutter, en la carpeta temporal
  Write-Host 'Generando esqueleto Android con tu Flutter...'
  flutter create --org com.goride --project-name goride_rider_app --platforms android --empty $scaffold
  if ($LASTEXITCODE -ne 0) { throw 'flutter create fallo.' }
  $android = Join-Path $scaffold 'android'
  if (-not (Test-Path $android)) { throw 'flutter create no genero la carpeta android.' }

  # 2) build.gradle.kts de la app
  $appKts = Join-Path $android 'app\build.gradle.kts'
  if (-not (Test-Path $appKts)) { throw 'Tu Flutter genero build.gradle (Groovy) y no .kts. Avisame y lo adapto.' }
  # Se conserva la configuracion Java/Kotlin que tu Flutter genera (compatible con su Gradle/AGP/Kotlin)
  # y solo se cambian namespace, applicationId y compileSdk.
  $kts = [System.IO.File]::ReadAllText($appKts)
  $kts = [regex]::Replace($kts, 'namespace\s*=\s*"[^"]*"', 'namespace = "com.goride.rider"')
  $kts = [regex]::Replace($kts, 'applicationId\s*=\s*"[^"]*"', 'applicationId = "com.goride.rider"')
  $kts = [regex]::Replace($kts, 'compileSdk\s*=\s*[^\r\n]+', "compileSdk = $CompileSdk")
  Write-NoBom -Path $appKts -Text $kts

  # 3) build.gradle.kts raiz
  $rootSrc = Join-Path $project 'scripts\root_build.gradle.kts'
  if (-not (Test-Path $rootSrc)) { throw 'Falta scripts\root_build.gradle.kts.' }
  Copy-Item $rootSrc (Join-Path $android 'build.gradle.kts') -Force

  # 4) MainActivity en com.goride.rider
  $kotlinRoot = Join-Path $android 'app\src\main\kotlin'
  if (Test-Path $kotlinRoot) { Remove-Item $kotlinRoot -Recurse -Force }
  $actDir = Join-Path $kotlinRoot 'com\goride\rider'
  New-Item -ItemType Directory -Force -Path $actDir | Out-Null
  $act = "package com.goride.rider`r`n`r`nimport io.flutter.embedding.android.FlutterActivity`r`n`r`nclass MainActivity : FlutterActivity()`r`n"
  Write-NoBom -Path (Join-Path $actDir 'MainActivity.kt') -Text $act

  # 5) AndroidManifest: nombre, permisos, llave de Maps
  $manifestPath = Join-Path $android 'app\src\main\AndroidManifest.xml'
  if (-not (Test-Path $manifestPath)) { throw 'No encuentro AndroidManifest.xml.' }
  $m = [System.IO.File]::ReadAllText($manifestPath)
  $m = [regex]::Replace($m, 'android:label="[^"]*"', 'android:label="GoRide"', 1)

  if ($m -notmatch 'android.permission.INTERNET') {
    $perms = '<uses-permission android:name="android.permission.INTERNET"/>' + "`r`n" +
             '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>' + "`r`n" +
             '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>' + "`r`n" + '    '
    $idx = $m.IndexOf('<application')
    if ($idx -lt 0) { throw 'No encuentro <application> en el manifiesto.' }
    $m = $m.Insert($idx, $perms)
  }

  $key = $MapsApiKey
  if ([string]::IsNullOrWhiteSpace($key)) {
    $key = 'PON_AQUI_TU_LLAVE_DE_MAPS'
    Write-Warning 'No diste -MapsApiKey: el mapa saldra gris hasta que edites AndroidManifest.xml.'
  }
  if ($m -notmatch 'com.google.android.geo.API_KEY') {
    $meta = '    <meta-data android:name="com.google.android.geo.API_KEY" android:value="' + $key + '"/>' + "`r`n    "
    $end = $m.LastIndexOf('</application>')
    if ($end -lt 0) { throw 'No encuentro </application> en el manifiesto.' }
    $m = $m.Insert($end, $meta)
  }
  Write-NoBom -Path $manifestPath -Text $m

  # 6) Validacion antes de copiar
  $final = [System.IO.File]::ReadAllText($manifestPath)
  foreach ($needle in @('android:label="GoRide"', 'android.permission.INTERNET', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION', 'com.google.android.geo.API_KEY', $key)) {
    if (-not $final.Contains($needle)) { throw "Validacion fallida: el manifiesto no contiene '$needle'." }
  }
  $ktsFinal = [System.IO.File]::ReadAllText($appKts)
  if (($ktsFinal -notmatch 'applicationId = "com.goride.rider"') -or ($ktsFinal -notmatch 'namespace = "com.goride.rider"') -or ($ktsFinal -notmatch "compileSdk = $CompileSdk")) { throw 'Validacion fallida: build.gradle.kts sin com.goride.rider.' }
  if (-not (Test-Path (Join-Path $actDir 'MainActivity.kt'))) { throw 'Validacion fallida: falta MainActivity.kt.' }

  # 7) Todo bien: recien ahora se copia android/ al proyecto
  Copy-Item $android -Destination (Join-Path $project 'android') -Recurse
  $ok = $true
}
catch {
  Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
  Write-Host 'No se creo ni se modifico nada en el proyecto. Puedes volver a ejecutar el script.' -ForegroundColor Yellow
}
finally {
  if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($ok) {
  Write-Host ''
  Write-Host 'Listo. Siguiente:' -ForegroundColor Green
  Write-Host '  flutter pub get'
  Write-Host '  flutter analyze'
  Write-Host '  flutter test'
} else {
  exit 1
}
