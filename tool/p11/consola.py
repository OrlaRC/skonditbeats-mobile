"""Práctica 11 · Capturas de consola para el informe.

Toma fragmentos LITERALES de las salidas guardadas en docs/practica11/evidencias
(no se escribe texto a mano) y los dibuja como una ventana de terminal con Chrome
headless, para insertarlos en el Word.

Uso:  python tool/p11/consola.py <carpeta_capturas>
"""
import html
import re
import subprocess
import sys
from pathlib import Path

CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
RAIZ = Path(__file__).resolve().parents[2]
EV = RAIZ / 'docs/practica11/evidencias'


def leer(nombre):
    return (EV / nombre).read_text(encoding='utf-8-sig', errors='replace')


def app_antes():
    t = leer('01_whitebox_app_ANTES.txt')
    fallas = []
    for l in t.splitlines():
        if l.rstrip().endswith('[E]'):
            l = re.sub(r'^.*?test/whitebox/', 'test/whitebox/', l.strip())
            if l not in fallas:
                fallas.append(l)
    final = [l for l in t.splitlines() if 'Some tests failed' in l][-1].strip()
    return ['$ flutter test test/whitebox --concurrency=1   # código ORIGINAL (b4a690d)', *fallas, final]


def api_antes():
    t = leer('04_whitebox_api_ANTES.txt')
    lineas = [l.rstrip() for l in t.splitlines() if re.match(r'^\s+not ok|^# (tests|pass|fail)', l)]
    return ['$ node --import tsx --test scripts/p11/whitebox.test.ts   # src/ ORIGINAL (74ab19d)', *lineas]


def cobertura():
    t = leer('02_flutter_test_DESPUES.txt').splitlines()
    fin = [l for l in t if 'All tests passed' in l][-1].strip()
    cov = [l.rstrip() for l in leer('03_cobertura_metodos.txt').splitlines() if l.strip()]
    return ['$ flutter test --coverage --branch-coverage', fin, '', '$ python tool/p11/cobertura_metodos.py coverage/lcov.info', *cov]


def concurrencia():
    t = leer('db.md').splitlines()
    i = t.index('## Concurrencia')
    filas = [l for l in t[i:] if l.startswith('| DB-06')]
    salida = ['$ node scripts/p11/db-whitebox.mjs   (sección de concurrencia, 2 sesiones psql simultáneas)', '']
    for f in filas:
        c = [x.strip() for x in f.strip('|').split('|')]
        salida += [f'{c[0]}  {c[1]}', f'        esperado = {c[2]}   obtenido = {c[3]}   {c[5]}', f'        {c[4]}', '']
    return salida


CAPTURAS = {
    'C1_app_pruebas_antes': ('Pruebas de caja blanca de la app sobre el código original', app_antes),
    'C2_api_pruebas_antes': ('Pruebas de caja blanca de la API sobre el código original', api_antes),
    'C3_cobertura_metodos': ('Cobertura de instrucciones y ramas por método crítico', cobertura),
    'C4_concurrencia_bd': ('Concurrencia real en PostgreSQL 16', concurrencia),
}


def pintar(lineas):
    out = []
    for l in lineas:
        e = html.escape(l)
        if l.startswith('$'):
            e = f'<span class="cmd">{e}</span>'
        elif re.search(r'\[E\]|not ok|failed|❌|fail [1-9]', l):
            e = f'<span class="err">{e}</span>'
        elif re.search(r'All tests passed|100\.0%|✅|# pass', l):
            e = f'<span class="ok">{e}</span>'
        out.append(e)
    return '\n'.join(out)


def main():
    salida = Path(sys.argv[1]).resolve()
    salida.mkdir(parents=True, exist_ok=True)
    for nombre, (titulo, fuente) in CAPTURAS.items():
        lineas = fuente()
        ancho = min(1500, max(760, 30 + 7.9 * max(len(l) for l in lineas)))
        alto = 70 + 19 * len(lineas)
        doc = f'''<!doctype html><meta charset="utf-8"><style>
body{{margin:0;background:#fff}}
.v{{margin:10px;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px #0004;background:#0C0C0C}}
.b{{background:#2B2B2B;color:#DDD;font:12px Segoe UI,Arial;padding:7px 12px}}
.b i{{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;background:#FF5F57}}
.b i+i{{background:#FEBC2E}} .b i+i+i{{background:#28C840;margin-right:14px}}
pre{{margin:0;padding:10px 14px 12px;color:#CCCCCC;font:13px/19px Consolas,monospace;white-space:pre}}
.cmd{{color:#61D6D6}} .err{{color:#F14C4C}} .ok{{color:#23D18B}}
</style><div class="v"><div class="b"><i></i><i></i><i></i>{html.escape(titulo)}</div><pre>{pintar(lineas)}</pre></div>'''
        h = salida / f'{nombre}.html'
        h.write_text(doc, encoding='utf8')
        png = salida / f'{nombre}.png'
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2',
                        f'--screenshot={png}', f'--window-size={int(ancho)},{int(alto)}', h.as_uri()], check=True, capture_output=True)
        h.unlink()
        print(png)


if __name__ == '__main__':
    main()
