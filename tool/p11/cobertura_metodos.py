"""Práctica 11 · Cobertura de instrucciones y de ramas por método crítico.

Lee coverage/lcov.info (generado con `flutter test --coverage --branch-coverage`)
y, para cada método, cuenta las líneas ejecutables (DA) y las ramas (BRDA)
que caen dentro de su rango de líneas. El rango se localiza por la firma del
método, así sigue funcionando si el archivo cambia.

Uso:  python tool/p11/cobertura_metodos.py [coverage/lcov.info]
"""
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
METODOS = [
    # (id, archivo, regex de la firma)
    ('M1 Validators.cardExpiry', 'lib/core/utils/validators.dart', r'static String\? cardExpiry\('),
    ('M2 Validators.luhn', 'lib/core/utils/validators.dart', r'static bool luhn\('),
    ('M3 CartController.addPack', 'lib/features/cart/presentation/cart_controller.dart', r'Future<CartResult> addPack\('),
    ('M3b CartController.addBeat', 'lib/features/cart/presentation/cart_controller.dart', r'Future<CartResult> addBeat\('),
    ('M4 ApiException.fromDio', 'lib/core/network/api_client.dart', r'factory ApiException\.fromDio\('),
    ('M5 ReintentoInterceptor.onError', 'lib/core/network/api_client.dart', r'Future<void> onError\(DioException err, ErrorInterceptorHandler'),
    ('M5b ReintentoInterceptor.esTransitorio', 'lib/core/network/api_client.dart', r'static bool esTransitorio\('),
]


def rango(archivo: Path, firma: str) -> tuple[int, int]:
    """Línea de la firma y línea de la llave que cierra el método."""
    lineas = archivo.read_text(encoding='utf8').splitlines()
    ini = next(i for i, l in enumerate(lineas) if re.search(firma, l))
    nivel, abierto = 0, False
    for j in range(ini, len(lineas)):
        for ch in lineas[j]:
            if ch in '{(':
                nivel += 1
                abierto = True
            elif ch in '})':
                nivel -= 1
        if abierto and nivel <= 0 and (lineas[j].rstrip().endswith('}') or lineas[j].rstrip().endswith('};')):
            return ini + 1, j + 1
    return ini + 1, len(lineas)


def leer_lcov(ruta: Path):
    datos, actual = {}, None
    for l in ruta.read_text(encoding='utf8').splitlines():
        if l.startswith('SF:'):
            actual = l[3:].replace('\\', '/').split('skondit_beats_mobile/')[-1]
            datos[actual] = {'DA': {}, 'BRDA': []}
        elif l.startswith('DA:'):
            n, h = l[3:].split(',')[:2]
            datos[actual]['DA'][int(n)] = int(h)
        elif l.startswith('BRDA:'):
            n, bloque, rama, h = l[5:].split(',')
            datos[actual]['BRDA'].append((int(n), bloque, rama, 0 if h in ('-', '0') else int(h)))
    return datos


def main():
    lcov = Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / 'coverage/lcov.info'
    datos = leer_lcov(lcov)
    filas = []
    for ident, rel, firma in METODOS:
        a, b = rango(RAIZ / rel, firma)
        d = datos.get(rel, {'DA': {}, 'BRDA': []})
        lin = {n: h for n, h in d['DA'].items() if a <= n <= b}
        ramas = [r for r in d['BRDA'] if a <= r[0] <= b]
        sin = sorted(n for n, h in lin.items() if h == 0)
        ramas_sin = sorted({r[0] for r in ramas if r[3] == 0})
        filas.append({
            'metodo': ident, 'archivo': rel, 'lineas': f'{a}-{b}',
            'instr_cubiertas': sum(1 for h in lin.values() if h), 'instr_total': len(lin),
            'ramas_cubiertas': sum(1 for r in ramas if r[3]), 'ramas_total': len(ramas),
            'lineas_sin_cubrir': sin, 'lineas_con_rama_sin_cubrir': ramas_sin,
        })
    print(f"{'Método':40} {'Líneas':>9} {'Instrucciones':>15} {'Ramas':>13}  Sin cubrir")
    ti = tt = ri = rt = 0
    for f in filas:
        pi = 100 * f['instr_cubiertas'] / f['instr_total'] if f['instr_total'] else 100
        pr = 100 * f['ramas_cubiertas'] / f['ramas_total'] if f['ramas_total'] else 100
        ti += f['instr_cubiertas']; tt += f['instr_total']; ri += f['ramas_cubiertas']; rt += f['ramas_total']
        print(f"{f['metodo']:40} {f['lineas']:>9} {f['instr_cubiertas']:>4}/{f['instr_total']:<4}{pi:6.1f}% "
              f"{f['ramas_cubiertas']:>3}/{f['ramas_total']:<3}{pr:6.1f}%  {f['lineas_sin_cubrir'] or '-'}")
    print(f"{'TOTAL módulos críticos':40} {'':>9} {ti:>4}/{tt:<4}{100 * ti / tt:6.1f}% {ri:>3}/{rt:<3}{100 * ri / rt:6.1f}%")
    # Global
    gl = sum(1 for d in datos.values() for h in d['DA'].values() if h)
    gt = sum(len(d['DA']) for d in datos.values())
    gb = sum(1 for d in datos.values() for r in d['BRDA'] if r[3])
    gbt = sum(len(d['BRDA']) for d in datos.values())
    print(f"{'GLOBAL (todo lib/ con pruebas)':40} {'':>9} {gl:>4}/{gt:<4}{100 * gl / gt:6.1f}% {gb:>3}/{gbt:<3}{100 * gb / max(gbt, 1):6.1f}%")
    (RAIZ / 'docs/practica11/evidencias/cobertura_metodos.json').write_text(
        json.dumps(filas, ensure_ascii=False, indent=2), encoding='utf8')


if __name__ == '__main__':
    main()
