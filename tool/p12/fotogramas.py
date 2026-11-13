"""Práctica 12 · Fase 2, prueba 6 (bloqueos de UI): fotogramas al hacer scroll en
la pantalla abierta (gestor de beats), con la medición de tool/p11/fotogramas.py.

Uso (con el gestor de beats abierto):  python tool/p12/fotogramas.py antes|despues [repeticiones]
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'p11'))
from fotogramas import medir  # noqa: E402

etiqueta = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 3
corridas = [medir() for _ in range(n)]
salida = Path(__file__).resolve().parent / 'resultados' / f'fotogramas-{etiqueta}.json'
salida.write_text(json.dumps({'etiqueta': etiqueta, 'pantalla': 'Gestor de beats', 'corridas': corridas}, indent=2, ensure_ascii=False), encoding='utf8')
print(json.dumps(corridas, indent=1, ensure_ascii=False))
