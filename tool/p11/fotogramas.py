"""Práctica 11 · WB-06 Rendimiento de la interfaz en el celular real.

Flutter dibuja en una SurfaceView; SurfaceFlinger guarda el momento en que cada
cuadro se presentó en pantalla (los últimos 128). El script hace scroll en la
pantalla abierta (la Tienda), lee esos tiempos y calcula FPS, percentiles del
tiempo entre cuadros y cuántos superan 16.7 ms (60 Hz) y 33.3 ms (jank visible).

Uso (con la Tienda abierta en el celular):
    python tool/p11/fotogramas.py [repeticiones]
"""
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

ADB = r'D:\AndroidSDK\platform-tools\adb.exe'
PAQUETE = 'com.skonditbeats.skondit_beats_mobile'
CAPA = f'SurfaceView - {PAQUETE}/{PAQUETE}.MainActivity#0'
RAIZ = Path(__file__).resolve().parents[2]


def adb(*args):
    return subprocess.run([ADB, *args], capture_output=True, text=True, timeout=60).stdout


def medir():
    adb('shell', f"dumpsys SurfaceFlinger --latency-clear '{CAPA}'")
    # Dos gestos de scroll rápidos hacia abajo y uno hacia arriba (fling).
    for x1, y1, x2, y2 in [(540, 1800, 540, 500), (540, 1800, 540, 500), (540, 600, 540, 1900)]:
        adb('shell', 'input', 'swipe', str(x1), str(y1), str(x2), str(y2), '180')
        time.sleep(0.35)
    time.sleep(0.6)
    lineas = adb('shell', f"dumpsys SurfaceFlinger --latency '{CAPA}'").split()
    periodo_ns = int(lineas[0])
    tiempos = [int(lineas[i + 1]) for i in range(1, len(lineas) - 2, 3)]
    presentados = sorted(t for t in tiempos if 0 < t < 2 ** 62)
    deltas = [(b - a) / 1e6 for a, b in zip(presentados, presentados[1:])]
    # Las pausas entre gestos (sin animación) no son cuadros lentos: se descartan.
    deltas = [d for d in deltas if d < 250]
    q = statistics.quantiles(deltas, n=100)
    return {
        'refresco_hz': round(1e9 / periodo_ns, 1),
        'cuadros': len(deltas) + 1,
        'fps_promedio': round(1000 / statistics.mean(deltas), 1),
        'ms_promedio': round(statistics.mean(deltas), 2),
        'ms_p50': round(q[49], 2), 'ms_p90': round(q[89], 2), 'ms_p99': round(q[98], 2),
        'ms_max': round(max(deltas), 2),
        'mas_de_16_7ms': sum(d > 16.7 * 1.2 for d in deltas),  # tolerancia de vsync
        'mas_de_33_3ms': sum(d > 33.3 for d in deltas),
    }


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    corridas = [medir() for _ in range(n)]
    modelo = adb('shell', 'getprop', 'ro.product.model').strip()
    android = adb('shell', 'getprop', 'ro.build.version.release').strip()
    res = {'dispositivo': f'{modelo} · Android {android}', 'compilacion': 'flutter build apk --profile', 'corridas': corridas}
    print(json.dumps(res, indent=2, ensure_ascii=False))
    (RAIZ / 'docs/practica11/evidencias/wb06_fotogramas.json').write_text(json.dumps(res, indent=2, ensure_ascii=False), encoding='utf8')


if __name__ == '__main__':
    main()
