"""Práctica 11 · Grafos de flujo de control (CFG) de los métodos críticos.

Cada grafo se describe a mano a partir del código (nodo = instrucción o decisión,
arista = posible transferencia de control) y se dibuja como SVG; luego Chrome
headless lo convierte en PNG para el informe.

Uso:  python tool/p11/grafos.py <carpeta_salida>
"""
import subprocess
import sys
from pathlib import Path

CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
W_NODO, H_NODO, SEP_X, SEP_Y = 250, 44, 290, 78

# Cada grafo: nodos {id: (fila, columna, texto, tipo)} y aristas (origen, destino, etiqueta)
# tipo: 'd' decisión (rombo), 'n' instrucción, 'r' retorno, 'e' fin
GRAFOS = {
    'M1_cardExpiry': {
        'titulo': 'M1 · Validators.cardExpiry(v, now)  —  V(G) = 5',
        'nodos': {
            '1': (0, 1, '1  m = regex.firstMatch(v ?? "")', 'n'),
            '2': (1, 1, '2  ¿m == null?', 'd'),
            '3': (1, 0, '3  "Usa el formato MM/AA"', 'r'),
            '4': (2, 1, '4  mes, anio = int.parse(...)', 'n'),
            '5': (3, 1, '5  ¿mes < 1 || mes > 12?', 'd'),
            '6': (3, 0, '6  "Mes no válido"', 'r'),
            '7': (4, 1, '7  hoy = now ?? DateTime.now()', 'n'),
            '8': (5, 1, '8  ¿anio < año || (anio == año && mes < mesActual)?', 'd'),
            '9': (5, 0, '9  "La tarjeta está vencida"', 'r'),
            '10': (6, 1, '10  ¿anio > año + 20?', 'd'),
            '11': (6, 0, '11  "Fecha no válida"', 'r'),
            '12': (7, 1, '12  return null (válida)', 'r'),
            'E': (8, 1, 'Fin', 'e'),
        },
        'aristas': [('1', '2', ''), ('2', '3', 'V'), ('2', '4', 'F'), ('4', '5', ''), ('5', '6', 'V'), ('5', '7', 'F'),
                    ('7', '8', ''), ('8', '9', 'V'), ('8', '10', 'F'), ('10', '11', 'V'), ('10', '12', 'F'),
                    ('3', 'E', ''), ('6', 'E', ''), ('9', 'E', ''), ('11', 'E', ''), ('12', 'E', '')],
    },
    'M3_addPack': {
        'titulo': 'M3 · CartController.addPack(pack, owned)  —  V(G) = 7',
        'nodos': {
            '1': (0, 1, '1  ¿_userId == null?', 'd'),
            '2': (0, 0, '2  "Inicia sesión…"', 'r'),
            '3': (1, 1, '3  ¿contains(pack)?', 'd'),
            '4': (1, 0, '4  "Ya está en tu carrito"', 'r'),
            '5': (2, 1, '5  yaTiene = beats comprados', 'n'),
            '6': (3, 1, '6  ¿yaTiene > 0?', 'd'),
            '7': (3, 2, '7  ¿yaTiene == 1?', 'd'),
            '7a': (3, 3, '7a  "Ya tienes 1 beat"', 'r'),
            '7b': (4, 2, '7b  "Ya tienes N beats"', 'r'),
            '8': (4, 1, '8  repetidos = sueltos del pack', 'n'),
            '9': (5, 1, '9  ¿quedan repetidos? (for)', 'd'),
            '10': (5, 0, '10  await remove(r)', 'n'),
            '11': (6, 1, '11  await _insert(pack)', 'n'),
            '12': (7, 1, '12  ¿repetidos.isEmpty?', 'd'),
            '13': (8, 0, '13  "se agregó"', 'r'),
            '14': (8, 2, '14  "se agregó. Quitamos N"', 'r'),
            'E': (9, 1, 'Fin', 'e'),
        },
        'aristas': [('1', '2', 'V'), ('1', '3', 'F'), ('3', '4', 'V'), ('3', '5', 'F'), ('5', '6', ''), ('6', '7', 'V'),
                    ('6', '8', 'F'), ('7', '7a', 'V'), ('7', '7b', 'F'), ('8', '9', ''), ('9', '10', 'V'), ('10', '9', ''),
                    ('9', '11', 'F'), ('11', '12', ''), ('12', '13', 'V'), ('12', '14', 'F'), ('13', 'E', ''), ('14', 'E', ''),
                    ('2', 'E', ''), ('4', 'E', ''), ('7a', 'E', ''), ('7b', 'E', '')],
    },
    'M4_fromDio': {
        'titulo': 'M4 · ApiException.fromDio(e)  —  V(G) = 11',
        'nodos': {
            '1': (0, 1, '1  data, status, deFastify', 'n'),
            '2': (1, 1, '2  ¿Map && error is String && !deFastify?', 'd'),
            '3': (1, 0, '3  ApiException(data.error)', 'r'),
            '4': (2, 1, '4  switch (e.type)', 'd'),
            '5': (2, 0, '5  timeout → sinRed', 'r'),
            '6': (3, 0, '6  connectionError → sinRed', 'r'),
            '7': (4, 0, '7  cancel', 'r'),
            '8': (3, 1, '8  ¿status == 401?', 'd'),
            '9': (3, 2, '9  "Tu sesión expiró"', 'r'),
            '10': (4, 1, '10  ¿status == 403?', 'd'),
            '11': (4, 2, '11  "No tienes permiso"', 'r'),
            '12': (5, 1, '12  ¿status == 400 || 422?', 'd'),
            '13': (5, 2, '13  "Revisa los datos"', 'r'),
            '14': (6, 1, '14  ¿status == 404?', 'd'),
            '15': (6, 2, '15  "No se encontró"', 'r'),
            '16': (7, 1, '16  ¿status != null && ≥ 500?', 'd'),
            '17': (7, 2, '17  "El servidor tuvo un problema"', 'r'),
            '18': (8, 1, '18  ¿status == null?', 'd'),
            '19': (8, 2, '19  "Se perdió la conexión"', 'r'),
            '20': (9, 1, '20  "Error inesperado (código)"', 'r'),
            'E': (10, 1, 'Fin', 'e'),
        },
        'aristas': [('1', '2', ''), ('2', '3', 'V'), ('2', '4', 'F'), ('4', '5', 'timeout'), ('4', '6', 'conexión'),
                    ('4', '7', 'cancel'), ('4', '8', 'otro'), ('8', '9', 'V'), ('8', '10', 'F'), ('10', '11', 'V'),
                    ('10', '12', 'F'), ('12', '13', 'V'), ('12', '14', 'F'), ('14', '15', 'V'), ('14', '16', 'F'),
                    ('16', '17', 'V'), ('16', '18', 'F'), ('18', '19', 'V'), ('18', '20', 'F'), ('20', 'E', ''),
                    ('3', 'E', ''), ('5', 'E', ''), ('6', 'E', ''), ('7', 'E', ''), ('9', 'E', ''), ('11', 'E', ''),
                    ('13', 'E', ''), ('15', 'E', ''), ('17', 'E', ''), ('19', 'E', '')],
    },
    'E1_postOrders': {
        'titulo': 'E1 · API POST /api/orders (beats sueltos)  —  V(G) = 28 − 20 + 2 = 10',
        'nodos': {
            '1': (0, 1, '1  preHandler: ¿token válido?', 'd'),
            '2': (0, 0, '2  401', 'r'),
            '3': (1, 1, '3  ¿esquema válido?', 'd'),
            '4': (1, 0, '4  400 FST_ERR_VALIDATION', 'r'),
            '5': (2, 1, '5  ¿Idempotency-Key con orden previa?', 'd'),
            '6': (2, 2, '6  200 repetida', 'r'),
            '7': (3, 1, '7  ¿packId? / ¿beats vacío?', 'd'),
            '8': (3, 0, '8  comprarPaquete / 400', 'r'),
            '9': (4, 1, '9  SELECT beats; ¿error ≠ 22P02?', 'd'),
            '10': (4, 0, '10  500', 'r'),
            '11': (5, 1, '11  ¿encontrados < pedidos?', 'd'),
            '12': (5, 0, '12  422', 'r'),
            '13': (6, 1, '13  ¿ya los compró?', 'd'),
            '14': (6, 0, '14  409', 'r'),
            '15': (7, 1, '15  INSERT orders; ¿error?', 'd'),
            '16': (7, 2, '16  23505 → 200 / otro → 500', 'r'),
            '17': (8, 1, '17  INSERT order_items; ¿error?', 'd'),
            '18': (8, 2, '18  deshacerOrden → 409 / 500', 'r'),
            '19': (9, 1, '19  201 { order }', 'r'),
            'E': (10, 1, 'Fin', 'e'),
        },
        'aristas': [('1', '2', 'F'), ('1', '3', 'V'), ('3', '4', 'F'), ('3', '5', 'V'), ('5', '6', 'V'), ('5', '7', 'F'),
                    ('7', '8', 'V'), ('7', '9', 'F'), ('9', '10', 'V'), ('9', '11', 'F'), ('11', '12', 'V'), ('11', '13', 'F'),
                    ('13', '14', 'V'), ('13', '15', 'F'), ('15', '16', 'V'), ('15', '17', 'F'), ('17', '18', 'V'),
                    ('17', '19', 'F'), ('19', 'E', ''), ('2', 'E', ''), ('4', 'E', ''), ('6', 'E', ''), ('8', 'E', ''),
                    ('10', 'E', ''), ('12', 'E', ''), ('14', 'E', ''), ('16', 'E', ''), ('18', 'E', '')],
    },
}

