# Práctica 12 · Optimización, pruebas de estrés y resiliencia — SkonditBeats Mobile

Código: app Flutter (`D:\Flutter\skondit_beats_mobile`) y API Fastify (`D:\Angular\erp_beats\api`).

## Cómo reproducir todo (sin Supabase ni internet)

| Paso | Comando (desde `erp_beats\api`) | Qué hace |
|---|---|---|
| 1 | `powershell -ExecutionPolicy Bypass -File local\preparar.ps1` | Descarga PostgREST una vez y crea la base `skondit_local` en el PostgreSQL de la PC con datos de prueba fijos |
| 2 | `powershell -ExecutionPolicy Bypass -File local\iniciar.ps1` | Levanta PostgREST + "Supabase local" + API en `:3000` y hace `adb reverse` al celular |
| 3 | `npm run p12:db` | Fase 4: consultas antes/después, índices y concurrencia → `scripts\p12\resultados\db.md` |
| 4 | `npm run p12:carga -- --etiqueta despues` | Fase 3: prueba de estrés por escalones → `scripts\p12\resultados\carga-despues.md` |
| 5 | `npm test` | Pruebas de caja blanca de la API (29, sin red, ~1 s) |
| 6 | `flutter test` (en la app) | Pruebas de la app (47, incluye resiliencia contra un servidor local) |

**¿Por qué no Supabase para las pruebas?** Las pruebas de caja blanca no deben depender de un servicio
externo: con Supabase el resultado cambia según el Wi-Fi (latencia de 150–400 ms, cortes, límites del
plan gratuito) y cada corrida ensucia la base real. Por eso:

- Las **pruebas de caja blanca** (`npm test`, `flutter test`) interceptan la red: la API responde con un
  `fetch` falso y la app habla con un servidor HTTP dentro de la misma prueba en `127.0.0.1`. Pasan igual
  en la universidad, en casa o sin internet.
- Las **pruebas de carga y de base de datos** usan el mismo motor que Supabase (PostgreSQL 16 +
  PostgREST, que es lo que expone Supabase en `/rest/v1`) en la PC. Solo cambia `SUPABASE_URL`
  (`local\local.env`); el código de la API es el mismo. `local\gateway.mjs` emula Storage (URL firmadas,
  subida reanudable TUS y descarga con Range) y puede simular cortes (`FALLA_SUBIDA_BYTES`) y latencia
  (`LATENCIA_MS`).
- El celular llega a la PC por el cable USB (`adb reverse`), no por el Wi-Fi: la red de la escuela no
  importa.

Datos de prueba: 5 000 beats, 2 003 usuarios, 20 000 órdenes, 40 001 renglones, 12 000 tickets y
30 000 respuestas. Cuentas: `admin@local.test` y `cliente@local.test`, contraseña `Prueba-12345!`.

## Fase 1 · Problemas e hipótesis

| # | Problema | Dónde | Hipótesis técnica |
|---|---|---|---|
| 1 | Método costoso | `GET /api/contact` (bandeja de mensajes) | Devuelve **todos** los tickets con el texto de **todas** sus respuestas (11.7 MB con 12 000 tickets). El tiempo y el tamaño crecen linealmente con el historial; con volumen real la pantalla se vuelve inutilizable. |
| 2 | Endpoint con latencia | `GET /api/beats` | Hace 3 consultas por petición (lista, conteo y géneros) aunque el conteo y los géneros casi nunca cambian, y regresa el catálogo completo (1.3 MB) aunque la pantalla muestra 8–20 beats. |
| 3 | Consulta optimizable | `beats where activo order by created_at desc` | No hay índice que cubra el filtro + el orden: recorrido secuencial y ordenamiento en memoria en cada petición. |
| 4 | Conectividad | Toda la app | Sin reintentos ni detección de red; una escritura repetida tras un corte podía duplicar un pago o un ticket, y una subida cortada empezaba de cero. |
| 5 | Memoria/CPU | Tienda e inicio | Decodificar 1.3 MB de JSON y construir 4 800 objetos `Beat` en cada carga, y el inicio pedía el catálogo completo para mostrar 8 tarjetas. |

## Fase 2 · Profiling en el celular

- `flutter run --profile` + Flutter DevTools (pestañas *Performance* y *Memory*).
- `tool\p12\perfil_android.ps1 -Etiqueta antes|despues` muestrea cada segundo CPU (de `/proc`) y RAM
  (`dumpsys meminfo`: PSS, Java, Native, Gráficos) a un CSV, mientras se hacen las 6 pruebas obligatorias.
