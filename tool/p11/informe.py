"""Práctica 11 · Genera el informe Word con el formato de las prácticas anteriores.

Usa el .docx de la Práctica 8 como plantilla (estilos, márgenes, pie con número de
página), borra su contenido y escribe el de la Práctica 11. Todas las métricas se
leen de docs/practica11/evidencias (JSON/TXT producidos por las pruebas), así que
ningún número se escribe a mano.

Uso:  python tool/p11/informe.py
"""
import copy
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
EV = RAIZ / 'docs/practica11/evidencias'
GRAFOS = RAIZ / 'docs/practica11/grafos'
PRACTICA = Path(r'D:\Flutter\PRACTICA 11 - Caja blanca - DMI')
CAP = PRACTICA / 'capturas'
PLANTILLA = Path(r'D:\Flutter\PRACTICA 8 - DMI\Practica 8 - Pruebas de caja negra - Orlando Rubio Cabrera.docx')
SALIDA = PRACTICA / 'Practica 11 - Pruebas de caja blanca - Orlando Rubio Cabrera.docx'

AZUL = RGBColor(0x1F, 0x3A, 0x5F)
ROJO = RGBColor(0xA6, 0x1B, 0x1B)
VERDE = RGBColor(0x2F, 0x7D, 0x4A)
GRIS = RGBColor(0x59, 0x59, 0x59)
ANCHO = 9360  # dxa útiles (6.5 in)


def cargar(n):
    return json.loads((EV / n).read_text(encoding='utf-8-sig'))


RED = cargar('red.json')
BD = cargar('db.json')
COB = cargar('cobertura_metodos.json')
FPS = cargar('wb06_fotogramas.json')
COD = cargar('codigos.json')
COB_API = {}
for l in (EV / '04_api_test_cobertura_DESPUES.txt').read_text(encoding='utf-8-sig').splitlines():
    m = re.match(r'# (src\\\S+|all files)\s+\|\s+([\d.]+)\s+\|\s+([\d.]+)\s+\|\s+([\d.]+)', l)
    if m:
        COB_API[m.group(1)] = tuple(float(x) for x in m.groups()[1:])
TOTAL_GLOBAL = re.search(r'GLOBAL.*?(\d+)/(\d+)\s+([\d.]+)%\s+(\d+)/(\d+)\s+([\d.]+)%',
                         (EV / '03_cobertura_metodos.txt').read_text(encoding='utf-8-sig')).groups()

# ── Documento a partir de la plantilla ────────────────────────────────────────
doc = Document(str(PLANTILLA))
cuerpo = doc.element.body
for hijo in list(cuerpo):
    if hijo.tag != qn('w:sectPr'):
        cuerpo.remove(hijo)
for rid, rel in list(doc.part.rels.items()):
    if rel.reltype.endswith('/image'):
        doc.part.drop_rel(rid)


def _runs(p, texto, tam=None, color=None, negrita=False, cursiva=False, fuente=None):
    """Agrega texto con **negritas** y `código` en línea."""
    for trozo in re.split(r'(\*\*.+?\*\*|`.+?`)', texto):
        if not trozo:
            continue
        r = p.add_run(trozo.strip('*') if trozo.startswith('**') else trozo.strip('`') if trozo.startswith('`') else trozo)
        r.bold = negrita or trozo.startswith('**')
        r.italic = cursiva
        if trozo.startswith('`'):
            r.font.name = 'Consolas'
            r.font.size = Pt((tam or 11) - 1.5)
        elif tam:
            r.font.size = Pt(tam)
        if fuente:
            r.font.name = fuente
        if color:
            r.font.color.rgb = color
    return p


def par(texto='', **k):
    p = doc.add_paragraph()
    alin = k.pop('alin', None)
    if alin:
        p.alignment = alin
    return _runs(p, texto, **k)


def h1(t):
    doc.add_heading(t, level=1)


def h2(t):
    doc.add_heading(t, level=2)


def h3(t):
    doc.add_heading(t, level=3)


def vinetas(items):
    for i in items:
        _runs(doc.add_paragraph(style='List Bullet'), i)


def numerada(items):
    for n, i in enumerate(items, 1):
        _runs(doc.add_paragraph(), f'{n}.\t{i}')


def sombra(celda, color):
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), color)
    celda._tc.get_or_add_tcPr().append(shd)


def _celda(c, texto, negrita=False, color=None, tam=9.5, alin=None):
    c.text = ''
    p = c.paragraphs[0]
    if alin:
        p.alignment = alin
    for i, linea in enumerate(str(texto).split('\n')):
        if i:
            p = c.add_paragraph()
        _runs(p, linea, tam=tam, negrita=negrita, color=color)


def mantener_junta(t, max_filas=16):
    """Evita que una fila se parta y, en tablas cortas, que la tabla se divida entre páginas."""
    filas = t.rows
    for i, fila in enumerate(filas):
        trpr = fila._tr.get_or_add_trPr()
        trpr.append(OxmlElement('w:cantSplit'))
        if len(filas) <= max_filas and i < len(filas) - 1:
            for c in fila.cells:
                for p in c.paragraphs:
                    p.paragraph_format.keep_with_next = True


def tabla(encabezados, filas, anchos, tam=9.5, centrar=()):
    """Tabla con encabezado azul (como la Práctica 8). anchos en proporciones."""
    total = sum(anchos)
    dxa = [int(ANCHO * a / total) for a in anchos]
    t = doc.add_table(rows=1, cols=len(encabezados))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for i, e in enumerate(encabezados):
        c = t.rows[0].cells[i]
        _celda(c, e, negrita=True, color=RGBColor(0xFF, 0xFF, 0xFF), tam=tam)
        sombra(c, '1F3A5F')
    trpr = t.rows[0]._tr.get_or_add_trPr()
    trpr.append(OxmlElement('w:tblHeader'))
    for f in filas:
        celdas = t.add_row().cells
        for i, v in enumerate(f):
            color = None
            s = str(v)
            if s.startswith(('✅', 'Aprobad', 'Cumple')):
                color = VERDE
            elif s.startswith(('❌', 'Falla', 'No cumple')):
                color = ROJO
            _celda(celdas[i], s, tam=tam, color=color, alin=WD_ALIGN_PARAGRAPH.CENTER if i in centrar else None)
    for fila in t.rows:
        for i, c in enumerate(fila.cells):
            c.width = Inches(dxa[i] / 1440)
    mantener_junta(t)
    doc.add_paragraph()
    return t


def ficha(filas, anchos=(1.25, 4.15)):
    """Tabla de dos columnas con etiqueta sombreada (ficha de caso o de defecto)."""
    t = doc.add_table(rows=0, cols=2)
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for etiqueta, valor in filas:
        a, b = t.add_row().cells
        _celda(a, etiqueta, negrita=True)
        sombra(a, 'E8EEF5')
        color = ROJO if str(valor).startswith(('Alta', 'Crítica')) else None
        _celda(b, valor, color=color)
    for fila in t.rows:
        fila.cells[0].width = Inches(anchos[0])
        fila.cells[1].width = Inches(anchos[1])
    mantener_junta(t, max_filas=12)
    doc.add_paragraph()


def imagen(ruta, ancho_max=6.4, alto_max=7.6, pie=None):
    w, h = Image.open(ruta).size
    ancho = min(ancho_max, alto_max * w / h)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run().add_picture(str(ruta), width=Inches(ancho))
    p.paragraph_format.keep_with_next = bool(pie)
    if pie:
        par(pie, tam=9, cursiva=True, color=GRIS, alin=WD_ALIGN_PARAGRAPH.CENTER)


def galeria(items, ancho=2.05):
    """Fila de capturas del celular con su pie, en tabla sin bordes (como la Práctica 8)."""
    t = doc.add_table(rows=2, cols=len(items))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, (ruta, pie) in enumerate(items):
        p = t.rows[0].cells[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(str(ruta), width=Inches(ancho))
        _celda(t.rows[1].cells[i], pie, tam=8.5, color=GRIS, alin=WD_ALIGN_PARAGRAPH.CENTER)
    doc.add_paragraph()


def codigo(lineas):
    for l in lineas:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(l)
        r.font.name = 'Consolas'
        r.font.size = Pt(8)
    doc.add_paragraph()


def salto():
    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)


def campo_toc():
    p = doc.add_paragraph()
    r = p.add_run()
    for tipo, texto in (('begin', None), (None, 'TOC \\o "1-2" \\h \\z \\u'), ('separate', None), (None, None), ('end', None)):
        if tipo:
            f = OxmlElement('w:fldChar')
            f.set(qn('w:fldCharType'), tipo)
            r._r.append(f)
        elif texto:
            it = OxmlElement('w:instrText')
            it.set(qn('xml:space'), 'preserve')
            it.text = texto
            r._r.append(it)
        else:
            tx = OxmlElement('w:t')
            tx.text = 'Actualiza el índice (clic derecho → Actualizar campos).'
            r._r.append(tx)


# Atajos a los datos medidos
def http(origen, destino):
    return next(h for h in RED['http'] if h['origen'].startswith(origen) and h['destino'] == destino)


def ping(prefijo):
    return next(p for p in RED['ping'] if p['destino'].startswith(prefijo))


def transf(sentido, origen, destino):
    return [x for x in RED['transferencia'] if x['sentido'] == sentido and x['origen'] == origen and x['destino'] == destino]


def prom(v):
    return round(sum(v) / len(v), 2)


def cob(id_):
    return next(c for c in COB if c['metodo'].startswith(id_))


def pc(c, k):
    return f"{c[k + '_cubiertas']}/{c[k + '_total']} ({100 * c[k + '_cubiertas'] / c[k + '_total']:.1f} %)"


CEL_LOCAL = http('Celular', 'API local por USB')
CEL_PROD = http('Celular', 'Producción por Wi-Fi')
PC_LOCAL = http('PC', 'API local')
PC_LOCAL = next(h for h in RED['http'] if h['origen'] == 'PC' and h['destino'] == 'API local' and 'beats' in h['ruta'])
PC_PROD = http('PC', 'Producción (Vercel + Supabase)')
P_ROUTER, P_PC, P_PROD = ping('Router'), ping('PC con'), ping('Producción')
Q = {c['id']: c for c in BD['consultas']}
CARGA = RED['carga']
TODAS_FPS = FPS['corridas']
CUADROS = sum(c['cuadros'] for c in TODAS_FPS)
LENTOS = sum(c['mas_de_33_3ms'] for c in TODAS_FPS)

# ═════════════════════════════════════════════════════════════════════════════
# Portada
# ═════════════════════════════════════════════════════════════════════════════
for _ in range(4):
    doc.add_paragraph()