COLOR = {'d': ('#FFF4D6', '#B7791F'), 'n': ('#E8EEF5', '#1F3A5F'), 'r': ('#E6F4EA', '#2F7D4A'), 'e': ('#1F3A5F', '#1F3A5F')}


MARGEN = 60  # espacio para los rieles laterales de retorno


def centro(fila, col):
    return MARGEN + col * SEP_X + W_NODO / 2, 70 + fila * SEP_Y + H_NODO / 2


def medidas(tipo):
    """Mitad del ancho y del alto de la figura del nodo."""
    if tipo == 'd':
        return W_NODO / 2 + 6, H_NODO / 2 + 6
    if tipo == 'e':
        return 40, 18
    return W_NODO / 2, H_NODO / 2


def svg(g):
    nodos = g['nodos']
    filas = max(f for f, *_ in nodos.values()) + 1
    cols = max(c for _, c, *_ in nodos.values()) + 1
    ancho, alto = 2 * MARGEN + (cols - 1) * SEP_X + W_NODO, 100 + filas * SEP_Y
    riel_izq, riel_der = MARGEN / 2 - 6, ancho - MARGEN / 2 + 6
    hueco = SEP_X - W_NODO
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{ancho}" height="{alto}" font-family="Calibri, Arial" font-size="13">',
         '<defs><marker id="f" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
         '<path d="M0,0 L10,5 L0,10 z" fill="#555"/></marker>'
         '<marker id="g" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
         '<path d="M0,0 L10,5 L0,10 z" fill="#9AA5B1"/></marker></defs>',
         '<rect width="100%" height="100%" fill="white"/>',
         f'<text x="{MARGEN}" y="34" font-size="17" font-weight="bold" fill="#1F3A5F">{g["titulo"]}</text>']
    orden = {(a, b): i for i, (a, b, _) in enumerate(g['aristas'])}
    pares = set(orden)
    for a, b, etq in g['aristas']:
        fa, ca, _, ta = nodos[a]
        fb, cb, _, tb = nodos[b]
        x1, y1 = centro(fa, ca)
        x2, y2 = centro(fb, cb)
        wa, ha = medidas(ta)
        wb, hb = medidas(tb)
        gris = False
        if b == 'E' and ca != cb:
            # Retorno al fin por un riel lateral, sin cruzar otros nodos.
            gris = True
            if ca < cb:
                camino = f'M{x1 - wa},{y1} L{riel_izq},{y1} L{riel_izq},{y2} L{x2 - wb},{y2}'
            else:
                camino = f'M{x1 + wa},{y1} L{riel_der},{y1} L{riel_der},{y2} L{x2 + wb},{y2}'
            lx = ly = None
        elif fa == fb:
            der = cb > ca
            xa, xb = x1 + (wa if der else -wa), x2 + (-wb if der else wb)
            if (b, a) in pares and orden[(b, a)] < orden[(a, b)]:
                # Regreso de un ciclo en la misma fila: curva por debajo.
                camino = f'M{x1},{y1 + ha} C{x1},{y1 + ha + 34} {x2},{y2 + hb + 34} {x2},{y2 + hb}'
                lx, ly = (x1 + x2) / 2, y1 + ha + 30
            else:
                camino = f'M{xa},{y1} L{xb},{y2}'
                lx, ly = xa + (10 if der else -24), y1 - 7
        elif fb > fa and ca == cb:
            camino = f'M{x1},{y1 + ha} L{x2},{y2 - hb}'
            lx, ly = x1 + 8, y1 + ha + 16
        elif fb > fa:
            # Baja a otra columna por el carril entre columnas y entra por el costado.
            if cb < ca:
                carril = centro(fb, cb)[0] + W_NODO / 2 + hueco / 2
                camino = f'M{x1 - wa},{y1} L{carril},{y1} L{carril},{y2} L{x2 + wb},{y2}'
                lx, ly = carril + 5, y2 + 15
            else:
                carril = centro(fb, cb)[0] - W_NODO / 2 - hueco / 2
                camino = f'M{x1 + wa},{y1} L{carril},{y1} L{carril},{y2} L{x2 - wb},{y2}'
                lx, ly = carril - 30, y2 - 7
        else:
            camino = f'M{x1 + wa},{y1} C{x1 + wa + 40},{y1} {x2 + wb + 40},{y2} {x2 + wb},{y2}'
            lx, ly = x1 + wa + 8, y1 - 7
        color_linea, marca = ('#9AA5B1', 'g') if gris else ('#555', 'f')
        s.append(f'<path d="{camino}" fill="none" stroke="{color_linea}" stroke-width="1.4" marker-end="url(#{marca})"/>')
        if etq and lx is not None:
            color = '#2F7D4A' if etq == 'V' else '#A61B1B' if etq == 'F' else '#B7791F'
            s.append(f'<text x="{lx}" y="{ly}" fill="{color}" font-weight="bold" font-size="12">{etq}</text>')
    for nid, (fila, col, texto, tipo) in nodos.items():
        x, y = centro(fila, col)
        relleno, borde = COLOR[tipo]
        w, h = medidas(tipo)
        if tipo == 'd':
            s.append(f'<polygon points="{x},{y - h} {x + w},{y} {x},{y + h} {x - w},{y}" fill="{relleno}" stroke="{borde}" stroke-width="1.6"/>')
        elif tipo == 'e':
            s.append(f'<ellipse cx="{x}" cy="{y}" rx="{w}" ry="{h}" fill="{relleno}"/>')
        else:
            s.append(f'<rect x="{x - w}" y="{y - h}" width="{2 * w}" height="{2 * h}" rx="8" fill="{relleno}" stroke="{borde}" stroke-width="1.4"/>')
        color = 'white' if tipo == 'e' else '#1A1A1A'
        tam = 11.5 if len(texto) > 34 else 13
        s.append(f'<text x="{x}" y="{y + 4.5}" text-anchor="middle" fill="{color}" font-size="{tam}">{texto.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")}</text>')
    s.append('</svg>')
    return '\n'.join(s), ancho, alto


def main():
    salida = Path(sys.argv[1] if len(sys.argv) > 1 else 'docs/practica11/grafos')
    salida.mkdir(parents=True, exist_ok=True)
    for nombre, g in GRAFOS.items():
        contenido, ancho, alto = svg(g)
        (salida / f'{nombre}.svg').write_text(contenido, encoding='utf8')
        html = salida / f'{nombre}.html'
        html.write_text(f'<!doctype html><meta charset="utf-8"><style>body{{margin:0;background:white}}</style>{contenido}', encoding='utf8')
        png = (salida / f'{nombre}.png').resolve()
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2',
                        f'--screenshot={png}', f'--window-size={ancho},{alto}', html.resolve().as_uri()],
                       check=True, capture_output=True)
        html.unlink()
        print(png)


if __name__ == '__main__':
    main()