- En debug/profile cada petición se registra en `flutter logs` como
  `[p12] GET /beats 200 · 84 ms · 5.4 KB · intento 1` (PER-03).

| Prueba obligatoria | Cómo se hace en la app |
|---|---|
| Consulta repetida | Tienda → jalar para actualizar 10 veces / cambiar de género |
| Escritura | Contacto → crear ticket; o pagar el carrito |
| Navegación | Inicio ↔ Tienda ↔ Paquetes ↔ Carrito |
| Procesamiento de datos | Tienda con scroll hasta el final (paginación) / filtros de BPM y precio |
| CPU y memoria | CSV de `perfil_android.ps1` + DevTools |
| Bloqueos de UI | DevTools → *Performance* → cuadros > 16 ms (jank) |

## Fase 3 · Prueba de estrés de la API

Script reproducible: `scripts\p12\carga.mjs` (sin dependencias). Sube por escalones
1 → 10 → 25 → 50 → 100 → 200 usuarios concurrentes, 10 s por escalón, y reporta RPS, promedio, P50, P90,
P95, máximo, % de errores, códigos HTTP, KB por respuesta y la latencia de `/health` durante la carga
(comportamiento del servidor). Detecta el punto de saturación (el escalón donde más usuarios ya no
aumentan el RPS).

- Lectura: `GET /api/beats?limit=20&page=1` (después) vs `GET /api/beats` en `scripts\p12\servidor-antes.ts`
  con la ruta original (antes), contra la misma base.
- Escritura: `POST /api/contact` (abre un ticket, con `Idempotency-Key`).

Resultados (2026-11-12): `scripts\p12\resultados\carga-antes.md` y `carga-despues.md`. Lectura con 200 usuarios:
antes 51 RPS, prom. 3 488 ms, P95 4 642 ms; después 1 270 RPS, prom. 154 ms, P95 215 ms; 0 % de errores en ambas.
Saturación: antes ~10 usuarios a 49 RPS; después ~10 usuarios a 1 681 RPS. Escritura (`POST /api/contact`): máx. 666 RPS.

## Fase 4 · Base de datos (medido)

PostgreSQL 16.11 local, mediana de 7 ejecuciones de `EXPLAIN ANALYZE`.

| Prueba | Consulta | Antes ms | Filas | KB | Después ms | Filas | KB |
|---|---|---:|---:|---:|---:|---:|---:|
| DB-01 | Beat por identificador | 0.06 | 1 | 0.4 | 0.10 | 1 | 0.4 |
| DB-02 | Conjunto pequeño (primera pantalla) | 2.50 | 4 800 | 1 332.9 | 0.11 | 20 | 5.5 |
| DB-03 | Conjunto grande (catálogo completo) | 2.34 | 4 800 | 1 332.9 | 1.26 | 4 800 | 1 332.9 |
| DB-04 | Con filtros (género + BPM + precio) | 0.50 | 70 | 19.4 | 0.34 | 20 | 5.5 |
| **DB-05** | **Bandeja de tickets (consulta crítica)** | **140.36** | **12 000** | **11 771** | **0.44** | **20** | **9.2** |
| DB-06 | Tickets de un cliente | 2.58 | 6 | 5.9 | 0.35 | 6 | 2.8 |
| DB-07 | Compras de un cliente | 0.38 | 18 | 3.2 | 0.36 | 18 | 3.2 |

DB-01 sube 0.04 ms por ruido de medición: es la misma consulta por llave primaria en ambos casos.

**Índices**: antes, DB-02/03/05/06 hacían recorrido secuencial y ordenaban en memoria. Después usan
`idx_beats_activo_fecha` (parcial, `where activo`), `idx_contact_messages_estado_fecha` e
`idx_contact_messages_user_fecha`; DB-02 y DB-05 ya no ordenan.

**Concurrencia** (pgbench, 20 clientes):

| Prueba | Resultado |
|---|---|
| CON-01 · 2 000 actualizaciones a tickets distintos | 15 497 tps, 1.29 ms, 0 fallidas |
| CON-02 · 2 000 escrituras al **mismo** ticket | 3 721 tps, 5.38 ms (espera por bloqueo de fila), 0 fallidas |
| CON-03 · 20 admins toman el mismo ticket a la vez | 1 lo obtiene; 19 reciben 409 (UPDATE condicionado al estado esperado) |
| CON-04 · mismo pago 20 veces con `Idempotency-Key` | 1 orden; 19 descartados por la restricción UNIQUE |
| CON-05 · mismo pago 20 veces **sin** clave (original) | **20 órdenes duplicadas** |