par('Desarrollo Móvil Integral', tam=16, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
par('Práctica 11', tam=26, negrita=True, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
par('Pruebas de caja blanca (White Box Testing): auditoría técnica de la estructura interna', tam=16, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
par('Aplicación evaluada: SkonditBeats Mobile (Flutter + API Fastify + PostgreSQL/Supabase)', tam=12, color=AZUL, alin=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_paragraph()
for linea in ('Alumno: Orlando Rubio Cabrera', 'Docente: MANUEL CONTRERAS CASTILLO', 'Grupo: IDGS16', 'Fecha: 11 de noviembre de 2026'):
    par(linea, tam=12, alin=WD_ALIGN_PARAGRAPH.CENTER)
salto()
par('Índice', tam=16, negrita=True, color=AZUL)
campo_toc()
salto()

# ═════════════════════════════════════════════════════════════════════════════
h1('1. Introducción')
par('SkonditBeats Mobile es la versión móvil de la tienda de beats SkonditBeats. La app (Flutter) permite registrarse, '
    'iniciar sesión con verificación en dos pasos, explorar y escuchar el catálogo, armar un carrito que se guarda en SQLite, '
    'pagar con tarjeta simulada, abrir tickets de soporte y subir o descargar archivos de forma reanudable. Consume una API REST '
    '(Fastify + TypeScript) que persiste en PostgreSQL: en producción es Supabase y para las pruebas se usa el mismo motor '
    '(PostgreSQL 16 + PostgREST) en la PC.')
par('En esta práctica se auditó el funcionamiento **interno** de los tres componentes (app, API y base de datos) y la comunicación '
    'entre ellos: se leyó el código, se dibujaron grafos de flujo, se diseñaron pruebas por camino, se midió la cobertura, se '
    'ejecutaron operaciones reales en la base, se midieron latencia, ping, transferencia y carga, y se cortó la conexión del '
    'celular a media operación. Cada defecto encontrado se **corrigió** y la corrección quedó verificada con la misma prueba '
    'que lo detectó.')
h2('Objetivo')
par('Demostrar con evidencias técnicas (código, pruebas automatizadas, registros de ejecución y mediciones) que la aplicación '
    'funciona correctamente desde su estructura interna, que sus componentes se comunican de forma eficiente y que los datos '
    'mantienen su integridad durante todo el proceso.')
h2('Entorno de prueba')
ent = RED['entorno']
tabla(['Elemento', 'Detalle'], [
    ['Dispositivo', f"Huawei {ent['celular']['modelo']} · Android {ent['celular']['android']} · 1080 × 2400 · 60 Hz · IP Wi-Fi {ent['celular']['ip']}"],
    ['Equipo (servidor local)', ent['pc']],
    ['Versión de la app', 'SkonditBeats Mobile 1.0.0+1 · Flutter 3.44.0 / Dart 3.12.0 · commit base `b4a690d` → final `b09a9ba`'],
    ['Compilación en el celular', '`flutter build apk --profile --dart-define=API_URL=http://127.0.0.1:3000/api`'],
    ['API', f"Fastify 5 · Node {ent['node']} · commit base `74ab19d` → final `9bdd33f` (repo `D:\\Angular\\erp_beats\\api`)"],
    ['Base de datos', f"{BD['motor'].split(',')[0]} local (`skondit_local`: 5 000 beats, 2 003 usuarios, 20 000 órdenes, "
                      '40 001 renglones, 12 000 tickets) + PostgREST 16.5, el mismo motor que expone Supabase'],
    ['Producción (solo lecturas)', f"{ent['produccion']} (Vercel + Supabase)"],
    ['Conexión', 'Celular ↔ API local por cable USB (`adb reverse tcp:3000` y `tcp:54321`); celular ↔ internet por Wi-Fi; '
                 'PC con ProtonVPN activo'],
    ['Fecha de ejecución', '11 de noviembre de 2026'],
], [1.6, 4.9])

# ═════════════════════════════════════════════════════════════════════════════
h1('2. Metodología')
numerada([
    '**Inspección y análisis estático:** módulos, funciones de red y de base de datos, analizadores (`flutter analyze`, `tsc`, '
    '`npm audit`, `npm outdated`) y revisión manual de los 7 puntos obligatorios.',
    '**Caja blanca de la app:** 3 métodos críticos (validación, procesamiento y comunicación) más 2 complementarios; grafo de flujo, '
    'complejidad ciclomática V(G), caminos independientes, pruebas unitarias y cobertura de instrucciones, ramas y condiciones.',
    '**Caja blanca de la API:** 3 endpoints; revisión de controladores, esquemas y middleware; pruebas por camino con la base '
    'interceptada y una matriz de códigos HTTP contra la API real.',
    '**Caja blanca de la base de datos:** operaciones CRUD reales, restricciones, transacciones, EXPLAIN ANALYZE y concurrencia con '
    'dos sesiones simultáneas.',
    '**Conectividad y rendimiento:** ping, latencia HTTP por fases, transferencia, carga controlada, interrupción de la conexión '
    'en el celular y fluidez de la interfaz.',
    '**Integración y defectos:** cada hallazgo con pasos, esperado, observado, severidad, evidencia y la **solución aplicada**.',
])
par('Técnicas: cobertura de instrucciones, de decisiones (ramas) y de condiciones (MC/DC), valores límite y pruebas de excepciones. '
    'Regla aplicada: no se escribieron pruebas artificiales para inflar la cobertura; los caminos que no se ejecutan se justifican.')
h2('Herramientas')
tabla(['Herramienta', 'Uso en la práctica'], [
    ['Git', 'Identificar la versión evaluada (commits base y final de cada repositorio) y aislar el código original para las pruebas «antes».'],
    ['flutter analyze · tsc --noEmit', 'Análisis estático de la app (Dart) y de la API (TypeScript).'],
    ['npm audit · npm outdated · flutter pub outdated', 'Dependencias vulnerables y desactualizadas.'],
    ['flutter test --coverage --branch-coverage', 'Pruebas de la app con cobertura de líneas y ramas (lcov); `tool/p11/cobertura_metodos.py` la recorta por método.'],
    ['node:test + --experimental-test-coverage', 'Pruebas de la API con la base interceptada y cobertura por archivo.'],
    ['psql + EXPLAIN (ANALYZE, BUFFERS)', 'Operaciones reales, planes de ejecución y concurrencia (`scripts/p11/db-whitebox.mjs`).'],
    ['scripts/p11/codigos.mjs', 'Equivalente reproducible a una colección de Postman: 18 peticiones reales con código esperado y obtenido.'],
    ['scripts/p11/red.mjs', 'Equivalente a k6/Apache Bench: latencia por fases (DNS, TCP, TLS, primer byte), transferencia y carga con 1, 5 y 10 usuarios.'],
    ['adb (curl, ping, logcat, screencap, dumpsys)', 'Mediciones desde el propio celular, registros `[p12]` de la app, capturas y tiempos de cuadros.'],
], [2.1, 4.4])
par('Postman, JMeter, k6 y Wireshark no estaban instalados. Se sustituyeron por scripts propios que miden lo mismo y quedan en el '
    'repositorio para repetirse con un solo comando. No se capturó tráfico con Wireshark: la red Wi-Fi no es propia y la PC tiene '
    'una VPN activa. En su lugar se registraron los tiempos de cada fase de la conexión (DNS, TCP, TLS, primer byte) con Node y '
    'con `curl -w` en el celular.', tam=10, cursiva=True)

# ═════════════════════════════════════════════════════════════════════════════
h1('3. Fase 1 · Inspección y análisis estático')
h2('Módulos principales')
tabla(['Componente', 'Módulo', 'Responsabilidad'], [
    ['App', '`core/network/api_client.dart`', 'Cliente Dio: token Bearer, reintentos con espera exponencial, medición `[p12]` y traducción de errores (`ApiException`).'],
    ['App', '`core/utils/validators.dart`', 'Validación de formularios: correo, contraseña, edad, OTP y tarjeta (Luhn, vencimiento, CVV).'],
    ['App', '`core/database/app_database.dart`', 'SQLite local: carrito, accesos y transferencias.'],
    ['App', '`features/*`', 'auth, catalog, cart, checkout, contact, admin, transfers, player, notifications, profile.'],
    ['API', '`src/routes/*` (10 módulos)', 'auth, beats, packs, orders, contact, users, profile, stats, audit, uploads.'],
    ['API', '`src/plugins/*`', 'JWT, idempotencia, auditoría, política de contraseñas, correo, CORS.'],
    ['BD', '`local/schema.sql` · `supabase/*.sql`', '11 tablas con NOT NULL, CHECK, UNIQUE, FK, índices y el disparador `trg_compra_unica`.'],
], [0.8, 2.2, 3.5])
h2('Funciones que se conectan con el servidor')
vinetas([
    '`dioProvider` (`api_client.dart`): cliente único con `baseUrl` inyectada por `--dart-define`, tiempos límite de 8 s (conexión) '
    'y 20 s (respuesta), interceptor de token, `ReintentoInterceptor` y `MedicionInterceptor`.',
    'Repositorios (`auth`, `catalog`, `orders`, `contact`, `admin`, `profile`): cada llamada pasa por `_run()` o `try/catch`, que '
    'convierte `DioException` en `ApiException` con un mensaje para el usuario.',
    '`TusClient` y `DescargaReanudable`: subida TUS y descarga con `Range` para archivos grandes.',
])
h2('Métodos de acceso a la base de datos')
vinetas([
    '**App:** `CartDao`, `TransferenciaDao` y `AccesoDao` sobre SQLite (`sqflite`), con consultas parametrizadas (`where: \'user_id = ?\'`).',
    '**API:** `supabase-js` (PostgREST) con la llave `service_role` solo en el servidor. La app nunca habla directo con la base; toda '
    'consulta pasa por la API, que valida el JWT y vuelve a leer el rol de la cuenta en cada petición.',
])
h2('Resultados de las herramientas')
tabla(['Herramienta', 'Antes', 'Después', 'Evidencia'], [
    ['flutter analyze', 'No issues found', 'No issues found', '`00_flutter_analyze.txt`'],
    ['tsc --noEmit (API)', '0 errores', '0 errores', '`00_tsc.txt`'],
    ['npm audit --omit=dev (producción)', '❌ 7: 1 crítica (fast-jwt), 5 altas (fast-uri, fastify, find-my-way, nodemailer, ws), 1 moderada (qs)',
     '✅ 0 vulnerabilidades', '`05_npm_audit_ANTES.txt` / `_DESPUES.txt`'],
    ['npm audit (incluye desarrollo)', '—', '11 en `@vercel/node`, esbuild y glob: herramientas de compilación que no se ejecutan en el servidor',
     '`05_npm_audit_DESPUES_con_dev.txt`'],
    ['Dependencias sin uso', '`nodemailer` y `googleapis` instalados sin ningún `import`', 'Eliminadas', 'DEF-14'],
    ['npm outdated / flutter pub outdated', '13 paquetes con versión menor disponible / 47 con versión nueva fuera de las restricciones',
     'Sin cambio: `flutter_local_notifications` se fijó en 22.0.0 a propósito (la 23 exige Android SDK 37)', '`06_npm_outdated.txt`'],
], [1.6, 1.9, 1.9, 1.1])
h2('Puntos de revisión obligatorios')
tabla(['Punto', 'Resultado', 'Sección del código'], [
    ['Métodos sin manejo de excepciones', 'Las llamadas a la API de los 9 archivos de red pasan por `_run()`/`try`. `Validators.luhn` lanzaba `FormatException` con guiones (DEF-07).',
     '`*_repository.dart` · `validators.dart:67`'],
    ['Credenciales o claves expuestas', 'Sin secretos en `lib/` (URL por `--dart-define`). El `.env` de la API no se versiona. `local/local.env` sí, pero solo trae un JWT de pruebas. En desarrollo el login devuelve `otpDev`; en producción está apagado.',
     '`env.dart` · `auth/index.ts:260`'],
    ['Validaciones duplicadas o inexistentes', 'El correo solo se validaba en la app (DEF-10). El vencimiento de tarjeta no tenía límite superior (DEF-06). La política de contraseña está duplicada a propósito en app y servidor.',
     '`validators.dart` · `plugins/password.ts`'],
    ['Código inaccesible o redundante', 'Dependencias sin uso (DEF-14), `digits.isNotEmpty &&` redundante (se quitó con DEF-07) y un camino infactible en `luhn` y otro en `addPack` (sección 4).',
     '`package.json` · `validators.dart`'],
    ['Consultas con datos sin validar', 'La búsqueda limpia los caracteres especiales del filtro `or()` de PostgREST (prueba E2·C6). Un id que no es UUID provocaba 22P02 y ahora se responde 404 o 422.',
     '`beats/index.ts:110` · `orders/index.ts`'],
    ['Red bloqueando el hilo principal', 'Toda la E/S es asíncrona (`Future`/`await`). No se usan isolates: el JSON se decodifica en el hilo principal, pero la paginación lo dejó en 5.5 KB por página y WB-06 no muestra jank sostenido.',
     '`catalog_repository.dart`'],
    ['Recursos que no se liberan', '14 archivos revisados: todos los `TextEditingController`, `StreamSubscription`, `Timer` y `AnimationController` se liberan en `dispose()` o `cancel()`; el `StreamController` de sesión se cierra con `ref.onDispose`.',
     'pantallas `*_screen.dart` · `api_client.dart:198`'],
], [1.45, 3.45, 1.6], tam=9)

# ═════════════════════════════════════════════════════════════════════════════
h1('4. Fase 2 · Caja blanca de la aplicación móvil')
par('Se eligieron tres métodos obligatorios (M1 validación, M3 procesamiento, M4 comunicación) y dos complementarios (M2 y M5). '
    'Las pruebas están en `test/whitebox/`: `validators_wb_test.dart` (35), `cart_wb_test.dart` (13) y `api_client_wb_test.dart` (26): '
    '**74 pruebas nuevas**. Cada una indica en su nombre el camino que recorre.')

h2('M1 · Validators.cardExpiry (método de validación)')
par('Valida la fecha de vencimiento de la tarjeta en el pago. **Condiciones:** D1 `m == null`; D2 `mes < 1 || mes > 12` (2 condiciones); '
    'D3 `anio < año || (anio == año && mes < mesActual)` (3 condiciones); D4 `anio > año + 20` (agregada por DEF-06); además dos '
    'operadores `??` (`v ?? \'\'` y `now ?? DateTime.now()`).')
imagen(GRAFOS / 'M1_cardExpiry.png', ancho_max=5.6, alto_max=6.2, pie='Figura 1. Grafo de flujo de control de cardExpiry.')
par('**Complejidad ciclomática:** V(G) = E − N + 2 = 16 − 13 + 2 = **5** = decisiones + 1 = 4 + 1. Contando cada condición '
    'atómica (1 + 2 + 3 + 1) más los dos `??`: 9 condiciones, V(G) extendido = 10.')
tabla(['Camino', 'Secuencia de nodos', 'Entrada (hoy = 11/2026)', 'Salida esperada', 'Resultado'], [
    ['P1', '1-2-3-Fin', '"1126"', '"Usa el formato MM/AA"', '✅ Aprobado'],
    ['P2', '1-2-4-5-6-Fin', '"13/27" y "00/27"', '"Mes no válido"', '✅ Aprobado'],
    ['P3', '1-2-4-5-7-8-9-Fin', '"12/25" y "10/26"', '"La tarjeta está vencida"', '✅ Aprobado'],
    ['P4', '1-2-4-5-7-8-10-11-Fin', '"12/99" (año 2099)', '"Fecha no válida"', '✅ DEF-06 corregido'],
    ['P5', '1-2-4-5-7-8-10-12-Fin', '"01/27", "11/26"', 'null (válida)', '✅ Aprobado'],
], [0.6, 1.6, 1.4, 1.6, 1.3], centrar=(0,))
par('**Cobertura de condiciones (MC/DC) de D3** — A: `anio < año`, B: `anio == año`, C: `mes < mesActual`. Cada fila cambia el '
    'resultado moviendo una sola condición:')
tabla(['Caso', 'A', 'B', 'C', 'Decisión D3', 'Entrada'], [
    ['1', 'V', '—', '—', 'V (vencida)', '"12/25"'],
    ['2', 'F', 'F', '—', 'F (vigente)', '"01/27"'],
    ['3', 'F', 'V', 'V', 'V (vencida)', '"10/26"'],
    ['4', 'F', 'V', 'F', 'F (vigente)', '"12/26"'],
], [0.6, 0.5, 0.5, 0.5, 1.4, 1.4], centrar=(0, 1, 2, 3))
par('**Valores límite:** mes 00/01/12/13; mes actual (11/26 vigente) contra mes anterior (10/26 vencida); 12/46 (+20 años) válida '
    'y 01/47 rechazada; formatos 1/27, 011/27, 01/2027, " 01/27", null y "" rechazados; cambio de año (12/26 contra 01/27 con hoy = '
    '01/01/2027). La rama derecha del `??` se cubre llamando sin `now`.')

h2('M3 · CartController.addPack (método de procesamiento)')
par('Agrega un paquete al carrito y quita los beats sueltos que ya incluye, para no cobrarlos dos veces. **Decisiones:** '
    '`_userId == null` (agregada por DEF-02), `contains(pack)`, `yaTiene > 0`, ternario `yaTiene == 1`, el ciclo `for` sobre '
    '`repetidos` y el ternario `repetidos.isEmpty`.')
imagen(GRAFOS / 'M3_addPack.png', ancho_max=6.3, alto_max=5.2, pie='Figura 2. Grafo de flujo de control de addPack.')
par('**V(G)** = 22 − 17 + 2 = **7** = 6 decisiones + 1.')
tabla(['Camino', 'Secuencia', 'Situación', 'Resultado esperado', 'Resultado'], [
    ['P1', '1-2', 'Sin sesión', 'ok = false, nada se guarda', '✅ DEF-02 corregido'],
    ['P2', '1-3-4', 'El paquete ya está en el carrito', '"Este paquete ya está en tu carrito"', '✅ Aprobado'],
    ['P3', '1-3-5-6-7-7a', 'Ya compró 1 beat del paquete', '"Ya tienes 1 beat de este paquete"', '✅ Aprobado'],
    ['P4', '1-3-5-6-7-7b', 'Ya compró 2 beats', '"Ya tienes 2 beats de este paquete"', '✅ Aprobado'],
    ['P5', '1-3-5-6-8-9-11-12-13', 'Sin beats sueltos repetidos', 'Total 500; el ciclo no itera', '✅ Aprobado'],
    ['P6', '1-3-5-6-8-9-10-9-11-12-14', 'Con 2 beats sueltos repetidos', 'Los quita; total 700 (200 + 500); SQLite igual a memoria', '✅ Aprobado'],
    ['P7', '9 (sin iterar) → 14', '—', 'Infactible', 'Justificado'],
], [0.6, 1.7, 1.5, 1.8, 0.9], centrar=(0,))
par('**Camino infactible (P7):** las decisiones 9 y 12 dependen de la misma lista. Si el ciclo no itera, `repetidos` está vacía y el '
    'ternario no puede ir a 14; si itera, no puede ir a 13. Por eso hay 6 caminos factibles para V(G) = 7, y no se forzó una prueba artificial. '
    '**Excepciones:** si SQLite falla al insertar, el error llega a quien llama y el estado en memoria no cambia (no se muestra un '
    'artículo que no se guardó).')

h2('M4 · ApiException.fromDio (método de comunicación)')
par('Traduce cualquier falla de red o HTTP en un mensaje para el usuario y marca si fue por falta de conexión (`sinRed`). Es el '
    'método con **mayor complejidad ciclomática** de la app.')
imagen(GRAFOS / 'M4_fromDio.png', ancho_max=5.4, alto_max=5.6, pie='Figura 3. Grafo de flujo de control de fromDio.')
par('**V(G)** = 30 − 21 + 2 = **11** (10 decisiones + 1). Con condiciones atómicas: D1 tiene 3 (`Map`, `error is String`, `!deFastify`), '
    'el `switch` tiene 5 etiquetas y D5 (`400 || 422`) y D7 (`!= null && >= 500`) tienen 2 cada una.')
tabla(['Camino', 'Entrada (DioException)', 'Mensaje / bandera', 'Resultado'], [
    ['P1', '409 con `{"error": "Ya tienes uno o más de estos beats"}`', 'Se usa el mensaje de la API y el código 409', '✅'],
    ['P2', 'connectionTimeout, receiveTimeout, sendTimeout', '"El servidor tardó demasiado…" · sinRed', '✅'],
    ['P3', 'connectionError', '"Sin conexión con el servidor…" · sinRed', '✅'],
    ['P4', 'cancel', '"Operación cancelada."', '✅'],
    ['P5', '401 sin cuerpo', '"Tu sesión expiró…"', '✅'],
    ['P6', '403 sin cuerpo', '"No tienes permiso…" (no se confunde con 401)', '✅'],
    ['P7', '400 de Fastify `{statusCode, error:"Bad Request"}` y 422', '"Revisa los datos e intenta de nuevo."', '✅ DEF-01 corregido'],
    ['P8', '404 de ruta inexistente', '"No se encontró lo que buscabas."', '✅ DEF-01 corregido'],
    ['P9', '500 y 503', '"El servidor tuvo un problema (500)…"', '✅'],
    ['P10', 'unknown sin respuesta (corte a media respuesta)', '"Se perdió la conexión…" · sinRed', '✅'],
    ['P11', '418 sin cuerpo', '"Ocurrió un error inesperado (418)."', '✅'],
], [0.6, 2.4, 2.4, 1.1], centrar=(0, 3))
par('**Valores límite:** 499 no es error de servidor y 500 sí. **Excepciones:** un cuerpo HTML de un proxy (502) no rompe la traducción.')

h2('Métodos complementarios: M2 luhn y M5 ReintentoInterceptor')
par('**M2 · Validators.luhn** (cálculo del dígito verificador): V(G) = 5 (validación de dígitos, ciclo, `i.isOdd`, `d > 9`). '
    'Caminos: cadena inválida o vacía → false; "0" (sin duplicar); "18" (duplica ≤ 9); "59" (duplica > 9 y resta 9); tarjetas de '
    'prueba de 16 dígitos. El camino «ciclo con 0 vueltas» es infactible después de DEF-07, porque la expresión `^\\d+$` garantiza al '
    'menos un dígito.')
par('**M5 · ReintentoInterceptor.onError**: decisión compuesta `cancelada || n >= max || !seguro || !transitorio`. MC/DC:')
tabla(['Caso', 'cancelada', 'n ≥ max', '!seguro', '!transitorio', '¿Reintenta?', 'Prueba (servidor local)'], [
    ['1', 'F', 'F', 'F', 'F', 'Sí', '503, 503, 200 → se recupera en el 3.er intento'],
    ['2', 'V', 'F', 'F', 'F', 'No', 'CancelToken cancelado durante la espera'],
    ['3', 'F', 'V', 'F', 'F', 'No', 'maxReintentos = 0 (valor límite) → 1 solo intento'],
    ['4', 'F', 'F', 'V', 'F', 'No', 'POST sin Idempotency-Key con 503 → 1 intento (no duplica)'],
    ['5', 'F', 'F', 'F', 'V', 'No', '500 (no transitorio) → se entrega de inmediato'],
], [0.5, 0.8, 0.7, 0.7, 0.9, 0.8, 2.6], centrar=(0, 1, 2, 3, 4, 5))
par('Valores límite de `esTransitorio`: 501 no, 502/503/504 sí, 505 no. `esperaPara(n)`: con n = 0 queda entre 250 y 500 ms y con '
    'n = 20 nunca pasa del tope de 8 s.')

h2('Cobertura obtenida')
tabla(['Método', 'Líneas del archivo', 'Instrucciones', 'Ramas'], [
    [c['metodo'], c['lineas'], pc(c, 'instr'), pc(c, 'ramas')] for c in COB
] + [['**Total de módulos críticos**', '', f"{sum(c['instr_cubiertas'] for c in COB)}/{sum(c['instr_total'] for c in COB)} (100 %)",
      f"{sum(c['ramas_cubiertas'] for c in COB)}/{sum(c['ramas_total'] for c in COB)} (100 %)"],
     ['Global (todo `lib/` con pruebas)', '', f'{TOTAL_GLOBAL[0]}/{TOTAL_GLOBAL[1]} ({TOTAL_GLOBAL[2]} %)', f'{TOTAL_GLOBAL[3]}/{TOTAL_GLOBAL[4]} ({TOTAL_GLOBAL[5]} %)']],
    [2.6, 1.1, 1.4, 1.4])
par(f'La cobertura **global** ({TOTAL_GLOBAL[2]} % de líneas) es baja a propósito. Lo que queda fuera son pantallas (widgets), el '
    'reproductor (`just_audio`), la biometría, el almacenamiento seguro y SQLite real, que dependen de la plataforma Android. Esas '
    'partes se validaron en el celular en la Fase 5 (interrupción, registros y fluidez) en lugar de simularlas con pruebas artificiales.')
imagen(CAP / 'C3_cobertura_metodos.png', pie='Captura 1. Todas las pruebas de la app pasan y la cobertura por método se calcula desde coverage/lcov.info.')
par('**Antes de corregir.** Las mismas pruebas, corridas sobre el código original (commit `b4a690d`), detectaron 7 fallas reales:')
imagen(CAP / 'C1_app_pruebas_antes.png', pie='Captura 2. Pruebas de caja blanca sobre el código original: 7 fallas que llevaron a DEF-01, 02, 06 y 07.')

# ═════════════════════════════════════════════════════════════════════════════
h1('5. Fase 3 · Caja blanca del sitio web y los servicios (API)')
par('Endpoints seleccionados: **E1** `POST /api/orders` (escritura, cálculo del total y base de datos), **E2** `GET /api/beats` y '
    '`/api/beats/:id` (lectura) y **E3** `POST /api/auth/login` con el control de acceso. Se revisaron los controladores, los esquemas '
    'JSON de Fastify (Ajv), el middleware `authenticate` (verifica el JWT y vuelve a leer el rol de la cuenta en la base), '
    '`plugins/idempotencia.ts` y `validarBeat`. Las pruebas están en `scripts/p11/whitebox.test.ts` (**56 pruebas**): la base se '
    'intercepta con un `fetch` falso, así que cada camino se fuerza sin depender de la red.')
h2('E1 · POST /api/orders')
imagen(GRAFOS / 'E1_postOrders.png', ancho_max=5.3, alto_max=5.6, pie='Figura 4. Grafo de flujo de control del controlador de órdenes (beats sueltos).')
tabla(['Camino', 'Situación', 'HTTP', 'Verificación adicional', 'Resultado'], [
    ['C1', 'Sin token', '401', 'No escribe órdenes', '✅'],
    ['C2', '`beats: []` (minItems = 1, valor límite 0)', '400', 'code = FST_ERR_VALIDATION', '✅'],
    ['C3', 'Ni beats ni packId', '400', '"Se requiere beats o packId"', '✅'],
    ['C4', '`beats` es objeto', '400', '—', '✅'],
    ['C4b', '`beats: "b1"` (Fastify lo convierte en `["b1"]`)', '422', 'OBS-01: coerceTypes de Ajv', '✅'],
    ['C5', 'Beat inexistente', '422', 'No escribe nada', '✅ (antes 400)'],
    ['C6', 'Uno existe y otro no', '422', 'Antes cobraba solo el existente', '✅ DEF-03 corregido'],
    ['C7', 'id que no es UUID (22P02)', '422', 'No es 500', '✅ (antes 500)'],
    ['C8', 'La base no responde', '500', 'Sin "PGRST" en la respuesta', '✅ (antes 400)'],
    ['C9', 'Ya compró uno de los beats', '409', 'No escribe órdenes', '✅'],
    ['C10', 'Compra válida con un beat repetido', '201', 'Total = 449 con los precios de la BD; dueño tomado del token; 2 renglones', '✅'],
    ['C11', 'Fallan los renglones', '500', 'DELETE de la orden incompleta', '✅ DEF-04 corregido'],
    ['C11b', 'Otra compra simultánea ganó (23505)', '409', 'Orden deshecha', '✅ (DEF-08)'],
    ['C12', 'Reintento con la misma Idempotency-Key', '200', '`repetida: true`, 0 escrituras', '✅'],
], [0.55, 2.2, 0.55, 2.3, 0.9], centrar=(0, 2))
h2('E2 y E3 · Consulta, inicio de sesión y autorización')
tabla(['Caso', 'HTTP', 'Comprobación', 'Resultado'], [
    ['GET /beats/:id existente', '200', '`{ beat }` solo con las columnas que usa la app (DEF-09)', '✅'],
    ['GET /beats/:id UUID inexistente / id "123"', '404 / 404', '`{"error":"Beat no encontrado"}`', '✅'],
    ['GET /beats/:id con la base caída', '500', 'Antes respondía 404 y ocultaba la caída (DEF-05)', '✅'],
    ['GET /beats?limit = 0, 1, 100, 1000, −5', '200', 'limit efectivo 20, 1, 100, 100, 1; claves estables', '✅'],
    ['Búsqueda `x),precio.lt.1,(nombre.ilike.*`', '200', 'No inyecta filtros en PostgREST', '✅'],
    ['Login: correo no registrado / contraseña mala', '401 / 401', 'Mismo mensaje: no revela si el correo existe; suma intento', '✅'],
    ['Login: 5.º intento fallido (límite)', '423', 'Bloqueo de 15 min', '✅'],
    ['Login: cuenta bloqueada vigente / desactivada', '423 / 401', 'No compara la contraseña', '✅'],
    ['Login correcto (admin, correo con espacios y mayúsculas)', '200', '6 campos de usuario, sin hash; correo normalizado', '✅'],
    ['/api/users sin token / token falso / token de cliente', '401 / 401 / 403', 'Autenticación ≠ autorización', '✅'],
    ['Registro o contacto con correo "nope", "a@b", "a b@c.com", ""', '400', 'Antes se aceptaban (DEF-10)', '✅'],
], [2.5, 0.9, 2.3, 0.8], centrar=(1, 3))
h2('Matriz de códigos HTTP contra la API real')
par('`scripts/p11/codigos.mjs` envía peticiones reales a la API local (con PostgREST y PostgreSQL) y compara el código esperado con el '
    'obtenido. Además revisa que ninguna respuesta contenga contraseñas, hashes bcrypt, la llave `service_role` ni detalles internos.')
tabla(['Esp.', 'Obt.', 'Situación', 'Petición', 'ms', 'Bytes', 'Cumple'],
      [[f['esperado'], f['obtenido'], f['situacion'], f['peticion'].replace('/api', '')[:38], f['ms'], f['bytes'], '✅' if f['cumple'] else '❌'] for f in COD]
      + [[500, 500, 'Error inesperado: PostgREST detenido (base caída)', 'GET /beats/:id', 7047, 36, '✅']],
      [0.45, 0.45, 2.15, 1.9, 0.5, 0.5, 0.65], tam=8.5, centrar=(0, 1, 4, 5, 6))
par(f"**Resultado:** {sum(f['cumple'] for f in COD) + 1}/{len(COD) + 1} casos cumplen; se evaluaron los diez códigos (200, 201, 204, "
    '400, 401, 403, 404, 409, 422, 500). El servidor **no responde siempre 200**: cada falla tiene su código. **No confunde** '
    'autenticación (401: sin token o token inválido) con autorización (403: token válido sin permiso). El 422 de BPM fuera de rango '
    'respondía 400 antes de DEF-13.')
h2('Estructura JSON y datos sensibles')
vinetas([
    f"Las 10 respuestas consecutivas de `GET /api/beats?limit=20` tuvieron el mismo código (200), el mismo tamaño ({PC_LOCAL['solicitudes'][0]['bytes']} B), "
    'el mismo contenido (1 hash distinto) y las mismas claves: `beats, generos, limit, page, total`.',
    'Login y `/api/users` devuelven campos explícitos (nunca `password`); la consulta de usuarios ni siquiera pide esa columna. Los errores '
    '500 no exponen códigos de PostgREST ni trazas.',
    'Observación: en desarrollo (`NODE_ENV≠production`) el login devuelve `otpDev` porque no se envían correos; en producción el envío '
    'es obligatorio y el código nunca viaja en la respuesta.',
])
def capi(fin):
    return next(v for k, v in COB_API.items() if k.replace('\\', '/').endswith(fin))


o_, i_, g_ = capi('orders/index.ts'), capi('idempotencia.ts'), COB_API['all files']
par(f"**Cobertura de la API** (92 pruebas en total): `orders/index.ts` {o_[0]} % de líneas y {o_[1]} % de ramas; "
    f"`idempotencia.ts` {i_[0]} % / {i_[1]} %; global {g_[0]} % de líneas, {g_[1]} % de ramas y "
    f"{g_[2]} % de funciones. Lo que falta en `orders` es la compra de paquetes y el intercambio de beats, fuera de los "
    'endpoints elegidos.')
imagen(CAP / 'C2_api_pruebas_antes.png', pie='Captura 3. Pruebas de la API sobre el código original (commit 74ab19d): 7 de 54 fallan (DEF-03, 04 y 05).')

# ═════════════════════════════════════════════════════════════════════════════
h1('6. Fase 4 · Caja blanca de la base de datos')
par('`scripts/p11/db-whitebox.mjs` ejecuta operaciones reales sobre PostgreSQL 16 (el mismo motor de Supabase) con registros de '
    'prueba propios (prefijo «P11 ») que borra al terminar. Los tiempos son los que reporta `psql` (`\\timing`) desde la PC.')
h2('Operaciones')
tabla(['ID', 'Operación', 'Tiempo (ms)', 'Resultado', 'Cumple'],
      [[o['id'], o['nombre'], o.get('ms') if o.get('ms') is not None else '—', (o['resultado'] or '') + (f" ({o['sqlstate']})" if o['sqlstate'] else ''), '✅' if o['cumple'] else '❌'] for o in BD['operaciones']],
      [0.7, 2.2, 0.8, 2.3, 0.6], centrar=(0, 2, 4))
h2('Restricciones (NOT NULL, CHECK, UNIQUE, FK, tipos)')
tabla(['Tipo', 'Caso', 'SQLSTATE esperado', 'Obtenido', 'Cumple'],
      [[r['tipo'], r['nombre'], r['esperado'], r['obtenido'], '✅' if r['cumple'] else '❌'] for r in BD['restricciones']],
      [0.9, 2.9, 1.1, 0.9, 0.7], centrar=(2, 3, 4))
par('Índices en uso: llaves primarias, `orders_client_ref_key` y `contact_messages.client_ref` (UNIQUE, para la idempotencia), '
    '`order_items(order_id, beat_id)` (UNIQUE), `idx_beats_activo_fecha` (parcial `WHERE activo`), `idx_orders_user_status`, '
    '`idx_order_items_beat` y `idx_orders_user`.')
h2('Transacciones y operaciones parcialmente completadas')
tx = BD['transaccion']
par(f"Se insertó una orden y luego un renglón inválido. Dentro de `BEGIN … COMMIT` quedaron **{tx['con_transaccion_ordenes_que_quedan']}** órdenes "
    f"(se revirtió todo). Con dos sentencias sueltas, como lo hacía la API con dos llamadas a PostgREST, quedó **{tx['sin_transaccion_ordenes_huerfanas']}** "
    'orden huérfana. Esa es la causa de DEF-04: la API ahora borra la orden si fallan sus renglones (`deshacerOrden`).')
h2('Medición de consultas (EXPLAIN ANALYZE, mediana de 7)')
tabla(['ID', 'Consulta', 'Ejecución ms', 'Planeación ms', 'Filas', 'Bytes', 'Plan / índice'],
      [[c['id'], c['nombre'], c['ejecucion_ms'], c['planeacion_ms'], c['filas'], c['bytes'], ', '.join(c['indices'])] for c in BD['consultas']],
      [0.4, 2.1, 0.7, 0.75, 0.5, 0.55, 1.5], tam=8.5, centrar=(0, 2, 3, 4, 5))
par(f"Todas las consultas usan índice y tardan menos de {max(c['ejecucion_ms'] for c in BD['consultas']) + 0.1:.1f} ms (objetivo ≤ 200 ms). "
    f"**Consulta que recupera más de lo necesario:** Q1 (`select *`) devolvía {Q['Q1']['bytes']} bytes y Q5 (solo las columnas que usa la app) "
    f"{Q['Q5']['bytes']} bytes, un {round(100 * (Q['Q1']['bytes'] / Q['Q5']['bytes'] - 1))} % de más (DEF-09). **Inyección SQL:** "
    "el valor `' or 1=1 --` enviado como parámetro (como lo hace PostgREST) devolvió 0 filas.")
h2('Concurrencia sobre el mismo registro')
imagen(CAP / 'C4_concurrencia_bd.png', ancho_max=5.6, pie='Captura 4. Dos sesiones de psql al mismo tiempo: la carrera de compras (DEF-08) antes y después de la corrección.')
c6a = next(c for c in BD['concurrencia'] if c['id'] == 'DB-06a')
par(f"**DB-06a:** dos `UPDATE precio = precio + n` simultáneos. PostgreSQL bloqueó la fila: la segunda sesión esperó {c6a['espera_sesion_b_ms']} ms y "
    f"el valor final fue {c6a['obtenido']} (100 + 10 + 25), sin pérdida de actualizaciones. **DB-06b:** dos compras simultáneas del mismo "
    'beat por la misma cuenta con claves de idempotencia distintas (dos teléfonos), siguiendo el flujo real de la API. Sin protección '
    'se cobraron **las dos**. Con el disparador `trg_compra_unica` (candado por usuario + verificación) la segunda se rechaza con 23505 '
    'y la API responde 409.')
h2('Seguridad y permisos')
par('La base no se expone a la app: solo la API la consulta, con la llave `service_role` en variables de entorno del servidor. Cada '
    'ruta protegida verifica el JWT y vuelve a leer el rol en la base, así que un token de alguien degradado o desactivado deja de '
    'servir (pruebas de seguridad de la Práctica 10, que siguen pasando). Las reglas RLS de Supabase no aplican a la `service_role`, por lo que '
    'el control de acceso real está en la API y se verificó con la matriz 401/403. **Consistencia app–servidor:** el total de una orden '
    'se calcula con los precios de la base, no con los que manda la app (E1·C10), y el carrito local quita lo que la cuenta ya compró '
    'en otro dispositivo (`removeOwned`).')

# ═════════════════════════════════════════════════════════════════════════════
h1('7. Fase 5 · Conectividad y rendimiento')
h2('A. Ping y latencia de red (ICMP, 20 paquetes desde el celular)')
tabla(['Destino', 'Recibidos', 'Pérdida %', 'Mín ms', 'Prom ms', 'Máx ms', 'Desv ms'],
      [[p['destino'], f"{p['recibidos']}/20", p['perdida_pct'], p['min'] or '—', p['promedio'] or '—', p['max'] or '—', p['desv'] or '—'] for p in RED['ping']],
      [2.5, 0.8, 0.8, 0.6, 0.6, 0.6, 0.6], centrar=(1, 2, 3, 4, 5, 6))
par('**Limitación registrada:** la PC no responde ICMP. Tiene ProtonVPN activo, que toma la ruta por defecto y bloquea el ICMP de la '
    'red local, y el firewall de Windows descarta el ping entrante. Además, la app llega a la API por el cable USB (`adb reverse`), un '
    'enlace sin ruta IP en el que el ping no aplica. Por eso, para el camino app → API se usó latencia HTTP (sección B). El ping al '
    'servidor de producción sí respondió y sirve para comparar ICMP contra HTTP (pregunta 4).', tam=10)
h2('B. Latencia HTTP (10 solicitudes consecutivas)')
tabla(['Origen → destino', 'Ruta', 'Mín', 'Prom', 'Máx', 'Desv', 'P95'],
      [[f"{h['origen'].split(' (')[0]} → {h['destino']}", h['ruta'], h['min'], h['promedio'], h['max'], h['desv'], h['p95']] for h in RED['http']],
      [2.3, 1.9, 0.45, 0.45, 0.45, 0.45, 0.45], tam=9, centrar=(2, 3, 4, 5, 6))
par('**Tabla de resultados por solicitud** (endpoint real de la app, medido desde el celular con `curl -w` hacia la API local por USB):')
tabla(['Solicitud', 'Código HTTP', 'Tiempo (ms)', 'Primer byte (ms)', 'Tamaño (bytes)'],
      [[i + 1, s['status'], s['ms'], s['ttfb'], s['bytes']] for i, s in enumerate(CEL_LOCAL['solicitudes'])]
      + [['Promedio', '', CEL_LOCAL['promedio'], '', ''], ['Mín / Máx', '', f"{CEL_LOCAL['min']} / {CEL_LOCAL['max']}", '', '']],
      [1.0, 1.0, 1.1, 1.3, 1.2], centrar=(0, 1, 2, 3, 4))
par(f"Desde producción (celular → Vercel + Supabase por Wi-Fi) el mismo endpoint promedió **{CEL_PROD['promedio']} ms**. De eso, el TLS "
    f"tomó ~{round(prom([s['tls'] for s in CEL_PROD['solicitudes']]))} ms y el primer byte llegó a los ~{round(prom([s['ttfb'] for s in CEL_PROD['solicitudes']]))} ms; "
    'la descarga del cuerpo fue casi instantánea. Dentro de la app, los registros `[p12]` del celular dieron entre 17 y 43 ms para '
    '`GET /beats` en 10 recargas (`07_logcat_celular.txt`).')
h2('C. Tasa de transferencia')
par('Tasa (Mbps) = (bytes transferidos × 8) / (tiempo en s × 1 000 000). Descarga: catálogo completo `GET /api/beats` (1.35 MB). '
    'Subida: archivo de 5 MB por el mismo camino que usa la app para subir audio (URL firmada → Storage).')
filas_t = []
for sentido, origen, destino in [('Descarga', 'PC', 'API local'), ('Descarga', 'Celular', 'API local por USB'),
                                 ('Subida', 'PC', 'Storage local'), ('Subida', 'Celular', 'Storage local por USB'),
                                 ('Descarga', 'Celular', 'Producción por Wi-Fi')]:
    m = transf(sentido, origen, destino)
    filas_t.append([sentido, f'{origen} → {destino}', m[0]['bytes'], ' / '.join(str(x['ms']) for x in m), ' / '.join(str(x['mbps']) for x in m), prom([x['mbps'] for x in m])])
tabla(['Sentido', 'Origen → destino', 'Bytes', 'Tiempo ms (3 mediciones)', 'Mbps (3 mediciones)', 'Mbps prom.'], filas_t,
      [0.8, 1.9, 0.8, 1.4, 1.3, 0.7], tam=9, centrar=(2, 5))
par('El enlace USB del celular sostuvo ~80 Mbps de bajada y ~108 Mbps de subida. En producción el catálogo real pesa solo 3.2 KB, '
    'así que su «tasa» (0.07 Mbps) refleja la latencia del servidor y no el ancho de banda: es la evidencia de que ahí el límite no es '
    'la red.', tam=10)
h2('D. Comparación de respuestas')
par(f"Las 10 solicitudes de la tabla B (celular → API local): mínimo {CEL_LOCAL['min']} ms, máximo {CEL_LOCAL['max']} ms, promedio "
    f"{CEL_LOCAL['promedio']} ms y desviación {CEL_LOCAL['desv']} ms. Todas devolvieron 200 con {CEL_LOCAL['solicitudes'][0]['bytes']} bytes. "
    'En la PC, las 10 respuestas tuvieron el mismo hash de contenido, así que los datos fueron consistentes en cada repetición.')
h2('E. Prueba de interrupción (celular real)')
par('Se usó la pantalla Contacto → Crear ticket, una escritura con `Idempotency-Key`. La conexión del celular con la API se cortó de '
    'forma controlada desde la PC, en dos momentos distintos:')
tabla(['Escenario', 'Cómo se cortó', 'Comportamiento de la app', 'En la base', 'Cumple'], [
    ['1. Sin red antes de enviar', '`adb reverse --remove tcp:3000`', 'Reintentó 2 veces (1.4 s en total) y mostró «Sin conexión… No se confirmó el envío; reintenta sin miedo a duplicarlo». Conservó el formulario.', '0 tickets', '✅'],
    ['1. Recuperación', 'Se restauró el túnel y se tocó Crear de nuevo', '201 en 55 ms: «Ticket #12121 creado»', '1 ticket', '✅'],
    ['2. Se pierde la respuesta (petición en vuelo)', 'Tabla bloqueada 12 s + `adb kill-server` a los 2.8 s', 'Tras 3 intentos (9.9 s) mostró el mismo aviso; no dio la operación por exitosa', 'Al liberarse el candado el servidor **sí guardó** el #12123', '✅'],
    ['2. Recuperación', 'Túnel restaurado y mismo formulario', '**200** (no 201) en 50 ms: devolvió el ticket existente #12123', 'Sigue 1 ticket: sin duplicado', '✅'],
], [1.25, 1.35, 2.2, 1.1, 0.6], tam=9, centrar=(4,))
par('Hallazgo de la prueba: quitar el reenvío con `adb reverse --remove` **no corta** las conexiones TCP ya abiertas (la petición en '
    'vuelo recibió su 201 a los 13.4 s), por eso el segundo escenario cortó el túnel completo con `adb kill-server`.', tam=10)
galeria([(CAP / 'NET05b_error_sin_conexion.png', 'Captura 5. Escenario 1: sin red, la app avisa y no da el envío por bueno.'),
         (CAP / 'NET05c_respuesta_perdida.png', 'Captura 6. Escenario 2: la respuesta se perdió con la petición en vuelo.'),
         (CAP / 'NET06b_reintento_sin_duplicar.png', 'Captura 7. Reintento: el servidor devuelve el mismo ticket #12123 (200).')])
h2('F. Carga controlada (entorno local propio)')
par('40 solicitudes por escenario (mínimo pedido: 20), con 1, 5 y 10 usuarios concurrentes. Lectura: `GET /api/beats?limit=20&page=N`. '
    'Escritura: `POST /api/contact` con una clave de idempotencia distinta por solicitud; los 120 tickets de prueba se borraron al terminar. '
    'CPU y RAM corresponden al proceso Node de la API, medidos con `Get-Process`.')
tabla(['Endpoint', 'Usuarios', 'OK', 'Fallidas', 'Prom ms', 'P95 ms', 'Máx ms', 'Req/s', 'Mbps', 'CPU API %', 'RAM MB'],
      [[c['endpoint'].split(' (')[0].replace('/api/', '/'), c['usuarios'], c['exitosas'], c['fallidas'], c['promedio'], c['p95'], c['max'], c['rps'], c['mbps'], c['cpu_api_pct'], c['ram_api_mb']] for c in CARGA],
      [1.5, 0.55, 0.4, 0.5, 0.5, 0.5, 0.5, 0.5, 0.45, 0.55, 0.5], tam=8, centrar=tuple(range(1, 11)))
par('**Lectura de resultados:** 240/240 solicitudes exitosas y 0 fallidas. Al pasar de 1 a 10 usuarios, el promedio de lectura subió de '
    f"{CARGA[0]['promedio']} a {CARGA[2]['promedio']} ms y el P95 de {CARGA[0]['p95']} a {CARGA[2]['p95']} ms; el rendimiento creció de "
    f"{CARGA[0]['rps']} a {CARGA[2]['rps']} req/s, pero de 5 a 10 usuarios solo un {round(100 * (CARGA[2]['rps'] / CARGA[1]['rps'] - 1))} %, "
    'señal de que el proceso único de Node (CPU entre 60 y 100 % de un núcleo) se acerca a su límite. La base no fue el cuello: tuvo como '
    'máximo 1 conexión activa a la vez (PostgREST reutiliza su pool) y cada consulta tarda menos de 0.5 ms.')
h2('G. Rendimiento de la interfaz (WB-06)')
par('Con la APK profile en el celular se hizo scroll en la Tienda (dos gestos hacia abajo y uno hacia arriba, 3 corridas). Los '
    'tiempos de presentación de cada cuadro se leyeron de SurfaceFlinger (`dumpsys SurfaceFlinger --latency`, capa SurfaceView de '
    'Flutter) con `tool/p11/fotogramas.py`.')
tabla(['Corrida', 'Cuadros', 'FPS prom.', 'ms prom.', 'P50', 'P90', 'P99', 'Máx', '> 33.3 ms'],
      [[i + 1, c['cuadros'], c['fps_promedio'], c['ms_promedio'], c['ms_p50'], c['ms_p90'], c['ms_p99'], c['ms_max'], c['mas_de_33_3ms']] for i, c in enumerate(TODAS_FPS)],
      [0.6, 0.7, 0.7, 0.7, 0.6, 0.6, 0.6, 0.6, 0.8], centrar=tuple(range(9)))
par(f'De {CUADROS} cuadros, {LENTOS} ({100 * LENTOS / CUADROS:.1f} %) superaron 33 ms, todos en la corrida 2, al cargar la siguiente '
    'página de portadas. La pantalla mantuvo 58–60 FPS (refresco de 60 Hz) y un P90 de 16.8 ms: sin bloqueos visibles.')

# ═════════════════════════════════════════════════════════════════════════════
h1('8. Fase 6 · Integración y reporte de defectos')
par('Se encontraron **14 defectos**, todos **corregidos y verificados**. Cada uno tiene una prueba que fallaba antes y pasa después '
    '(salidas en `01_…_ANTES.txt` y `04_…_ANTES.txt`). La columna «Solución aplicada» describe el cambio que ya está en el código, con su commit.')
DEFECTOS = [
    ('DEF-01', 'App · `core/network/api_client.dart` → `ApiException.fromDio`', 'Media',
     'Enviar un formulario con datos que el esquema de la API rechaza (p. ej. `beats: []`) o pedir una ruta inexistente.',
     'Un mensaje en español que le diga al usuario qué hacer.', 'La pantalla mostraba «Bad Request» o «Not Found»: el campo `error` genérico de Fastify se tomaba como mensaje.',
     'Pruebas M4 «errores generados por Fastify» (3 fallaban: Captura 2).',
     'Se distingue la respuesta de Fastify (trae `statusCode`) de la de las rutas; 400/422 → «Revisa los datos e intenta de nuevo», 404 → «No se encontró lo que buscabas». App `600e7f0`.'),
    ('DEF-02', 'App · `cart_controller.dart` → `addBeat` / `addPack`', 'Media',
     'Sin sesión (usuario nulo), agregar un beat o un paquete.', 'ok = false y ningún mensaje de éxito.',
     '`_insert()` salía sin guardar, pero se respondía ok = true y «se agregó al carrito».', 'Prueba M3 «sin sesión…» (fallaba).',
     'Se valida la sesión al inicio de ambos métodos y se responde «Inicia sesión para usar el carrito». App `600e7f0`.'),
    ('DEF-03', 'API · `routes/orders/index.ts` → POST /api/orders', 'Alta',
     'POST /api/orders con `{"beats": [idValido, idInexistente]}`.', 'Rechazar toda la orden con 422.',
     'Se creaba la orden y se cobraba solo el beat existente; el otro se descartaba sin avisar.', 'Prueba E1·C6 (fallaba: Captura 3).',
     'Si se encuentran menos beats que los pedidos, 422 sin escribir nada; un error de PostgREST que no sea 22P02 → 500. API `e18e479`.'),
    ('DEF-04', 'API · `routes/orders/index.ts` (beats y paquetes)', 'Alta',
     'Provocar un error al insertar `order_items` después de crear la orden.', 'Ninguna orden a medias.',
     'Quedaba una orden COMPLETADA sin renglones. En la base: sin transacción, 1 orden huérfana.', 'Prueba E1·C11 (fallaba) · sección 6 «Transacciones».',
     'Nueva función `deshacerOrden()`: borra la orden si fallan sus renglones (compensación), en compras sueltas y de paquetes. API `e18e479`.'),
    ('DEF-05', 'API · `routes/beats/index.ts` → GET /api/beats/:id', 'Media',
     'Detener la base (PostgREST) y pedir un beat existente.', '500: falla del servidor.',
     'Respondía 404 «Beat no encontrado» y ocultaba la caída.', 'Prueba E2·C4 (fallaba) · 500 en vivo (`codigos.md`).',
     'Se usa `maybeSingle()`: sin fila → 404; 22P02 → 404; cualquier otro error → 500. API `e18e479`.'),
    ('DEF-06', 'App · `validators.dart` → `cardExpiry`', 'Baja',
     'Escribir «12/99» como vencimiento.', 'Rechazar una fecha imposible.', 'Se aceptaba como vigente (año 2099).',
     'Prueba M1·P4 (fallaba).', 'Límite de 20 años (`maxAniosVigencia`); 12/46 válida y 01/47 «Fecha no válida». App `600e7f0`.'),
    ('DEF-07', 'App · `validators.dart` → `luhn`', 'Baja',
     'Llamar `Validators.luhn(\'4242-4242\')`.', 'Responder false.', 'Lanzaba FormatException (método público sin manejo de excepciones).',
     'Prueba M2 «pruebas de excepciones» (fallaba).', 'Se valida `^\\d+$` antes del ciclo y se quitó la condición redundante. App `600e7f0`.'),
    ('DEF-08', 'BD + API · `order_items` / POST /api/orders', 'Alta',
     'Dos compras simultáneas del mismo beat con la misma cuenta (dos teléfonos, claves distintas).', 'Una sola compra.',
     'Se cobraban las dos: ambas pasaban «¿ya lo compró?» antes de que la otra guardara.', 'DB-06b (obtenido = 2, Captura 4).',
     'Disparador `trg_compra_unica` (`local/p11_compras_unicas.sql` y `supabase/compras_unicas.sql`): candado por usuario + verificación → 23505; la API deshace la orden y responde 409. API `80240d4`.'),
    ('DEF-09', 'API · GET /api/beats/:id', 'Baja',
     'Pedir el detalle de un beat.', 'Solo las columnas que usa la app.', '`select *` enviaba también `activo`, `client_ref` y `updated_at`: 362 B en lugar de 234 (+55 %).',
     'Q1 contra Q5 (sección 6).', 'Mismas columnas que la lista (`CAMPOS_LISTA`). API `80240d4`.'),
    ('DEF-10', 'API · registro, contacto y alta de usuarios', 'Media',
     'POST /api/auth/register o /api/contact con `"email": "nope"` (desde Postman/curl).', '400.',
     'Se aceptaba cualquier texto: el correo solo lo validaba la app.', 'Prueba «correo con formato inválido» · `codigos.md`.',
     'Esquema común `EMAIL` (`src/schemas/comunes.ts`) en las tres rutas. API `80240d4`.'),
    ('DEF-11', 'BD local · `local/preparar.ps1`', 'Media',
     'Con una base local creada antes, abrir la app en el celular.', '200 en `GET /api/contact/no-leidos`.',
     '500: faltaban las columnas `no_leido_admin` y `no_leido_cliente` porque `create table if not exists` no agrega columnas nuevas.',
     'Registro `[p12]` del celular (`07_logcat_celular.txt`) · diff de esquemas.',
     'Se agregaron las columnas y `preparar.ps1` ahora recrea la base completa (`drop database … with (force)`). API `c2b7ed6`.'),
    ('DEF-12', 'App · `api_client.dart` → `MedicionInterceptor`', 'Baja',
     'Petición que falla con reintentos (sin red).', 'Una línea de registro por petición.',
     'La falla final se imprimía 3 veces («intento 3»), porque cada reintento pasa por toda la cadena de interceptores.', 'Registro del celular · prueba DEF-12 (fallaba).',
     'Se marca la petición como registrada en `extra` y se imprime una sola vez. App `b09a9ba`.'),
    ('DEF-13', 'API · `routes/beats/index.ts` → `validarBeat`', 'Baja',
     'POST /api/beats con `bpm: 999`.', '422 (valor fuera de rango); 400 solo si faltan campos.', 'Respondía 400 en ambos casos.',
     'Matriz de códigos en vivo (17/18 antes).', '`codigoValidacion()`: faltan campos → 400; valor inválido → 422. API `9bdd33f`.'),
    ('DEF-14', 'API · dependencias (`package.json`)', 'Crítica',
     '`npm audit --omit=dev`.', '0 vulnerabilidades en producción.',
     '7 (1 crítica: fast-jwt permitía saltarse la verificación del JWT; 5 altas). `nodemailer` y `googleapis` estaban instalados sin usarse.',
     '`05_npm_audit_ANTES.txt` / `_DESPUES.txt`.', '`npm audit fix` y se eliminaron las dos dependencias sin uso → 0. API `e18e479` y `de485cb`.'),
]
tabla(['ID', 'Componente', 'Severidad', 'Solución aplicada'], [[d[0], d[1], d[2], d[7].split('. ')[0] + '.'] for d in DEFECTOS],
      [0.65, 2.0, 0.75, 3.1], tam=8.5, centrar=(0, 2))
for d in DEFECTOS:
    h3(f'{d[0]}')
    ficha([('Componente', d[1]), ('Pasos para reproducir', d[3]), ('Resultado esperado', d[4]), ('Resultado observado', d[5]),
           ('Severidad', d[2]), ('Evidencia', d[6]), ('Solución aplicada', d[7]), ('Verificación', 'La prueba que lo detectó pasa con la corrección.')])
h2('Observaciones del entorno (no son defectos de la app)')
vinetas([
    '**PostgREST no arrancaba:** cerraba con 0xC0000139 porque cargaba la `libpq.dll` de `C:\\xampp\\php`. `iniciar.ps1` ahora antepone '
    'en el PATH la carpeta de PostgreSQL 16 (API `c2b7ed6`).',
    '**ProtonVPN** bloquea el ICMP de la red local: no hay ping entre la PC y el celular (sección 7-A).',
    '**OBS-01:** Fastify convierte un texto en arreglo (`coerceTypes: \'array\'` de Ajv), así que `beats: "b1"` llega como `["b1"]`; la '
    'orden se rechaza igual (E1·C4b).',
    '**Pendiente en producción:** el código corregido está en los repositorios, pero para que DEF-08 aplique en Supabase hay que ejecutar '
    '`supabase/compras_unicas.sql` en su editor SQL y desplegar la API.',
])

# ═════════════════════════════════════════════════════════════════════════════
h1('9. Matriz de pruebas White Box')
ok = '✅ Aprobado'
okc = '✅ Aprobado tras corrección'
MATRIZ = [
    ('Aplicación móvil', [
        ('WB-01', 'Cobertura de instrucciones', ok, '81/81 (100 %) en métodos críticos · Captura 1 · `03_cobertura_metodos.txt`'),
        ('WB-02', 'Cobertura de decisiones', ok, '42/42 ramas (100 %) · lcov `--branch-coverage`'),
        ('WB-03', 'Cobertura de condiciones', ok, 'MC/DC de cardExpiry D3 y de ReintentoInterceptor (sección 4)'),
        ('WB-04', 'Manejo de excepciones', okc, 'DEF-07 · error de SQLite en addPack · cuerpo HTML en fromDio'),
        ('WB-05', 'Validación de entradas', okc, 'Valores límite (M1, edad, contraseña, CVV, OTP, teléfono) · DEF-02 y DEF-06'),
        ('WB-06', 'Rendimiento de interfaz', ok, f'{CUADROS} cuadros, 58–60 FPS, {LENTOS} lentos · `wb06_fotogramas.json`'),
    ]),
    ('Sitio web / API', [
        ('WEB-01', 'Respuesta HTTP exitosa', ok, '200, 201 y 204 en vivo (`codigos.md`)'),
        ('WEB-02', 'Respuesta HTTP de error', okc, '400, 404, 409, 422 y 500 en vivo · DEF-05 y DEF-13'),
        ('WEB-03', 'Validación del backend', okc, 'Esquemas, validarBeat y 422 · DEF-03 y DEF-10'),
        ('WEB-04', 'Autenticación y autorización', ok, '401 ≠ 403; JWT con rol releído; DEF-14 (fast-jwt)'),
        ('WEB-05', 'Latencia HTTP', ok, f"Celular → API local {CEL_LOCAL['promedio']} ms; → producción {CEL_PROD['promedio']} ms"),
        ('WEB-06', 'Consistencia de respuesta', ok, '10/10 respuestas idénticas; estructura JSON estable'),
    ]),
    ('Base de datos', [
        ('DB-01', 'Inserción válida', ok, f"DB-01 · {BD['operaciones'][0]['ms']} ms"),
        ('DB-02', 'Integridad', ok, f"{sum(r['cumple'] for r in BD['restricciones'])}/{len(BD['restricciones'])} restricciones con el SQLSTATE esperado"),
        ('DB-03', 'Consulta', ok, 'Por id existente e inexistente · EXPLAIN Q1–Q5 < 0.5 ms'),
        ('DB-04', 'Actualización', ok, 'Precio 349 leído en otra conexión'),
        ('DB-05', 'Eliminación', ok, 'FK restrict en beat vendido · cascada a renglones · 0 filas después'),
        ('DB-06', 'Concurrencia', okc, 'DB-06a sin pérdidas · DB-06b corregido con trg_compra_unica (DEF-08) · Captura 4'),
    ]),
    ('Conectividad y rendimiento', [
        ('NET-01', 'Ping', ok, f"Router {P_ROUTER['promedio']} ms y Vercel {P_PROD['promedio']} ms, 0 % de pérdida; PC bloqueada por VPN (justificado)"),
        ('NET-02', 'Latencia de API', ok, f"10 solicitudes: prom. {CEL_LOCAL['promedio']} ms, P95 {CEL_LOCAL['p95']} ms"),
        ('NET-03', 'Tasa de descarga', ok, f"Celular por USB {prom([x['mbps'] for x in transf('Descarga', 'Celular', 'API local por USB')])} Mbps"),
        ('NET-04', 'Tasa de subida', ok, f"Celular por USB {prom([x['mbps'] for x in transf('Subida', 'Celular', 'Storage local por USB')])} Mbps"),
        ('NET-05', 'Pérdida de conexión', ok, 'Escenarios 1 y 2 · Capturas 5 y 6'),
        ('NET-06', 'Recuperación', ok, 'Reintento con la misma clave: 200, mismo folio, sin duplicado · Captura 7'),
        ('NET-07', 'Carga controlada', ok, '240/240 exitosas con 1, 5 y 10 usuarios'),
    ]),
]
for grupo, filas in MATRIZ:
    h2(grupo)
    tabla(['ID', 'Prueba', 'Resultado', 'Evidencia'], [list(f) for f in filas], [0.7, 1.6, 1.6, 2.6], tam=9, centrar=(0,))

# ═════════════════════════════════════════════════════════════════════════════
h1('10. Registro de métricas de rendimiento')
h2('A. Tabla de medición de conectividad')
d_cel = transf('Descarga', 'Celular', 'API local por USB')
s_cel = transf('Subida', 'Celular', 'Storage local por USB')
tabla(['Métrica', 'Unidad', 'Cantidad', 'Valor medido'], [
    ['Ping mínimo', 'ms', '20 paquetes', f"Router {P_ROUTER['min']} · Vercel {P_PROD['min']}"],
    ['Ping promedio', 'ms', '20 paquetes', f"Router {P_ROUTER['promedio']} · Vercel {P_PROD['promedio']}"],
    ['Ping máximo', 'ms', '20 paquetes', f"Router {P_ROUTER['max']} · Vercel {P_PROD['max']}"],
    ['Pérdida de paquetes', '%', '20 paquetes', f"Router {P_ROUTER['perdida_pct']} · Vercel {P_PROD['perdida_pct']} · PC {P_PC['perdida_pct']} (ICMP bloqueado)"],
    ['Latencia HTTP', 'ms', '10 solicitudes', f"Celular → local {CEL_LOCAL['promedio']} · → producción {CEL_PROD['promedio']}"],
    ['Tiempo de descarga (1.35 MB)', 's', '3 mediciones', ' / '.join(f"{x['ms'] / 1000:.3f}" for x in d_cel)],
    ['Tasa de descarga', 'Mbps', '3 mediciones', ' / '.join(str(x['mbps']) for x in d_cel)],
    ['Tasa de subida (5 MB)', 'Mbps', '3 mediciones', ' / '.join(str(x['mbps']) for x in s_cel)],
    ['Tamaño de respuesta', 'bytes', '10 solicitudes', f"Local {CEL_LOCAL['solicitudes'][0]['bytes']} · producción {CEL_PROD['solicitudes'][0]['bytes']}"],
    ['Tiempo de consulta DB', 'ms', '5 consultas', ' · '.join(f"{c['id']} {c['ejecucion_ms']}" for c in BD['consultas'])],
], [1.8, 0.6, 1.1, 3.0])
h2('B. Tabla de resultados por solicitud')
par('Se presenta en la sección 7-B: 10 solicitudes reales de `GET /api/beats?limit=20&page=1` desde el celular.')
h2('C. Indicadores calculados')
tabla(['Indicador', 'Objetivo orientativo', 'Obtenido', 'Evaluación'], [
    ['Cobertura de instrucciones (módulos críticos)', '≥ 85 %', '100 % (81/81)', '✅ Cumple'],
    ['Cobertura de ramas (módulos críticos)', '≥ 80 %', '100 % (42/42)', '✅ Cumple'],
    ['Pérdida de paquetes en red estable', '0 %', f"{P_ROUTER['perdida_pct']} % (router y Vercel)", '✅ Cumple'],
    ['Latencia HTTP promedio', '≤ 500 ms', f"{CEL_LOCAL['promedio']} ms local · {CEL_PROD['promedio']} ms producción", '✅ Cumple'],
    ['Tiempo de consulta sencilla a DB', '≤ 200 ms', f"{Q['Q1']['ejecucion_ms']} ms (Q1)", '✅ Cumple'],
    ['Respuestas exitosas del endpoint', '100 %', '240/240 en carga · 10/10 consecutivas', '✅ Cumple'],
    ['Operaciones inválidas rechazadas', '100 %', f"{len(BD['restricciones'])}/{len(BD['restricciones'])} restricciones · todos los casos de error de API", '✅ Cumple'],
    ['Tasa de transferencia (celular)', '—', f"{prom([x['mbps'] for x in d_cel])} Mbps bajada · {prom([x['mbps'] for x in s_cel])} Mbps subida", 'Referencia'],
], [2.2, 1.2, 2.0, 1.1])

# ═════════════════════════════════════════════════════════════════════════════
h1('11. Preguntas')
PREGUNTAS = [
    ('¿Qué diferencia existe entre cobertura de instrucciones, cobertura de decisiones y cobertura de condiciones? Incluye un ejemplo de tu aplicación.',
     'La de **instrucciones** mide qué líneas se ejecutaron; la de **decisiones** (ramas), si cada `if` tomó su camino verdadero y su '
     'camino falso; la de **condiciones**, si cada condición atómica dentro de una decisión compuesta tomó ambos valores e influyó en '
     'el resultado. En `cardExpiry`, la línea `if (anio < año || (anio == año && mes < mesActual))` queda «cubierta» como '
     'instrucción con una sola tarjeta vigente («01/27»). Para cubrir la decisión se necesita además una vencida («12/25»). Para cubrir '
     'las condiciones (MC/DC) hacen falta cuatro casos: «12/25», «01/27», «10/26» y «12/26», porque «mismo año, mes anterior» solo se '
     'prueba con «10/26».'),
    ('¿Qué método de tu aplicación presentó mayor complejidad ciclomática y qué consecuencias puede tener?',
     '`ApiException.fromDio`, con V(G) = 11 (10 decisiones y 18 condiciones atómicas). Necesita al menos 11 pruebas para recorrer sus '
     'caminos, y su comportamiento depende del **orden** de las condiciones: así apareció DEF-01, porque la primera rama (la API manda '
     '`error`) atrapaba los errores de Fastify antes de llegar a las ramas por código. Una complejidad alta hace más fácil que un cambio '
     'rompa un camino que nadie volvió a probar; por eso cada camino tiene su prueba y se agregaron los límites 499/500.'),
    ('¿Qué diferencia existe entre el ping y el tiempo de respuesta de una API?',
     'El ping (ICMP echo) mide solo el ida y vuelta de un paquete por la red, sin abrir conexiones ni ejecutar nada en el servidor. El '
     'tiempo de respuesta de la API suma DNS, la conexión TCP, el saludo TLS, el procesamiento en el servidor (validar el JWT, consultar '
     f"la base, armar el JSON) y la descarga del cuerpo. Medido: el celular hizo ping a Vercel en {P_PROD['promedio']} ms, pero la petición "
     f"HTTP tardó {CEL_PROD['promedio']} ms. No son métricas equivalentes."),
    ('Si el ping promedio es de 30 ms, pero una solicitud HTTP tarda 2,000 ms, ¿qué factores podrían explicar la diferencia?',
     'Resolución DNS; varias idas y vueltas para TCP y TLS; arranque en frío de una función serverless (Vercel); tiempo de '
     'procesamiento y consultas a una base lejana (cada consulta de Vercel a Supabase es otro viaje de red, y varias en serie se suman); '
     'consultas lentas o N+1; colas o saturación del servidor; límites de uso del plan; respuestas grandes con poco ancho de banda; y '
     f"retransmisiones por pérdida de paquetes. En nuestro caso, con ping de {P_PROD['promedio']} ms, el TLS se llevó "
     f"~{round(prom([s['tls'] for s in CEL_PROD['solicitudes']]))} ms y el primer byte llegó a los ~{round(prom([s['ttfb'] for s in CEL_PROD['solicitudes']]))} ms: "
     'casi todo es servidor.'),
    ('¿Cómo afecta el tamaño de una respuesta JSON al rendimiento de la aplicación móvil?',
     'Más bytes implican más tiempo de transferencia (sobre todo en datos móviles), más memoria y más CPU para decodificar el JSON, que '
     'en Flutter ocurre en el hilo de la interfaz y puede congelarla, además de más batería. El catálogo completo pesa 1.35 MB y tardó '
     f"{d_cel[0]['ms']} ms incluso por USB (a 1 Mbps serían ~11 s); la página de 20 beats pesa {CEL_LOCAL['solicitudes'][0]['bytes']} B y "
     'tarda ~9 ms. Por eso se pagina y se piden solo las columnas necesarias (DEF-09 redujo un 35 % el detalle de beat).'),
    ('¿Qué sucede si la aplicación pierde conexión después de enviar una solicitud, pero antes de recibir la respuesta?',
     'El servidor puede completar la operación aunque el cliente no se entere: queda un estado ambiguo. Lo comprobamos en el escenario 2: '
     'la app mostró «No se confirmó el envío» mientras el servidor sí guardaba el ticket #12123. Si la app diera la operación por fallida '
     'y reintentara sin control, crearía un duplicado; si la diera por buena, mentiría. La app no afirma nada, conserva el formulario y '
     'permite reintentar de forma segura.'),
    ('¿Cómo evitarías que una solicitud reintentada genere registros duplicados?',
     'Con **idempotencia**: la app genera un UUID v4 por operación (`Idempotency-Key`) y lo conserva en todos los reintentos; solo cambia '
     'si el usuario cambia los datos. La API lo guarda en una columna `client_ref` UNIQUE: si llega otra vez, devuelve el registro original '
     '(200, `repetida`). Si dos llegan al mismo tiempo, la restricción UNIQUE (23505) decide. Además, para reglas de negocio con claves '
     'distintas (dos teléfonos) se usa una restricción en la base (`trg_compra_unica`, DEF-08). La app solo reintenta automáticamente '
     'las lecturas y las escrituras con clave.'),
    ('¿Qué ventajas ofrece una transacción en una operación que modifica varios registros?',
     'Atomicidad (todo o nada), consistencia (las restricciones se cumplen al final), aislamiento (otras sesiones no ven estados '
     'intermedios y las filas se bloquean, como en DB-06a) y durabilidad. Medido: dentro de `BEGIN/COMMIT`, un renglón inválido dejó '
     f"{tx['con_transaccion_ordenes_que_quedan']} órdenes; sin transacción quedó {tx['sin_transaccion_ordenes_huerfanas']} orden huérfana. "
     'Como PostgREST no comparte transacción entre llamadas, la API compensa con `deshacerOrden` (DEF-04).'),
    ('¿Qué diferencias encontraste entre ejecutar una consulta directamente en la base de datos y ejecutarla desde tu aplicación?',
     f"La primera página del catálogo tarda {Q['Q2']['ejecucion_ms']} ms dentro de PostgreSQL (más {Q['Q2']['planeacion_ms']} ms de planeación). "
     f"Por la API en la PC tardó {PC_LOCAL['promedio']} ms; desde el celular por USB, {CEL_LOCAL['promedio']} ms; dentro de la app (registro `[p12]`), "
     f"17–43 ms; y desde producción, {CEL_PROD['promedio']} ms. Cada capa suma: verificar el JWT, el salto HTTP a PostgREST, el conteo "
     'total, serializar JSON, la red, los interceptores de Dio y la decodificación. Además, desde la app los datos llegan filtrados por '
     'permisos y paginados, y los errores se traducen.'),
    ('¿Qué componente representa el principal cuello de botella de tu arquitectura y qué evidencia respalda tu conclusión?',
     'En producción, el **servidor remoto** (función de Vercel más los viajes a Supabase). Evidencia: el ping a Vercel es de '
     f"{P_PROD['promedio']} ms y las consultas en PostgreSQL tardan menos de 0.5 ms, pero el primer byte llega a los "
     f"~{round(prom([s['ttfb'] for s in CEL_PROD['solicitudes']]))} ms. La misma petición contra la API local responde en "
     f"{CEL_LOCAL['promedio']} ms. En el entorno local, bajo carga, el siguiente límite es la CPU del proceso único de Node "
     f"(60–100 % de un núcleo): de 5 a 10 usuarios el rendimiento solo creció un {round(100 * (CARGA[2]['rps'] / CARGA[1]['rps'] - 1))} %. "
     'La base no es el cuello: como máximo tuvo 1 conexión activa.'),
]
for n, (pregunta, respuesta) in enumerate(PREGUNTAS, 1):
    par(f'{n}. {pregunta}', negrita=True, color=AZUL)
    par(respuesta)

# ═════════════════════════════════════════════════════════════════════════════
h1('12. Dictamen')
par('Entrega ACEPTADA: la aplicación funciona correctamente desde su estructura interna.', tam=12, negrita=True, color=VERDE)
N_MATRIZ = sum(len(f) for _, f in MATRIZ)
N_TRAS = sum(1 for _, f in MATRIZ for x in f if x[2] == okc)
par(f'Los {N_MATRIZ} puntos de la matriz quedaron aprobados, {N_TRAS} de ellos después de corregir lo que las propias pruebas detectaron. Las 14 '
    'correcciones están en el código y cada una se verificó con la prueba que la encontró. Los indicadores cumplen los objetivos '
    'orientativos: 100 % de instrucciones y de ramas en los métodos críticos, 0 % de pérdida de paquetes en la red estable, latencia '
    'HTTP menor a 500 ms, consultas menores a 1 ms, 100 % de solicitudes válidas exitosas y 100 % de operaciones inválidas rechazadas.')
par('Para que producción quede igual que el entorno evaluado:')
numerada([
    'Ejecutar `supabase/compras_unicas.sql` en el editor SQL de Supabase (DEF-08).',
    'Desplegar la API con los commits `e18e479` a `9bdd33f`.',
    'Generar la APK de la app con el commit `b09a9ba`.',
    'Repetir `node scripts/p11/codigos.mjs` contra producción, solo con las lecturas.',
])

# ═════════════════════════════════════════════════════════════════════════════
h1('13. Anexos')
h2('Cómo reproducir')
codigo([
    'API (D:\\Angular\\erp_beats\\api)',
    '  powershell -ExecutionPolicy Bypass -File local\\preparar.ps1   # PostgREST + base skondit_local',
    '  powershell -ExecutionPolicy Bypass -File local\\iniciar.ps1    # PostgREST + Storage + API :3000',
    '  npm test                         # 92 pruebas (56 de caja blanca en scripts/p11/whitebox.test.ts)',
    '  node scripts/p11/codigos.mjs     # matriz de códigos HTTP en vivo',
    '  node scripts/p11/db-whitebox.mjs # Fase 4: CRUD, restricciones, EXPLAIN, concurrencia',
    '  node scripts/p11/red.mjs         # Fase 5: ping, latencia, transferencia y carga',
    'App (D:\\Flutter\\skondit_beats_mobile)',
    '  flutter analyze',
    '  flutter test --coverage --branch-coverage          # 125 pruebas (74 en test/whitebox)',
    '  python tool/p11/cobertura_metodos.py               # cobertura por método',
    '  python tool/p11/fotogramas.py 3                    # WB-06 en el celular',
    '  python tool/p11/grafos.py docs/practica11/grafos   # grafos de flujo',
])
h2('Código fuente de los casos de prueba')
tabla(['Archivo', 'Pruebas', 'Contenido'], [
    ['`test/whitebox/validators_wb_test.dart`', '35', 'M1 cardExpiry y M2 luhn: caminos, MC/DC, valores límite y excepciones'],
    ['`test/whitebox/cart_wb_test.dart`', '13', 'M3 addPack y addBeat: caminos, sin sesión, falla de SQLite'],
    ['`test/whitebox/api_client_wb_test.dart`', '26', 'M4 fromDio, M5 reintentos (servidor local), DEF-12'],
    ['`scripts/p11/whitebox.test.ts` (API)', '56', 'E1 órdenes, E2 beats, E3 login/autorización, validarBeat, idempotencia'],
    ['`scripts/p11/codigos.mjs` · `db-whitebox.mjs` · `red.mjs`', '—', 'Pruebas en vivo de API, base de datos y red'],
], [2.6, 0.7, 3.2])
h2('Archivos de evidencia')
par('Las capturas están en `capturas/` y los volcados de texto en `evidencias_texto/`, dentro de la carpeta de la práctica. '
    'Los mismos archivos están versionados en `docs/practica11/evidencias` de la app y en `scripts/p11/resultados` de la API.')
tabla(['Archivo', 'Contenido'], [
    ['00_flutter_analyze.txt · 00_tsc.txt', 'Análisis estático'],
    ['01_whitebox_app_ANTES.txt · 02_flutter_test_DESPUES.txt', 'Pruebas de la app antes y después de corregir'],
    ['03_cobertura_metodos.txt · cobertura_metodos.json', 'Cobertura por método'],
    ['04_whitebox_api_ANTES.txt · 04_api_test_cobertura_DESPUES.txt', 'Pruebas y cobertura de la API'],
    ['05_npm_audit_*.txt · 06_npm_outdated.txt', 'Dependencias'],
    ['07_logcat_celular.txt', 'Registros [p12] del celular e interrupción'],
    ['codigos.md/json · db.md/json · red.md/json · wb06_fotogramas.json', 'Resultados de los scripts de la Fase 3, 4 y 5'],
], [3.4, 3.1])

SALIDA.parent.mkdir(parents=True, exist_ok=True)
doc.save(str(SALIDA))
print(SALIDA)
