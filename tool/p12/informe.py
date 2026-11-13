"""Práctica 12 · Genera el informe Word (mismo formato que la Práctica 11).

Reutiliza la plantilla y las funciones de tool/p11/informe.py (estilos, tablas,
galerías) y lee todas las métricas de los resultados medidos:
  - api/scripts/p12/resultados/db.json, carga-antes.json, carga-despues.json
  - tool/p12/resultados/perfil-antes.csv, perfil-despues.csv
  - PRACTICA 12 - DMI/evidencias_texto/*.txt (logs del celular y pruebas)

Uso:  python tool/p12/informe.py
"""
import csv
import json
import re
from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]
API_RES = Path(r'D:\Angular\erp_beats\api\scripts\p12\resultados')
PERFIL = RAIZ / 'tool/p12/resultados'
PRACTICA = Path(r'D:\Flutter\PRACTICA 12 - DMI')
CAP = PRACTICA / 'capturas'
EVT = PRACTICA / 'evidencias_texto'
PLANTILLA = Path(r'D:\Flutter\PRACTICA 8 - DMI\Practica 8 - Pruebas de caja negra - Orlando Rubio Cabrera.docx')
SALIDA = PRACTICA / 'Practica 12 - Optimizacion, estres y resiliencia - Orlando Rubio Cabrera.docx'

AZUL = RGBColor(0x1F, 0x3A, 0x5F)
ROJO = RGBColor(0xA6, 0x1B, 0x1B)
VERDE = RGBColor(0x2F, 0x7D, 0x4A)
GRIS = RGBColor(0x59, 0x59, 0x59)
ANCHO = 9360

# Funciones de formato del informe de la Práctica 11 (doc, par, h1, tabla, galeria, ...).
_src = (RAIZ / 'tool/p11/informe.py').read_text(encoding='utf-8')
_bloque = _src.split('# ── Documento a partir de la plantilla')[1].split('# Atajos a los datos medidos')[0]
exec(_bloque.split('\n', 1)[1])  # sin el resto de la línea del título


def jl(ruta):
    return json.loads(Path(ruta).read_text(encoding='utf-8-sig'))


BD = jl(API_RES / 'db.json')
C_ANTES = jl(API_RES / 'carga-antes.json')
C_DESP = jl(API_RES / 'carga-despues.json')


def perfil(etq):
    with open(PERFIL / f'perfil-{etq}.csv', encoding='utf-8-sig') as f:
        filas = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]
    cpu = [r['cpu_pct'] for r in filas[1:]]  # el primer segundo no tiene lectura previa
    col = lambda k: [r[k] for r in filas]
    return {
        'n': len(filas), 'cpu_prom': sum(cpu) / len(cpu), 'cpu_max': max(cpu),
        'pss_ini': filas[0]['pss_mb'], 'pss_max': max(col('pss_mb')), 'pss_prom': sum(col('pss_mb')) / len(filas),
        'pss_fin': filas[-1]['pss_mb'], 'java_max': max(col('java_mb')), 'native_max': max(col('native_mb')),
        'graf_max': max(col('graficos_mb')),
    }


def log_beats(nombre):
    ms, kb = [], []
    for l in (EVT / nombre).read_text(encoding='utf-8').splitlines():
        m = re.search(r'GET /beats 200 · (\d+) ms · ([\d.]+) KB', l)
        if m:
            ms.append(int(m.group(1)))
            kb.append(float(m.group(2)))
    return {'n': len(ms), 'prom': sum(ms) / len(ms), 'min': min(ms), 'max': max(ms), 'kb': kb[0]}


def prueba(nombre, patron):
    t = (EVT / nombre).read_text(encoding='utf-8', errors='replace')
    return re.findall(patron, t)[-1]


P_A, P_D = perfil('antes'), perfil('despues')
L_A, L_D = log_beats('log-antes.txt'), log_beats('log-despues.txt')
N_FLUTTER = prueba('flutter_test.txt', r'\+(\d+): All tests passed')
N_API = prueba('api_test.txt', r'# pass (\d+)')
N_API_FAIL = prueba('api_test.txt', r'# fail (\d+)')


def fila_carga(f):
    return [f['usuarios'], f['solicitudes'], f"{f['rps']:.0f}", f"{f['promedio']:.1f}", f"{f['p50']:.1f}",
            f"{f['p90']:.1f}", f"{f['p95']:.1f}", f"{f['max']:.1f}", f"{f['errorPct']:.2f}",
            ', '.join(f'{k}×{v}' for k, v in f['codigos'].items()), f"{f['kbPorRespuesta']:.1f}", f"{f['healthMaxMs']:.0f}"]


ENC_CARGA = ['Usuarios', 'Solic.', 'RPS', 'Prom. ms', 'P50', 'P90', 'P95', 'Máx. ms', 'Err. %', 'Códigos', 'KB/resp.', '/health máx.']
ANCH_CARGA = [0.8, 0.8, 0.6, 0.8, 0.7, 0.7, 0.7, 0.8, 0.6, 1.2, 0.7, 0.8]