**Integridad** después de todo: 0 renglones sin orden, 0 respuestas sin ticket, 0 folios repetidos,
12 000 tickets sin pérdida.

**Consultas repetidas innecesariamente**: `GET /api/beats` hacía 3 consultas por petición; ahora
1 (más una cada 60 s para el resumen en caché, compartida entre peticiones simultáneas). Prueba:
`tickets.test.ts` → "con la caché vigente: una consulta por petición, no tres".

## Fase 5 · Matriz de resiliencia

| Código | Escenario | Esperado | Cómo responde ahora | Evidencia |
|---|---|---|---|---|
| RES-01 | Sin internet en una consulta | Error controlado | Se detecta de inmediato (error de conexión), 2 reintentos con espera de 0.25–1 s, mensaje "Sin conexión…" y barra roja global mientras no hay red | `resiliencia_test.dart` RES-01 |
| RES-02 | Sin internet en una escritura | No confirmar en falso | La pantalla nunca dice "enviado/pagado" sin respuesta del servidor; avisa "no se confirmó, reintenta sin miedo a duplicar" y conserva lo escrito | `contact_screen`, `payment_screen`, `thread_screen` |
| RES-03 | Servidor sin respuesta | Timeout controlado | connect 8 s / receive 20 s; con 2 reintentos el usuario recibe el aviso en ≤ 25 s | RES-03 (3 intentos, < 5 s con timeout corto) |
| RES-04 | HTTP 500 | Error y estabilidad | No se reintenta (no es transitorio), se muestra el mensaje de la API y la pantalla sigue usable | RES-04 |
| RES-05 | HTTP 401/403 | Manejar sesión/permisos | 401 con token → cierra sesión y avisa; 403 → "No tienes permiso"; ninguno se reintenta | RES-05, `sesionExpiradaProvider` |
| RES-06 | Recuperación de conexión | Restablecer | 502/503/504 se reintentan con backoff; al volver la red las transferencias continúan solas y la barra desaparece | RES-06, `conectividadProvider` |
| RES-07 | Reintento de escritura | Sin duplicados | `Idempotency-Key` (UUID v4) en pagos, tickets, respuestas y altas de beat; la API guarda la clave con UNIQUE y responde el registro original | RES-07, CON-04, `tickets.test.ts` 2, 11, 17, 18 |
| RES-08 | Respuesta tardía | Sin operaciones dobles en UI | Botones deshabilitados mientras hay una operación; 409 al mover un ticket que otro ya cambió; la clave se conserva entre reintentos | CON-03, `tickets.test.ts` 9 |

**Análisis**

- *¿Cuánto tarda en detectar una interrupción?* Sin red: inmediato (el sistema rechaza la conexión) y la
  barra aparece al cambiar la conectividad. Servidor caído pero con red: hasta 8 s por intento de
  conexión. Servidor colgado a media respuesta: 20 s. En subidas, 30 s sin enviar bytes.
- *¿Qué pasa con la operación pendiente?* Las lecturas se reintentan solas. Las escrituras quedan en
  la pantalla con su texto y su clave para reenviarlas. Subidas/descargas quedan "Esperando conexión"
  en SQLite.
- *¿Se repite automáticamente?* Sí, solo si es seguro: GET/HEAD y escrituras con `Idempotency-Key`,
  máximo 2 veces, ante fallos transitorios (sin conexión, timeout, 502/503/504). Nunca ante 4xx o 500.
- *¿Puede duplicarse un registro?* Antes sí (CON-05: 20 de 20). Ahora no: la clave UNIQUE lo impide
  incluso con envíos simultáneos (CON-04, prueba 18).
- *¿Cómo se recupera la interfaz?* Los estados de error tienen "Reintentar"; jalar para actualizar
  recarga; al volver la red se quita el aviso y se reanuda la cola.
- *¿Y si el servidor procesa pero la respuesta no llega?* La app no sabe si se guardó, así que no lo
  confirma. Al reintentar con la misma clave la API encuentra el registro (`client_ref`) y responde 200
  `repetida: true` con el original: el pago no se cobra dos veces y el ticket no se abre dos veces.

**Reto (exponential backoff + idempotencia)**: implementado en `ReintentoInterceptor`
(`base·2ⁿ` con tope de 8 s y *jitter* del 50 %) y en la cola de transferencias (2 s → 60 s).

