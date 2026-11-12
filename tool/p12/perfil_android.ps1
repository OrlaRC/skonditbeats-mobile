# Práctica 12 · Fase 2: muestreo de CPU y memoria de la app en el celular (adb).
# Complementa a Flutter DevTools: deja un CSV por segundo para la tabla PER-01/PER-02.
#
# Uso (con la app ya abierta en el celular, de preferencia en modo profile):
#   flutter run --profile -d <id> --dart-define=API_URL=http://127.0.0.1:3000/api
#   powershell -ExecutionPolicy Bypass -File tool\p12\perfil_android.ps1 -Etiqueta antes -Segundos 120
# Mientras corre, haz las pruebas obligatorias: consultar la tienda varias veces,
# escribir (ticket o compra), navegar entre pestañas y subir un audio.
param(
  [string]$Etiqueta = 'prueba',
  [int]$Segundos = 120,
  [string]$Paquete = 'com.skonditbeats.skondit_beats_mobile',
  [string]$Adb = 'D:\AndroidSDK\platform-tools\adb.exe'
)
$ErrorActionPreference = 'Stop'
$salida = Join-Path $PSScriptRoot "resultados\perfil-$Etiqueta.csv"
New-Item -ItemType Directory -Force (Split-Path $salida) | Out-Null

$appPid = (& $Adb shell pidof $Paquete).Trim()
if (-not $appPid) { throw "La app no está corriendo en el celular ($Paquete)." }
$nucleos = [int](& $Adb shell nproc).Trim()

# CPU del proceso a partir de /proc (ticks de usuario + sistema entre dos lecturas).
function TicksApp { $c = (& $Adb shell cat /proc/$appPid/stat) -split ' '; [long]$c[13] + [long]$c[14] }
function TicksTotal { $c = ((& $Adb shell head -1 /proc/stat) -split '\s+')[1..7]; ($c | Measure-Object -Sum).Sum }

"segundo,cpu_pct,pss_mb,java_mb,native_mb,graficos_mb" | Out-File $salida -Encoding utf8
Write-Host "Midiendo PID $appPid durante $Segundos s ($nucleos núcleos) → $salida"

$a0 = TicksApp; $t0 = TicksTotal
for ($s = 1; $s -le $Segundos; $s++) {
  Start-Sleep -Seconds 1
  $a1 = TicksApp; $t1 = TicksTotal
  # Porcentaje de UN núcleo (como Android Studio): 100 % = un núcleo completo.
  $cpu = if ($t1 -gt $t0) { [math]::Round(100 * $nucleos * ($a1 - $a0) / ($t1 - $t0), 1) } else { 0 }
  $a0 = $a1; $t0 = $t1

  $mem = & $Adb shell dumpsys meminfo $Paquete
  $kb = { param($nombre) $l = $mem | Select-String -Pattern "^\s*$nombre" | Select-Object -First 1
          if ($l) { [double](($l.Line.Trim() -split '\s+') | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1) / 1024 } else { 0 } }
  # Formato invariante: punto decimal y sin separador de miles, para que el CSV no se rompa.
  $fila = [string]::Format([cultureinfo]::InvariantCulture, '{0},{1:F1},{2:F1},{3:F1},{4:F1},{5:F1}',
    $s, $cpu, (& $kb 'TOTAL PSS:'), (& $kb 'Java Heap:'), (& $kb 'Native Heap:'), (& $kb 'Graphics:'))
  $fila | Out-File $salida -Append -Encoding utf8
  Write-Host "  $fila"
}

$datos = Import-Csv $salida
$cpuS = $datos | ForEach-Object { [double]$_.cpu_pct } | Measure-Object -Average -Maximum
$ram = $datos | ForEach-Object { [double]$_.pss_mb }
Write-Host ''
Write-Host ('CPU promedio {0:N1} % · máximo {1:N1} %' -f $cpuS.Average, $cpuS.Maximum)
Write-Host ('RAM (PSS) inicial {0:N1} MB · máxima {1:N1} MB · final {2:N1} MB' -f $ram[0], ($ram | Measure-Object -Maximum).Maximum, $ram[-1])