def saturacion(filas):
    mejor = max(filas, key=lambda f: f['rps'])
    return mejor


def escalon(datos, tipo, usuarios):
    return next(f for f in datos[tipo]['filas'] if f['usuarios'] == usuarios)


def dif(a, b, menor_es_mejor=True):
    if a == 0:
        return '—'
    d = 100 * (b - a) / a
    return f'{d:+.1f} %'.replace('.', '.')


A200, D200 = escalon(C_ANTES, 'lectura', 200), escalon(C_DESP, 'lectura', 200)
A1, D1 = escalon(C_ANTES, 'lectura', 1), escalon(C_DESP, 'lectura', 1)
SAT_A, SAT_D, SAT_W = saturacion(C_ANTES['lectura']['filas']), saturacion(C_DESP['lectura']['filas']), saturacion(C_DESP['escritura']['filas'])
ERR_A = 100 * sum(f['errores'] for f in C_ANTES['lectura']['filas']) / sum(f['solicitudes'] for f in C_ANTES['lectura']['filas'])
ERR_D = 100 * sum(f['errores'] for f in C_DESP['lectura']['filas']) / sum(f['solicitudes'] for f in C_DESP['lectura']['filas'])
Q_A, Q_D, CON = BD['antes'], BD['despues'], BD['concurrencia']

# ═════════════════════════════════════════════════════════════════════════════
# Portada
# ═════════════════════════════════════════════════════════════════════════════
for _ in range(4):
    doc.add_paragraph()