### Subidas y descargas que continúan al cambiar de red (carga reanudable)

El nombre técnico es **carga reanudable** (*resumable upload*), con el protocolo abierto **TUS**, que
es el que ofrece Supabase Storage; para descargas, **peticiones de rango HTTP** (`Range` / `If-Range`).

- `TransferManager` guarda cada transferencia en SQLite (tabla `transferencias`, base v3).
- Subida: abre una sesión TUS (válida 24 h), manda partes de 6 MB con su `Upload-Offset`. Si se corta,
  queda "Esperando conexión"; al detectar cualquier red (u otra vez al abrir la app) pregunta con `HEAD`
  cuántos bytes tiene el servidor y sigue desde ahí. Al terminar avisa a la API
  (`PUT /beats/:id/media`, `/packs/:id/imagen`, `/profile/foto`).
- Descarga: escribe en `archivo.part` y continúa con `Range: bytes=N-`; si el archivo cambió en el
  servidor (`If-Range` con ETag) empieza de cero para no mezclar versiones.
- Aplica a: audio y portada del gestor de beats, foto de perfil y descarga del MP3 comprado.
- Pantalla *Subidas y descargas* con progreso, pausar, reanudar y quitar.
- Probado: `resiliencia_test.dart` (corte a 1.5 MB de 3 MB → continúa con 2 partes y el archivo queda
  idéntico) y con el emulador de Storage (corte a 300 000 bytes → continúa → archivo idéntico, `206`).

## Fase 6 · Optimización real y comparación

**Optimización elegida: paginación + índices + caché del catálogo + bandeja de tickets paginada.**

| Cambio | Archivo |
|---|---|
| `limit`/`page` en `GET /api/beats` y `GET /api/contact` (sin `limit` responde como antes para la web) | `api/src/routes/beats`, `contact` |
| La bandeja trae `contact_replies(count)` en vez del texto de todas las respuestas | `contact/index.ts` |
| Total y géneros del catálogo en caché 60 s, con una sola consulta compartida | `beats/index.ts` |
| Índices parciales y compuestos | `supabase/tickets.sql`, `local/indices.sql` |
| Tienda y gestor con scroll infinito; inicio pide solo 8 beats | `catalog_repository.dart`, `store_screen.dart` |

### Tabla comparativa antes y después

| Métrica | Antes | Después | Diferencia |
|---|---:|---:|---:|
| Latencia promedio API, 200 usuarios (ms) | 3 488 | 154 | −95.6 % |
| P95 API, 200 usuarios (ms) | 4 642 | 215 | −95.4 % |
| RPS máximo | 51 | 1 681 | 33× |
| Errores (%) | 0.00 | 0.00 | — |
| Tiempo de consulta DB (ms) — bandeja de tickets | 140.36 | 0.44 | −99.7 % |
| Tiempo de consulta DB (ms) — primera pantalla tienda | 2.50 | 0.11 | −95.8 % |
| Tamaño de respuesta — tienda (KB) | 1 332.9 | 5.5 | −99.6 % |
| Tamaño de respuesta — bandeja (KB) | 11 771 | 9.2 | −99.9 % |
| Consultas a la base por `GET /beats` | 3 | 1 | −66 % |
| Pagos duplicados con 20 reintentos | 20 | 1 | sin duplicados |
| RAM máxima en el celular, PSS (MB) | 199.3 | 193.9 | −2.7 % |
| CPU promedio en el celular (%) | 38.5 | 37.6 | −2.2 % |
| Tiempo de operación crítica (`GET /beats` en la app, ms) | 317 | 50 | −84.3 % |

## Registro de defectos y correcciones

