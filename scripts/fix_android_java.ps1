<#
 GoRide Rider - corrige SOLO la configuracion Java/Kotlin de android\app\build.gradle.kts
 sin regenerar android\ y sin tocar nada mas.

 Idea: en vez de adivinar versiones, toma de TU Flutter (flutter create en una carpeta temporal)
 los bloques compileOptions y kotlin que Flutter genera para tu version de Gradle/AGP/Kotlin,
 y los pone en tu build.gradle.kts. Se conservan namespace/applicationId com.goride.rider y compileSdk.

 Uso:
   powershell -ExecutionPolicy Bypass -File .\scripts\fix_android_java.ps1
 Antes de escribir hace una copia: android\app\build.gradle.kts.bak-FECHA
 Con -SoloDiagnostico solo muestra versiones y no cambia nada.
#>
param(
  [switch]$SoloDiagnostico,
  [int]$CompileSdk = 36
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$noBom = New-Object System.Text.UTF8Encoding($false)

function Get-Block {
  param([string]$Text, [string]$Header)
  $i = $Text.IndexOf($Header)
  if ($i -lt 0) { return $null }
  $open = $Text.IndexOf('{', $i)
  if ($open -lt 0) { return $null }
  $depth = 0
  for ($k = $open; $k -lt $Text.Length; $k++) {
    $c = [string]$Text[$k]
    if ($c -eq '{') { $depth++ }
    elseif ($c -eq '}') {
      $depth--
      if ($depth -eq 0) { return $Text.Substring($i, $k - $i + 1) }
    }
  }
  return $null
}

$appKts   = Join-Path $project 'android\app\build.gradle.kts'
$wrapper  = Join-Path $project 'android\gradle\wrapper\gradle-wrapper.properties'
$settings = Join-Path $project 'android\settings.gradle.kts'
if (-not (Test-Path $appKts)) { throw 'No existe android\app\build.gradle.kts. Esta correccion es para el proyecto con android ya creado.' }

Write-Host '=== DIAGNOSTICO (solo lectura) ===' -ForegroundColor Cyan
Write-Host ('JAVA_HOME de esta ventana: ' + $env:JAVA_HOME)
if (Test-Path $wrapper) { Select-String -Path $wrapper -Pattern 'distributionUrl' | ForEach-Object { Write-Host ('Gradle: ' + $_.Line) } }
if (Test-Path $settings) { Select-String -Path $settings -Pattern 'com.android.application|org.jetbrains.kotlin.android' | ForEach-Object { Write-Host ('Plugin: ' + $_.Line.Trim()) } }
Write-Host '--- build.gradle.kts actual (lineas Java/Kotlin) ---'
Select-String -Path $appKts -Pattern 'JavaVersion|jvmToolchain|jvmTarget|kotlin|compileSdk|namespace|applicationId' | ForEach-Object { Write-Host ('  ' + $_.Line.Trim()) }
if ($SoloDiagnostico) { return }

$work = Join-Path $env:TEMP ('goride_rider_javafix_' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  $scaffold = Join-Path $work 'scaffold'
  Write-Host 'Leyendo la plantilla que Flutter genera para tu version...'
  flutter create --org com.goride --project-name goride_rider_app --platforms android --empty $scaffold | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'flutter create fallo.' }
  $tplPath = Join-Path $scaffold 'android\app\build.gradle.kts'
  if (-not (Test-Path $tplPath)) { throw 'La plantilla de Flutter no tiene build.gradle.kts.' }
  $tpl = [System.IO.File]::ReadAllText($tplPath)

  $tCompile = Get-Block -Text $tpl -Header 'compileOptions {'
  $tKotlin  = Get-Block -Text $tpl -Header "`nkotlin {"
  $tKOpts   = Get-Block -Text $tpl -Header 'kotlinOptions {'
  if (-not $tCompile) { throw 'No encontre compileOptions en la plantilla de Flutter. No se cambio nada.' }
  if ($tKotlin) { $tKotlin = $tKotlin.TrimStart("`r", "`n") }

  $cur = [System.IO.File]::ReadAllText($appKts)
  $cCompile = Get-Block -Text $cur -Header 'compileOptions {'
  $cKotlin  = Get-Block -Text $cur -Header "`nkotlin {"
  $cKOpts   = Get-Block -Text $cur -Header 'kotlinOptions {'
  if (-not $cCompile) { throw 'No encontre compileOptions en tu build.gradle.kts. No se cambio nada.' }
  if ($cKotlin) { $cKotlin = $cKotlin.TrimStart("`r", "`n") }

  $new = $cur
  $replacement = $tCompile
  if ($tKOpts -and -not $tKotlin) { $replacement = $tCompile + "`r`n`r`n    " + $tKOpts }
  $new = $new.Replace($cCompile, $replacement)
  if ($cKOpts) { $new = $new.Replace($cKOpts, '') }
  if ($cKotlin) {
    if ($tKotlin) { $new = $new.Replace($cKotlin, $tKotlin) } else { $new = $new.Replace($cKotlin, '') }
  } elseif ($tKotlin) {
    $fl = $new.IndexOf('flutter {')
    if ($fl -lt 0) { throw 'No encontre el bloque flutter { } en tu build.gradle.kts.' }
    $new = $new.Insert($fl, $tKotlin + "`r`n`r`n")
  }
  $new = [regex]::Replace($new, '(\r?\n){3,}', "`r`n`r`n")

  # Validacion antes de escribir
  if ($new -notmatch 'namespace\s*=\s*"com\.goride\.rider"') { throw 'Validacion: falta namespace com.goride.rider.' }
  if ($new -notmatch 'applicationId\s*=\s*"com\.goride\.rider"') { throw 'Validacion: falta applicationId com.goride.rider.' }
  if ($new -notmatch ('compileSdk\s*=\s*' + $CompileSdk)) { throw "Validacion: falta compileSdk = $CompileSdk." }
  if ($new -notmatch 'dev\.flutter\.flutter-gradle-plugin') { throw 'Validacion: falta el plugin de Flutter.' }
  if ($new -match 'VERSION_25|jvmToolchain\(25\)') { if (-not ($tpl -match 'VERSION_25|jvmToolchain\(25\)')) { throw 'Validacion: sigue habiendo Java 25 que tu plantilla de Flutter no usa.' } }

  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bak = $appKts + '.bak-' + $stamp
  Copy-Item $appKts $bak
  [System.IO.File]::WriteAllText($appKts, $new, $noBom)
  Write-Host ''
  Write-Host ('Listo. Copia de seguridad: ' + $bak) -ForegroundColor Green
  Write-Host '--- build.gradle.kts nuevo (lineas Java/Kotlin) ---'
  Select-String -Path $appKts -Pattern 'JavaVersion|jvmToolchain|jvmTarget|kotlin|compileSdk|namespace|applicationId' | ForEach-Object { Write-Host ('  ' + $_.Line.Trim()) }
}
catch {
  Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
  Write-Host 'No se modifico build.gradle.kts.' -ForegroundColor Yellow
  exit 1
}
finally {
  if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}