par('Desarrollo Móvil Integral', tam=16, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
par('Práctica 12', tam=26, negrita=True, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
par('Optimización, pruebas de estrés y resiliencia', tam=16, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
par('Aplicación evaluada: SkonditBeats Mobile (Flutter + API Fastify + PostgreSQL/Supabase)', tam=12, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_paragraph()
for linea in ('Alumno: Orlando Rubio Cabrera', 'Docente: MANUEL CONTRERAS CASTILLO', 'Grupo: IDGS16', 'Fecha: 12 de noviembre de 2026'):
    par(linea, tam=12, alin=WD_ALIGN_PARAGRAPH.CENTER)
salto()
par('Índice', tam=16, negrita=True, color=AZUL)
campo_toc()
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('1. Introducción')
par('SkonditBeats Mobile es la app (Flutter) de la tienda de beats SkonditBeats: catálogo con reproducción, carrito, pago '
    'simulado, tickets de soporte y un panel de administración con gestor de beats, usuarios y mesa de ayuda. Consume una API '
    'REST (Fastify + TypeScript) que guarda en PostgreSQL (Supabase en producción).')
par('En esta práctica se buscaron los puntos lentos y frágiles del sistema completo, se midieron con herramientas '
    'reproducibles, se aplicaron optimizaciones reales y se volvió a medir en las mismas condiciones para comparar. También se '
    'sometió la API a carga creciente, se probó la concurrencia en la base de datos y se verificó cómo responde la app ante '
    'cortes de red, servidores caídos, errores HTTP y reintentos.')
h2('Objetivo')
par('Identificar cuellos de botella de rendimiento en la app, la API y la base de datos; demostrar con mediciones antes y '
    'después que las optimizaciones los resuelven; y comprobar que la aplicación se mantiene estable, sin duplicar datos, '
    'bajo carga, concurrencia y fallas de conectividad.')
h2('Entorno de prueba')
tabla(['Elemento', 'Detalle'], [
    ['Dispositivo', 'Huawei FRL-L23 · Android 10 · 1080 × 2400 · conectado por USB (`adb reverse tcp:3000`)'],
    ['Compilación de la app', '`flutter build apk --profile --dart-define=API_URL=http://127.0.0.1:3000/api`'],
    ['API', 'Fastify + TypeScript (Node 20) en la PC, puerto 3000; ruta original de beats en el 3001 para medir el "antes"'],
    ['Base de datos', f"{BD['version']} + PostgREST (el mismo motor que expone Supabase en /rest/v1), base `skondit_local`"],
    ['Datos de prueba', '5 000 beats, 2 003 usuarios, 20 000 órdenes, 40 001 renglones, 12 000 tickets y 30 000 respuestas'],
    ['Herramientas', '`carga.mjs` (estrés), `db-bench.mjs` + EXPLAIN ANALYZE + pgbench (BD), `perfil_android.ps1` (CPU/RAM por adb), '
                     'registro `[p12]` de cada petición en logcat, `flutter test`, `node --test`'],
], [1.6, 4.8])
par('**¿Por qué un entorno local y no Supabase?** Con una base remota la latencia del Wi-Fi (150–400 ms, variable) se mezcla '
    'con la del código y cada corrida ensucia la base real. Con el mismo motor en la PC y el celular por cable, las mediciones '
    'son repetibles; solo cambia `SUPABASE_URL`, el código de la API es el mismo.')
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('2. Fase 1 · Problemas detectados e hipótesis')
tabla(['#', 'Problema', 'Dónde', 'Hipótesis técnica'], [
    ['1', 'Método costoso', '`GET /api/contact` (bandeja de tickets)',
     'Devuelve todos los tickets con el texto de todas sus respuestas (11.7 MB con 12 000 tickets): tiempo y tamaño crecen con el historial.'],
    ['2', 'Endpoint con latencia', '`GET /api/beats`',
     'Hace 3 consultas por petición (lista, conteo y géneros) y regresa el catálogo completo (1.3 MB) aunque la pantalla muestra 8–20 beats.'],
    ['3', 'Consulta optimizable', '`beats where activo order by created_at desc`',
     'Sin índice que cubra filtro + orden: recorrido secuencial y ordenamiento en memoria en cada petición.'],
    ['4', 'Conectividad', 'Toda la app',
     'Sin reintentos ni detección de red; repetir una escritura tras un corte podía duplicar un pago o un ticket; una subida cortada empezaba de cero.'],
    ['5', 'Memoria / CPU', 'Tienda, gestor e inicio',
     'Decodificar 1.3 MB de JSON y construir 4 800 objetos `Beat` en cada carga; el inicio pedía el catálogo entero para 8 tarjetas.'],
], [0.3, 1.1, 1.6, 3.4])

# ═════════════════════════════════════════════════════════════════════════════
h1('3. Fase 2 · Profiling de la app en el celular')
par('La app se compiló en modo **profile** (el que usa DevTools para medir, con el rendimiento de release) y se instaló en el '
    'celular. `tool/p12/perfil_android.ps1` muestreó cada segundo el CPU del proceso (desde `/proc`) y su memoria '
    '(`dumpsys meminfo`: PSS total, Java, Native y Gráficos) a un CSV. Cada petición quedó registrada en logcat como '
    '`[p12] GET /beats 200 · 44 ms · 5.5 KB · intento 1`.')
par('Para que la comparación sea justa se hizo **exactamente el mismo recorrido** automatizado con `adb` (4 veces: abrir el '
    'gestor de beats, 5 desplazamientos hasta abajo, regresar) durante 60 s, con la misma APK. Para el "antes" el puerto del '
    'celular se redirigió a la API con la ruta original (sin paginación); para el "después", a la API optimizada.')
h2('Pruebas obligatorias')
tabla(['Prueba', 'Cómo se hizo en la app', 'Resultado'], [
    ['Consulta repetida', 'Abrir el gestor de beats 4 veces y jalar para actualizar', f'{L_D["n"]} consultas registradas, {L_D["min"]}–{L_D["max"]} ms cada una'],
    ['Escritura', 'Prueba de estrés `POST /api/contact` (abrir ticket con `Idempotency-Key`)', f"{sum(f['solicitudes'] for f in C_DESP['escritura']['filas']):,} tickets, 0 % de errores".replace(',', ' ')],
    ['Navegación', 'Panel ↔ Gestor de beats ↔ Mesa de ayuda ↔ Mi perfil (3 vueltas)', 'Sin bloqueos ni errores'],
    ['Procesamiento de datos', 'Scroll hasta abajo en el gestor (paginación de 20 en 20) y en la mesa de ayuda (30 000+ tickets)', 'Las páginas se agregan al llegar al final'],
    ['CPU y memoria', 'CSV de `perfil_android.ps1` (60 muestras por escenario)', 'Tabla siguiente'],
    ['Bloqueos de UI', 'Registro de tiempos del recorrido y DevTools (Performance)', 'Sin congelamientos visibles; picos de CPU solo al construir la lista'],
], [1.3, 3.0, 2.1])
h2('CPU, memoria y operación crítica (mismo recorrido)')
tabla(['Métrica', 'Antes', 'Después', 'Diferencia'], [
    ['Tiempo de la operación crítica (`GET /beats` visto desde la app, ms)', f"{L_A['prom']:.0f} ({L_A['min']}–{L_A['max']})", f"{L_D['prom']:.0f} ({L_D['min']}–{L_D['max']})", dif(L_A['prom'], L_D['prom'])],
    ['Datos descargados por consulta (KB)', f"{L_A['kb']:.1f}", f"{L_D['kb']:.1f}", dif(L_A['kb'], L_D['kb'])],
    ['CPU promedio del proceso (% de un núcleo)', f"{P_A['cpu_prom']:.1f}", f"{P_D['cpu_prom']:.1f}", dif(P_A['cpu_prom'], P_D['cpu_prom'])],
    ['CPU máximo (%)', f"{P_A['cpu_max']:.1f}", f"{P_D['cpu_max']:.1f}", dif(P_A['cpu_max'], P_D['cpu_max'])],
    ['RAM máxima, PSS (MB)', f"{P_A['pss_max']:.1f}", f"{P_D['pss_max']:.1f}", dif(P_A['pss_max'], P_D['pss_max'])],
    ['RAM promedio, PSS (MB)', f"{P_A['pss_prom']:.1f}", f"{P_D['pss_prom']:.1f}", dif(P_A['pss_prom'], P_D['pss_prom'])],
    ['Native heap máximo (MB)', f"{P_A['native_max']:.1f}", f"{P_D['native_max']:.1f}", dif(P_A['native_max'], P_D['native_max'])],
    ['Java heap máximo (MB)', f"{P_A['java_max']:.1f}", f"{P_D['java_max']:.1f}", dif(P_A['java_max'], P_D['java_max'])],
], [3.2, 1.1, 1.1, 1.0], centrar=(1, 2, 3))
par(f"**Análisis.** La mejora más grande en el teléfono es la **operación crítica**: cargar el catálogo pasó de "
    f"{L_A['prom']:.0f} ms a {L_D['prom']:.0f} ms y de {L_A['kb']:.0f} KB a {L_D['kb']:.1f} KB por consulta, lo que en datos "
    f"móviles es la diferencia entre esperar y no esperar. El CPU y la RAM cambian poco "
    f"({P_A['cpu_prom']:.1f} → {P_D['cpu_prom']:.1f} % y {P_A['pss_max']:.0f} → {P_D['pss_max']:.0f} MB) porque Flutter solo "
    'construye los renglones visibles de la lista (`ListView` perezoso): aunque antes llegaban 4 800 beats, nunca se dibujaban '
    'todos. Lo que sí se ahorra es decodificar 1.3 MB de JSON y crear 4 800 objetos en cada visita, trabajo que antes se repetía '
    'en cada consulta. Es decir, el cuello de botella no estaba en el teléfono sino en cuánto dato pedía cada pantalla.')
galeria([
    (CAP / 'antes-catalogo.png', 'Antes: gestor de beats (1 314 KB por consulta)'),
    (CAP / 'antes-catalogo-scroll.png', 'Antes: los 4 800 beats llegan de una vez'),
    (CAP / 'despues-catalogo.png', 'Después: primera página (5.5 KB)'),
], ancho=1.9)
galeria([
    (CAP / 'despues-catalogo-scroll.png', 'Después: scroll infinito, páginas de 20'),
    (CAP / 'despues-03-mesa-ayuda.png', 'Mesa de ayuda paginada con 30 000+ tickets'),
    (CAP / 'despues-05-panel.png', 'Panel de administración (navegación)'),
], ancho=1.9)
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('4. Fase 3 · Prueba de estrés de la API')
par('Script reproducible `scripts/p12/carga.mjs` (sin dependencias): sube la carga por escalones de 1, 10, 25, 50, 100 y 200 '
    f"usuarios concurrentes, {C_DESP['segundosPorEscalon']} s por escalón, y mide RPS, latencia promedio, P50, P90, P95, máximo, "
    'errores, códigos HTTP, tamaño de respuesta y la latencia de `/health` durante la carga (si el servidor sigue atendiendo).')
codigo(['node scripts/p12/carga.mjs --etiqueta antes --base http://127.0.0.1:3001 --lectura /api/beats --escritura no',
        'node scripts/p12/carga.mjs --etiqueta despues'])
h2('Antes · lectura GET /api/beats (ruta original, catálogo completo)')
tabla(ENC_CARGA, [fila_carga(f) for f in C_ANTES['lectura']['filas']], ANCH_CARGA, tam=8, centrar=range(12))
h2('Después · lectura GET /api/beats?limit=20&page=1')
tabla(ENC_CARGA, [fila_carga(f) for f in C_DESP['lectura']['filas']], ANCH_CARGA, tam=8, centrar=range(12))
h2('Después · escritura POST /api/contact (abre un ticket)')
tabla(ENC_CARGA, [fila_carga(f) for f in C_DESP['escritura']['filas']], ANCH_CARGA, tam=8, centrar=range(12))
par(f"**Punto de saturación.** Antes, el servidor se saturaba con ~{SAT_A['usuarios']} usuarios a ~{SAT_A['rps']:.0f} RPS: "
    f"cada respuesta de 1.3 MB ocupa la red y la serialización JSON, así que a partir de ahí más usuarios solo hacen cola y "
    f"la latencia sube hasta {A200['promedio']:.0f} ms (P95 {A200['p95']:.0f} ms) con 200. Incluso `/health` llegó a "
    f"{A200['healthMaxMs']:.0f} ms: el proceso entero se volvía lento. Después, el máximo es ~{SAT_D['rps']:.0f} RPS con "
    f"{SAT_D['usuarios']} usuarios ({SAT_D['rps'] / SAT_A['rps']:.0f}× más) y con 200 usuarios el promedio es "
    f"{D200['promedio']:.0f} ms (P95 {D200['p95']:.0f} ms). La escritura (inserta en la base con su clave de idempotencia) "
    f"alcanza ~{SAT_W['rps']:.0f} RPS con {SAT_W['usuarios']} usuarios. **En ninguna corrida hubo errores** "
    f"({ERR_A:.2f} % antes, {ERR_D:.2f} % después): el servidor se vuelve más lento al saturarse pero no se cae ni responde 5xx.")
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('5. Fase 4 · Base de datos')
par(f"{BD['version']} local, mediana de 7 ejecuciones de `EXPLAIN ANALYZE` (script `npm run p12:db`).")
NOMBRES = {'DB-01': 'Beat por identificador', 'DB-02': 'Conjunto pequeño (primera pantalla)', 'DB-03': 'Conjunto grande (catálogo completo)',
           'DB-04': 'Con filtros (género + BPM + precio)', 'DB-05': 'Bandeja de tickets (consulta crítica)', 'DB-06': 'Tickets de un cliente',
           'DB-07': 'Compras de un cliente'}
filas = []
for k, n in NOMBRES.items():
    a, d = Q_A[k], Q_D[k]
    filas.append([k, n, f"{a['ms']:.2f}", f"{a['filas']:,}".replace(',', ' '), f"{a['kb']:,.1f}".replace(',', ' '),
                  'Sí' if a['secuencial'] else 'No', f"{d['ms']:.2f}", d['filas'], f"{d['kb']:.1f}", ', '.join(d['indices']) or '—'])
tabla(['Prueba', 'Consulta', 'Antes ms', 'Filas', 'KB', 'Seq. scan', 'Después ms', 'Filas', 'KB', 'Índice usado'], filas,
      [0.6, 1.7, 0.7, 0.6, 0.7, 0.5, 0.7, 0.5, 0.5, 1.6], tam=8, centrar=(0, 2, 3, 4, 5, 6, 7, 8))
par('DB-01 varía unas centésimas por ruido de medición: es la misma consulta por llave primaria en ambos casos. Antes, DB-02, '
    'DB-03, DB-05 y DB-06 hacían recorrido secuencial y ordenaban en memoria; después usan los índices '
    '`idx_beats_activo_fecha` (parcial, `where activo`), `idx_contact_messages_estado_fecha` e `idx_contact_messages_user_fecha`.')
h2('Concurrencia (pgbench, 20 clientes)')
c = CON
tabla(['Prueba', 'Escenario', 'Resultado'], [
    ['CON-01', f"{c['distintos']['transacciones']:,} actualizaciones a tickets distintos".replace(',', ' '), f"{c['distintos']['tps']:,.0f} tps · {c['distintos']['latenciaMs']:.2f} ms · {c['distintos']['fallidas']} fallidas".replace(',', ' ')],
    ['CON-02', f"{c['mismo']['transacciones']:,} escrituras al **mismo** ticket".replace(',', ' '), f"{c['mismo']['tps']:,.0f} tps · {c['mismo']['latenciaMs']:.2f} ms (espera por bloqueo de fila) · {c['mismo']['fallidas']} fallidas".replace(',', ' ')],
    ['CON-03', f"{c['tomar']['intentos']} admins toman el mismo ticket a la vez", f"{c['tomar']['ganadores']} lo obtiene; {c['tomar']['intentos'] - c['tomar']['ganadores']} reciben 409 (UPDATE condicionado al estado esperado)"],
    ['CON-04', f"Mismo pago {c['pago']['intentos']} veces con `Idempotency-Key`", f"{c['pago']['enBase']} orden en la base; {c['pago']['intentos'] - c['pago']['insertados']} descartados por la restricción UNIQUE"],
    ['CON-05', f"Mismo pago {c['sinClave']['intentos']} veces **sin** clave (código original)", f"**{c['sinClave']['enBase']} órdenes duplicadas**"],
], [0.8, 2.7, 2.9])
i = c['integridad']
par(f"**Integridad después de todo:** {i['renglonesHuerfanos']} renglones sin orden, {i['respuestasHuerfanas']} respuestas sin ticket, "
    f"{i['foliosRepetidos']} folios repetidos y {i['tickets']:,} tickets sin pérdida.".replace(',', ' '))
par('**Consultas repetidas innecesariamente:** `GET /api/beats` hacía 3 consultas por petición; ahora 1 (más una cada 60 s para '
    'el resumen en caché, compartida entre peticiones simultáneas).')
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('6. Fase 5 · Resiliencia')
tabla(['Código', 'Escenario', 'Esperado', 'Cómo responde la app', 'Evidencia'], [
    ['RES-01', 'Sin internet en una consulta', 'Error controlado', 'Se detecta de inmediato, 2 reintentos con espera de 0.25–1 s y luego el mensaje "Sin conexión…" con botón Reintentar; barra roja global mientras no hay red', 'Prueba RES-01 · captura en el celular'],
    ['RES-02', 'Sin internet en una escritura', 'No confirmar en falso', 'Nunca dice "enviado/pagado" sin respuesta del servidor; avisa que no se confirmó y conserva lo escrito', '`contact_screen`, `payment_screen`'],
    ['RES-03', 'Servidor sin respuesta', 'Timeout controlado', 'connect 8 s / receive 20 s; con 2 reintentos el aviso llega en ≤ 25 s', 'Prueba RES-03'],
    ['RES-04', 'HTTP 500', 'Error y estabilidad', 'No se reintenta (no es transitorio); muestra el mensaje y la pantalla sigue usable', 'Prueba RES-04'],
    ['RES-05', 'HTTP 401 / 403', 'Manejar sesión/permisos', '401 con token → cierra sesión y avisa; 403 → "No tienes permiso"; no se reintentan', 'Prueba RES-05'],
    ['RES-06', 'Recuperación de conexión', 'Restablecer', '502/503/504 con backoff; al volver la red la pantalla carga al reintentar y las transferencias continúan solas', 'Prueba RES-06 · captura'],
    ['RES-07', 'Reintento de escritura', 'Sin duplicados', '`Idempotency-Key` (UUID v4) en pagos, tickets, respuestas y altas de beat; UNIQUE en la base', 'CON-04 / CON-05'],
    ['RES-08', 'Respuesta tardía', 'Sin operaciones dobles', 'Botones deshabilitados durante la operación; 409 si otro admin ya cambió el ticket', 'CON-03'],
], [0.6, 1.2, 1.0, 2.6, 1.0], tam=8.5)
h2('Defecto encontrado en el celular durante esta práctica (D-11)')
par('Al cortar la conexión del celular (`adb reverse --remove`) y abrir el gestor de beats, la pantalla se quedó **cargando '
    'indefinidamente** (esqueleto gris) y en logcat la app repetía `GET /beats sin respuesta · intento 3` cada 1–8 s, sin mostrar '
    'nunca el mensaje de error. La causa: Riverpod 3 reintenta automáticamente cualquier provider que falla (hasta 10 veces, con '
    'espera exponencial) y mantiene el estado en "cargando" mientras tanto; eso se sumaba a los 3 intentos del '
    '`ReintentoInterceptor` (≈30 peticiones y más de 20 s sin respuesta para el usuario).')
par('**Solución aplicada:** `ProviderScope(retry: (_, _) => null)` en `lib/main.dart`: la política de reintentos queda en un solo '
    'lugar (el interceptor de red, que sabe qué es seguro repetir) y la pantalla muestra el error con "Reintentar" en cuanto se '
    'agotan sus 3 intentos. Se volvió a probar en el celular:')
galeria([
    (CAP / 'res01-antes-fix.png', 'D-11 antes: sin red, cargando para siempre'),
    (CAP / 'res01-sin-conexion.png', 'RES-01 después: error controlado con Reintentar'),
    (CAP / 'res06-recuperacion.png', 'RES-06: vuelve la conexión y el catálogo carga'),
], ancho=1.9)
h2('Análisis')
vinetas([
    '**¿Cuánto tarda en detectar una interrupción?** Sin red: inmediato (la conexión se rechaza) y la barra aparece al cambiar la '
    'conectividad. Servidor caído con red: hasta 8 s por intento. Servidor colgado a media respuesta: 20 s.',
    '**¿Qué pasa con la operación pendiente?** Las lecturas se reintentan solas; las escrituras quedan en pantalla con su texto y su '
    'clave para reenviarlas; las subidas y descargas quedan "Esperando conexión" en SQLite.',
    '**¿Se repite automáticamente?** Solo si es seguro: GET/HEAD y escrituras con `Idempotency-Key`, máximo 2 veces, ante fallos '
    'transitorios (sin conexión, timeout, 502/503/504). Nunca ante 4xx o 500.',
    '**¿Puede duplicarse un registro?** Antes sí (CON-05: 20 de 20). Ahora no: la clave UNIQUE lo impide incluso con envíos '
    'simultáneos (CON-04).',
    '**¿Y si el servidor procesa pero la respuesta no llega?** La app no lo confirma; al reintentar con la misma clave la API '
    'encuentra el registro y responde `repetida: true` con el original.',
    '**Reto (exponential backoff + idempotencia):** `ReintentoInterceptor` (base·2ⁿ con tope de 8 s y jitter del 50 %) y la cola '
    'de transferencias (2 s → 60 s), más carga reanudable TUS para subidas y peticiones de rango para descargas.',
])
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('7. Fase 6 · Optimización real y comparación')
par('**Optimización elegida:** paginación + índices + caché del resumen del catálogo + bandeja de tickets paginada, con '
    'idempotencia en las escrituras.')
tabla(['Cambio', 'Archivo'], [
    ['`limit`/`page` en `GET /api/beats` y `GET /api/contact` (sin `limit` responden como antes, para la web)', '`api/src/routes/beats`, `contact`'],
    ['La bandeja trae `contact_replies(count)` en vez del texto de todas las respuestas', '`contact/index.ts`'],
    ['Total y géneros del catálogo en caché 60 s, con una sola consulta compartida', '`beats/index.ts`'],
    ['Índices parciales y compuestos', '`supabase/tickets.sql`, `local/indices.sql`'],
    ['Tienda y gestor con scroll infinito; el inicio pide solo 8 beats', '`catalog_repository.dart`, `store_screen.dart`'],
    ['`Idempotency-Key` + `client_ref UNIQUE` en órdenes, tickets y respuestas', '`api_client.dart`, rutas de la API'],
    ['Sin reintento duplicado de Riverpod (D-11)', '`lib/main.dart`'],
], [4.4, 2.0])
h2('Tabla comparativa antes y después')
tabla(['Métrica', 'Antes', 'Después', 'Diferencia'], [
    ['Latencia promedio API, 1 usuario (ms)', f"{A1['promedio']:.1f}", f"{D1['promedio']:.1f}", dif(A1['promedio'], D1['promedio'])],
    ['Latencia promedio API, 200 usuarios (ms)', f"{A200['promedio']:.0f}", f"{D200['promedio']:.0f}", dif(A200['promedio'], D200['promedio'])],
    ['P95 API, 200 usuarios (ms)', f"{A200['p95']:.0f}", f"{D200['p95']:.0f}", dif(A200['p95'], D200['p95'])],
    ['RPS máximo', f"{SAT_A['rps']:.0f}", f"{SAT_D['rps']:.0f}", f"{SAT_D['rps'] / SAT_A['rps']:.0f}× más"],
    ['Errores (%)', f'{ERR_A:.2f}', f'{ERR_D:.2f}', 'sin errores'],
    ['Tiempo de consulta DB — bandeja de tickets (ms)', f"{Q_A['DB-05']['ms']:.2f}", f"{Q_D['DB-05']['ms']:.2f}", dif(Q_A['DB-05']['ms'], Q_D['DB-05']['ms'])],
    ['Tiempo de consulta DB — primera pantalla tienda (ms)', f"{Q_A['DB-02']['ms']:.2f}", f"{Q_D['DB-02']['ms']:.2f}", dif(Q_A['DB-02']['ms'], Q_D['DB-02']['ms'])],
    ['Tamaño de respuesta — catálogo (KB)', f"{A1['kbPorRespuesta']:.1f}", f"{D1['kbPorRespuesta']:.1f}", dif(A1['kbPorRespuesta'], D1['kbPorRespuesta'])],
    ['Tamaño de respuesta — bandeja (KB)', f"{Q_A['DB-05']['kb']:,.0f}".replace(',', ' '), f"{Q_D['DB-05']['kb']:.1f}", dif(Q_A['DB-05']['kb'], Q_D['DB-05']['kb'])],
    ['Consultas a la base por `GET /beats`', '3', '1', '−66.7 %'],
    ['Pagos duplicados con 20 reintentos', str(c['sinClave']['enBase']), str(c['pago']['enBase']), 'sin duplicados'],
    ['RAM máxima en el celular (MB)', f"{P_A['pss_max']:.1f}", f"{P_D['pss_max']:.1f}", dif(P_A['pss_max'], P_D['pss_max'])],
    ['CPU promedio en el celular (%)', f"{P_A['cpu_prom']:.1f}", f"{P_D['cpu_prom']:.1f}", dif(P_A['cpu_prom'], P_D['cpu_prom'])],
    ['Tiempo de operación crítica en la app (ms)', f"{L_A['prom']:.0f}", f"{L_D['prom']:.0f}", dif(L_A['prom'], L_D['prom'])],
], [3.2, 1.1, 1.1, 1.0], centrar=(1, 2, 3))
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('8. Registro de defectos y correcciones')
tabla(['#', 'Defecto encontrado', 'Severidad', 'Solución aplicada', 'Prueba'], [
    ['D-01', 'Reintentar un pago tras perder la respuesta podía cobrar dos veces', 'Crítica', '`Idempotency-Key` + `orders.client_ref UNIQUE`', 'CON-04/05'],
    ['D-02', 'Un ticket reenviado se creaba dos veces', 'Alta', 'Igual, en `contact_messages`/`contact_replies`', 'Pruebas API'],
    ['D-03', 'La bandeja descargaba todos los tickets con todas las respuestas', 'Alta', 'Paginación + conteo de respuestas', 'DB-05'],
    ['D-04', 'El catálogo completo se pedía para mostrar 8 tarjetas', 'Media', '`novedadesProvider` con `limit=8`', 'DB-02'],
    ['D-05', '3 consultas por cada `GET /beats`', 'Media', 'Caché del resumen (60 s)', 'Prueba API'],
    ['D-06', 'Dos admins podían pisarse el estado de un ticket', 'Media', 'UPDATE condicionado al estado esperado → 409', 'CON-03'],
    ['D-07', 'Una subida cortada empezaba de cero', 'Media', 'Carga reanudable TUS + cola persistente', 'Resiliencia TUS'],
    ['D-08', 'La búsqueda con `,()` alteraba el filtro de PostgREST', 'Media', 'Se descartan esos caracteres', 'Prueba API'],
    ['D-09', 'Un 401 por token vencido dejaba la app "logueada" con errores', 'Media', '`sesionExpiradaProvider` → cierre de sesión', 'RES-05'],
    ['D-10', 'La API aceptaba BPM 999 o precio negativo (500 en la base)', 'Baja', '`validarBeat` → 400', 'Prueba API'],
    ['D-11', 'Sin red, el gestor/tienda se quedaba cargando para siempre (reintento doble de Riverpod)', 'Media', '`ProviderScope(retry: (_, _) => null)`', 'RES-01 en el celular'],
], [0.5, 2.4, 0.7, 1.9, 0.9], tam=8.5)
par(f"**Sin defectos críticos nuevos:** `flutter analyze` sin avisos, **{N_FLUTTER}** pruebas de la app y **{N_API}** de la API "
    f"pasan ({N_API_FAIL} fallidas), y la web sigue funcionando porque sin `limit` las rutas responden exactamente como antes.")

h1('9. Criterios de aceptación')
tabla(['Criterio', 'Estado', 'Evidencia'], [
    ['Prueba de estrés reproducible', 'Cumple', '`carga.mjs` antes y después (sección 4)'],
    ['Análisis de CPU y memoria', 'Cumple', '`perfil_android.ps1` en el Huawei, mismo recorrido (sección 3)'],
    ['Concurrencia de API y base', 'Cumple', 'CON-01…05 e integridad (sección 5)'],
    ['Al menos 3 escenarios de resiliencia', 'Cumple', 'Los 8 (RES-01…08), con pruebas automáticas y capturas'],
    ['Optimización real', 'Cumple', 'Paginación, índices, caché, idempotencia, carga reanudable'],
    ['Comparación antes y después', 'Cumple', 'Tabla de la sección 7: API, base de datos, CPU, RAM y operación crítica'],
    ['Sin defectos críticos nuevos', 'Cumple', 'D-11 se encontró y corrigió; análisis y pruebas en verde'],
], [2.2, 0.8, 3.4])

h1('10. Conclusiones técnicas')
par('El cuello de botella de SkonditBeats no estaba en el teléfono sino en **cuánto dato pedía cada pantalla**. La bandeja de '
    f"tickets tardaba {Q_A['DB-05']['ms']:.0f} ms en la base y devolvía {Q_A['DB-05']['kb'] / 1024:.1f} MB porque traía el texto de "
    f"todas las conversaciones; con paginación, un índice por estado y fecha y el conteo de respuestas, baja a "
    f"{Q_D['DB-05']['ms']:.2f} ms y {Q_D['DB-05']['kb']:.0f} KB. Con el catálogo pasaba lo mismo: 1.3 MB para mostrar 8–20 "
    f"tarjetas. Por eso la API pasó de saturarse en ~{SAT_A['rps']:.0f} RPS a atender ~{SAT_D['rps']:.0f} RPS, y en el celular "
    f"la carga del catálogo bajó de {L_A['prom']:.0f} ms a {L_D['prom']:.0f} ms. La escalabilidad se decide en la forma de la "
    'consulta (qué columnas, cuántas filas, qué índice resuelve el orden) antes que en el hardware.')
par('La prueba de concurrencia mostró el riesgo más grave: sin clave de idempotencia, 20 reintentos de un pago crearon 20 '
    'órdenes. En una red móvil eso no es teórico: basta con que la respuesta se pierda al cambiar de antena. La solución no es '
    '"no reintentar", sino hacer que reintentar sea seguro: el cliente genera un UUID por operación y la base, con una '
    'restricción UNIQUE, garantiza que no haya duplicados incluso con envíos simultáneos.')
par('Probar en el celular real encontró un defecto que las pruebas automáticas no veían: dos capas de reintento (la librería '
    'de estado y el cliente HTTP) se multiplicaban y dejaban al usuario mirando un esqueleto de carga sin fin. La lección es que '
    'la política de reintentos debe vivir en un solo lugar, el que sabe qué operaciones es seguro repetir, y que el usuario '
    'siempre debe recibir una respuesta: datos o un error con la opción de reintentar.')
salto()

h1('Anexo A · Cómo reproducir')
codigo([
    r'cd D:\Angular\erp_beats\api',
    r'powershell -ExecutionPolicy Bypass -File local\preparar.ps1   # base skondit_local con datos fijos',
    r'powershell -ExecutionPolicy Bypass -File local\iniciar.ps1    # PostgREST + Storage local + API :3000',
    r'node --env-file=local/local.env node_modules/tsx/dist/cli.cjs scripts/p12/servidor-antes.ts   # API original :3001',
    'npm run p12:db                                 # Fase 4',
    'node scripts/p12/carga.mjs --etiqueta antes --base http://127.0.0.1:3001 --lectura /api/beats --escritura no',
    'node scripts/p12/carga.mjs --etiqueta despues  # Fase 3',
    r'cd D:\Flutter\skondit_beats_mobile',
    'flutter build apk --profile --dart-define=API_URL=http://127.0.0.1:3000/api',
    r'powershell -File tool\p12\perfil_android.ps1 -Etiqueta despues -Segundos 60   # Fase 2',
    'flutter test ; python tool/p12/informe.py',
])
h1('Anexo B · Registro de peticiones en el celular (logcat)')
par('Antes (API original):', negrita=True)
codigo([l.split('flutter : ')[-1] for l in (EVT / 'log-antes.txt').read_text(encoding='utf-8').splitlines() if 'beats' in l][:5])
par('Después (API optimizada):', negrita=True)
codigo([l.split('flutter : ')[-1] for l in (EVT / 'log-despues.txt').read_text(encoding='utf-8').splitlines()][:5])
par('Sin conexión y recuperación (RES-01 / RES-06):', negrita=True)
codigo([l.split('flutter : ')[-1] for l in (EVT / 'log-resiliencia.txt').read_text(encoding='utf-8').splitlines()][-6:])

doc.save(str(SALIDA))
print('Informe:', SALIDA)