| # | Defecto encontrado | Severidad | Corrección | Prueba |
|---|---|---|---|---|
| D-01 | Reintentar un pago tras perder la respuesta podía cobrar dos veces | Crítica | `Idempotency-Key` + `orders.client_ref UNIQUE` | CON-04/05, test 17–18 |
| D-02 | Un ticket reenviado se creaba dos veces | Alta | Igual, en `contact_messages`/`contact_replies` | test 2, 11 |
| D-03 | La bandeja descargaba todos los tickets con todas las respuestas | Alta | Paginación + conteo | DB-05 |
| D-04 | El catálogo completo se pedía para mostrar 8 tarjetas | Media | `novedadesProvider` con `limit=8` | DB-02 |
| D-05 | 3 consultas por cada `GET /beats` | Media | Caché del resumen | test 13 |
| D-06 | Dos admins podían pisarse el estado de un ticket | Media | UPDATE condicionado (`esperado`) → 409 | CON-03, test 9 |
| D-07 | Una subida cortada empezaba de cero | Media | Carga reanudable TUS + cola persistente | resiliencia TUS |
| D-08 | La búsqueda con `,()` alteraba el filtro de PostgREST | Media | Se descartan esos caracteres | test 13 |
| D-09 | Un 401 por token vencido dejaba la app "logueada" con errores | Media | `sesionExpiradaProvider` → cierre de sesión | RES-05 |
| D-10 | La API aceptaba BPM 999 o precio negativo (fallaba en la base con 500) | Baja | `validarBeat` → 400 | test 14 |
| D-11 | Sin red, el gestor/tienda se quedaba cargando para siempre: Riverpod 3 reintentaba el provider (hasta 10 veces) encima de los 3 intentos del interceptor | Media | `ProviderScope(retry: (_, _) => null)` en `main.dart` | RES-01 en el celular |

Sin defectos críticos nuevos: `flutter analyze` sin avisos, 47 pruebas de la app y 29 de la API pasan,
y la web sigue funcionando porque sin `limit` las rutas responden exactamente como antes.

## ¿Cumple los criterios de aceptación?

| Criterio | Estado |
|---|---|
| Prueba de estrés reproducible | Hecho (`carga.mjs`, antes y después) |
| Análisis de CPU y memoria | Hecho (`perfil_android.ps1` en el Huawei, mismo recorrido antes/después) |
| Concurrencia de API y base | Hecho (CON-01…05) |
| Al menos 3 escenarios de resiliencia | Hecho: los 8 (RES-01…08), con pruebas automáticas |
| Optimización real | Hecho (paginación, índices, caché, idempotencia, carga reanudable) |
| Comparación antes y después | Hecho (API, base de datos, CPU, RAM y operación crítica) |
| Sin defectos críticos nuevos | Hecho (análisis y pruebas en verde) |

## Conclusiones técnicas

El cuello de botella de SkonditBeats no estaba en el teléfono sino en **cuánto dato pedía cada
pantalla**. La bandeja de tickets tardaba 140 ms en la base y devolvía 11.7 MB porque traía el texto de
todas las conversaciones; con paginación, un índice por estado y fecha y el conteo de respuestas en
lugar de su texto, baja a 0.44 ms y 9 KB. Lo mismo pasaba con la tienda: 1.3 MB para mostrar 8–20
tarjetas. La lección es que la escalabilidad se decide en la forma de la consulta (qué columnas, cuántas
filas, qué índice resuelve el orden) antes que en el hardware del servidor: el tiempo de la consulta
original crece con el historial, el de la paginada se mantiene constante.

La prueba de concurrencia mostró el riesgo más grave: sin una clave de idempotencia, 20 reintentos de
un mismo pago crearon 20 órdenes. En una red móvil esto no es teórico: basta con que la respuesta se
pierda al cambiar de antena o de Wi-Fi. La solución correcta no es "no reintentar", sino hacer que
reintentar sea seguro: el cliente genera un UUID por operación, el servidor lo guarda con una
restricción UNIQUE y, si llega de nuevo, devuelve el registro original. La base de datos, no la app, es
quien garantiza que no haya duplicados, incluso con envíos simultáneos. Sobre eso, el reintento
automático con espera exponencial y variación aleatoria se limita a lo que es seguro repetir (lecturas
y escrituras con clave) y a fallos transitorios; un 500 o un 403 se muestran de inmediato.

Para la movilidad real del usuario —subir un beat en la universidad y terminar en casa— se implementó
carga reanudable con el protocolo TUS que ya ofrece Supabase Storage, y descargas con peticiones de
rango. La cola vive en SQLite, así que sobrevive a cortes, al cambio de red y a cerrar la app; al volver
la conectividad pregunta al servidor cuántos bytes tiene y continúa desde ahí, sin volver a mandar lo
ya subido.

Finalmente, separar el entorno de pruebas de Supabase fue necesario para que los resultados sean
confiables: con una base remota, la latencia del Wi-Fi se mezcla con la del código y las pruebas fallan
según dónde se corran. Con PostgreSQL y PostgREST locales (el mismo motor que Supabase), las pruebas de
caja blanca interceptando la red y el celular conectado por USB, los resultados son reproducibles y se
obtienen en segundos en cualquier lugar.
