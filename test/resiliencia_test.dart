// Práctica 12 · Fase 5: pruebas de resiliencia de la app. Todo corre contra un
// servidor HTTP local dentro de la prueba (127.0.0.1), sin Supabase ni internet:
// da el mismo resultado en cualquier red y tarda pocos segundos.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';
import 'package:skondit_beats_mobile/features/contact/domain/contact_thread.dart';
import 'package:skondit_beats_mobile/features/transfers/data/descarga_reanudable.dart';
import 'package:skondit_beats_mobile/features/transfers/data/tus_client.dart';
import 'package:skondit_beats_mobile/features/transfers/domain/transferencia.dart';

/// Servidor de pruebas: cada prueba define cómo responde.
class Servidor {
  late HttpServer _http;
  final peticiones = <HttpRequest>[];
  Future<void> Function(HttpRequest r, int n)? responder;

  String get url => 'http://127.0.0.1:${_http.port}';

  Future<void> iniciar() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((r) async {
      peticiones.add(r);
      await responder!(r, peticiones.length);
    });
  }

  Future<void> cerrar() => _http.close(force: true);
}

Future<void> json(HttpRequest r, int status, [String cuerpo = '{}']) async {
  await r.drain<void>();
  r.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(cuerpo);
  await r.response.close();
}

/// Dio con el interceptor de reintentos real, sin esperas reales.
(Dio, List<Duration>) dioConReintentos(String base, {Duration? receiveTimeout}) {
  final esperas = <Duration>[];
  final dio = Dio(BaseOptions(
    baseUrl: base,
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: receiveTimeout ?? const Duration(seconds: 2),
  ));
  dio.interceptors.add(ReintentoInterceptor(dio, esperar: (d) async => esperas.add(d), random: Random(1)));
  return (dio, esperas);
}

void main() {
  late Servidor s;
  setUp(() async {
    s = Servidor();
    await s.iniciar();
  });
  tearDown(() => s.cerrar());

  group('Reintentos con espera progresiva', () {
    test('la espera crece exponencialmente con variación y tiene tope', () {
      final r = ReintentoInterceptor(Dio(), base: const Duration(milliseconds: 500), tope: const Duration(seconds: 8), random: Random(7));
      for (var n = 0; n < 8; n++) {
        final ms = min(500 * (1 << n), 8000);
        final d = r.esperaPara(n).inMilliseconds;
        expect(d, inInclusiveRange(ms ~/ 2, ms), reason: 'intento $n');
      }
    });

    test('RES-03/RES-06: una lectura con 503 se reintenta y se recupera', () async {
      s.responder = (r, n) => n < 3 ? json(r, 503) : json(r, 200, '{"ok":true}');
      final (dio, esperas) = dioConReintentos(s.url);
      final res = await dio.get<Map<String, dynamic>>('/beats');
      expect(res.data!['ok'], isTrue);
      expect(s.peticiones, hasLength(3));
      expect(esperas, hasLength(2));
    });

    test('RES-03: servidor que no responde → timeout controlado tras 2 reintentos', () async {
      s.responder = (r, n) async {}; // nunca contesta
      final (dio, esperas) = dioConReintentos(s.url, receiveTimeout: const Duration(milliseconds: 300));
      final reloj = Stopwatch()..start();
      final e = await dio.get<void>('/beats').then<DioException?>((_) => null, onError: (Object e) => e as DioException);
      expect(e, isNotNull);
      final api = ApiException.fromDio(e!);
      expect(api.sinRed, isTrue);
      expect(api.message, contains('tardó demasiado'));
      expect(s.peticiones, hasLength(3));
      expect(esperas, hasLength(2));
      expect(reloj.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('RES-02/RES-07: una escritura SIN clave nunca se repite sola', () async {
      s.responder = (r, n) => json(r, 503);
      final (dio, _) = dioConReintentos(s.url);
      await expectLater(dio.post<void>('/orders', data: {'beats': ['b1']}), throwsA(isA<DioException>()));
      expect(s.peticiones, hasLength(1));
    });

    test('RES-07: una escritura CON clave se reintenta y manda siempre la misma clave', () async {
      s.responder = (r, n) => n == 1 ? json(r, 504) : json(r, 200, '{"repetida":true}');
      final (dio, _) = dioConReintentos(s.url);
      final clave = nuevaClaveIdempotencia();
      await dio.post<void>('/orders', data: {'beats': ['b1']}, options: idempotente(clave));
      expect(s.peticiones, hasLength(2));
      expect(s.peticiones.map((r) => r.headers.value(cabeceraIdempotencia)).toSet(), {clave});
    });

    test('RES-04: un 500 no se reintenta y llega como error controlado', () async {
      s.responder = (r, n) => json(r, 500, '{"error":"Error al obtener los beats"}');
      final (dio, _) = dioConReintentos(s.url);
      final e = await dio.get<void>('/beats').then<DioException?>((_) => null, onError: (Object e) => e as DioException);
      expect(s.peticiones, hasLength(1));
      expect(ApiException.fromDio(e!).message, 'Error al obtener los beats');
      expect(ApiException.fromDio(e).statusCode, 500);
    });

    test('RES-05: 401 y 403 no se reintentan y se traducen', () async {
      s.responder = (r, n) => json(r, n == 1 ? 401 : 403, '{}');
      final (dio, _) = dioConReintentos(s.url);
      final e1 = await dio.get<void>('/profile').then<DioException?>((_) => null, onError: (Object e) => e as DioException);
      final e2 = await dio.get<void>('/users').then<DioException?>((_) => null, onError: (Object e) => e as DioException);
      expect(s.peticiones, hasLength(2));
      expect(ApiException.fromDio(e1!).message, contains('sesión expiró'));
      expect(ApiException.fromDio(e2!).message, contains('permiso'));
    });

    test('RES-01: sin conexión se detecta como error de red', () async {
      final url = s.url;
      await s.cerrar(); // puerto cerrado = no hay servidor
      final (dio, esperas) = dioConReintentos(url);
      final e = await dio.get<void>('/beats').then<DioException?>((_) => null, onError: (Object e) => e as DioException);
      expect(ApiException.fromDio(e!).sinRed, isTrue);
      expect(esperas, hasLength(2));
      await s.iniciar(); // para el tearDown
    });

    test('las claves de idempotencia son UUID v4 distintos', () {
      final claves = List.generate(500, (_) => nuevaClaveIdempotencia()).toSet();
      expect(claves, hasLength(500));
      final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(claves.every(uuid.hasMatch), isTrue);
    });
  });

  group('Subida reanudable (TUS)', () {
    /// Servidor TUS mínimo que guarda los bytes en memoria y puede cortar la conexión.
    Future<BytesBuilder> servidorTus({int? cortarEn}) async {
      final guardado = BytesBuilder(copy: false);
      var cortado = false;
      s.responder = (r, n) async {
        if (r.method == 'POST') {
          await r.drain<void>();
          r.response
            ..statusCode = 201
            ..headers.set('location', '/subida/1');
          return r.response.close();
        }
        if (r.method == 'HEAD') {
          r.response
            ..statusCode = 200
            ..headers.set('upload-offset', '${guardado.length}');
          return r.response.close();
        }
        if (int.parse(r.headers.value('upload-offset')!) != guardado.length) return json(r, 409);
        await for (final trozo in r) {
          if (cortarEn != null && !cortado && guardado.length + trozo.length > cortarEn) {
            guardado.add(trozo.sublist(0, cortarEn - guardado.length));
            cortado = true;
            r.response.detachSocket().then((sock) => sock.destroy()); // se va el Wi-Fi
            return;
          }
          guardado.add(trozo);
        }
        r.response
          ..statusCode = 204
          ..headers.set('upload-offset', '${guardado.length}');
        await r.response.close();
      };
      return guardado;
    }

    Future<File> archivo(int bytes) async {
      final f = File('${Directory.systemTemp.createTempSync('tus').path}/beat.mp3');
      await f.writeAsBytes(List.generate(bytes, (i) => i % 251));
      return f;
    }

    test('se corta a la mitad y continúa desde el byte donde quedó, sin repetir lo subido', () async {
      const total = 3 * 1024 * 1024;
      final guardado = await servidorTus(cortarEn: 1500 * 1024);
      final f = await archivo(total);
      final tus = TusClient(Dio(), tamanoParte: 1024 * 1024);

      final url = await tus.crear(
        endpoint: '${s.url}/upload/resumable', token: 't', bucket: 'beats-audio',
        objectName: 'beat.mp3', mime: 'audio/mpeg', total: total,
      );
      await expectLater(
        tus.enviar(url: url, token: 't', archivo: f, desde: 0, total: total),
        throwsA(isA<DioException>()),
      );
      // "Llega a casa": se pregunta al servidor cuánto tiene y se continúa.
      final avance = await tus.avance(url, 't');
      expect(avance, 1500 * 1024);

      final antes = s.peticiones.length;
      await tus.enviar(url: url, token: 't', archivo: f, desde: avance!, total: total);
      expect(guardado.length, total);
      expect(guardado.toBytes(), await f.readAsBytes(), reason: 'el archivo en el servidor queda idéntico');
      // Solo se mandó lo que faltaba (1.5 MB → 2 partes), no el archivo completo.
      expect(s.peticiones.length - antes, 2);
    });

    test('si el servidor tiene otro avance (409), pregunta y se alinea', () async {
      const total = 256 * 1024;
      final guardado = await servidorTus();
      final f = await archivo(total);
      final tus = TusClient(Dio(), tamanoParte: 64 * 1024);
      final url = await tus.crear(
        endpoint: '${s.url}/upload/resumable', token: 't', bucket: 'b', objectName: 'o', mime: 'audio/mpeg', total: total,
      );
      await tus.enviar(url: url, token: 't', archivo: f, desde: 0, total: 128 * 1024);
      // La app cree que va en 0 (perdió su avance local): el servidor dice 128 KB.
      await tus.enviar(url: url, token: 't', archivo: f, desde: 0, total: total);
      expect(guardado.toBytes(), await f.readAsBytes());
    });

    test('una sesión vencida (404) pide empezar de nuevo', () async {
      s.responder = (r, n) => json(r, 404);
      expect(await TusClient(Dio()).avance('${s.url}/subida/x', 't'), isNull);
    });
  });

  group('Descarga reanudable (Range)', () {
    final contenido = Uint8List.fromList(List.generate(400 * 1024, (i) => i % 239));

    void servidorArchivo({int? cortarEn, String etag = '"v1"'}) {
      var cortes = 0;
      s.responder = (r, n) async {
        await r.drain<void>();
        final rango = RegExp(r'bytes=(\d+)-').firstMatch(r.headers.value('range') ?? '');
        final vigente = r.headers.value('if-range') == null || r.headers.value('if-range') == etag;
        final desde = rango != null && vigente ? int.parse(rango.group(1)!) : 0;
        r.response.headers.set('etag', etag);
        if (desde > 0) {
          r.response
            ..statusCode = 206
            ..headers.set('content-range', 'bytes $desde-${contenido.length - 1}/${contenido.length}');
        }
        r.response.contentLength = contenido.length - desde;
        if (cortarEn != null && cortes == 0) {
          cortes++;
          // Se mandan las cabeceras y solo parte del cuerpo; luego se cae la red.
          final sock = await r.response.detachSocket();
          sock.add(contenido.sublist(desde, cortarEn));
          await sock.flush();
          sock.destroy();
          return;
        }
        r.response.add(contenido.sublist(desde));
        await r.response.close();
      };
    }

    test('se corta, y al reintentar pide solo lo que falta', () async {
      servidorArchivo(cortarEn: 150 * 1024);
      final destino = File('${Directory.systemTemp.createTempSync('dl').path}/beat.mp3');
      final d = DescargaReanudable(Dio());
      String? etag;

      await expectLater(
        d.bajar(url: '${s.url}/beat.mp3', destino: destino, alIniciar: (_, e) => etag = e),
        throwsA(isA<DioException>()),
      );
      expect(File('${destino.path}.part').lengthSync(), greaterThan(0));
      expect(destino.existsSync(), isFalse);

      await d.bajar(url: '${s.url}/beat.mp3', destino: destino, etag: etag);
      expect(s.peticiones.last.headers.value('range'), startsWith('bytes='));
      expect(await destino.readAsBytes(), contenido);
      expect(File('${destino.path}.part').existsSync(), isFalse);
    });

    test('si el archivo cambió en el servidor, empieza de cero (no mezcla versiones)', () async {
      servidorArchivo(etag: '"v2"');
      final destino = File('${Directory.systemTemp.createTempSync('dl').path}/beat.mp3');
      await File('${destino.path}.part').writeAsBytes(List.filled(1000, 7)); // parcial de la v1
      await DescargaReanudable(Dio()).bajar(url: '${s.url}/beat.mp3', destino: destino, etag: '"v1"');
      expect(await destino.readAsBytes(), contenido);
    });
  });

  group('Modelos', () {
    test('un ticket paginado lee folio, prioridad y el conteo de respuestas', () {
      final t = ContactThread.fromJson({
        'id': 'm1', 'folio': 41, 'asunto': 'No suena', 'nombre': 'Ana', 'email': 'a@b.c',
        'mensaje': 'x', 'tipo': 'ERROR', 'estado': 'EN_PROCESO', 'prioridad': 'ALTA',
        'contact_replies': [{'count': 3}],
      });
      expect(t.titulo, '#41 · No suena');
      expect(t.estadoTicket, EstadoTicket.enProceso);
      expect(t.prioridad, PrioridadTicket.alta);
      expect(t.totalRespuestas, 3);
      expect(t.respuestas, isEmpty);
    });

    test('estados desconocidos caen en Abierto y los terminados se distinguen', () {
      expect(EstadoTicket.desde('RARO'), EstadoTicket.abierto);
      expect(EstadoTicket.cerrado.terminado, isTrue);
      expect(EstadoTicket.devuelto.terminado, isFalse);
    });

    test('una transferencia sobrevive ida y vuelta a SQLite', () {
      final t = Transferencia(
        id: 'x', userId: 'u', tipo: TipoTransferencia.subida, titulo: 'Audio',
        rutaLocal: '/a.mp3', bucket: 'beats-audio', mime: 'audio/mpeg', url: 'http://s/1', token: 'tk',
        total: 100, avance: 40, estado: EstadoTransferencia.esperandoRed, intentos: 2,
        destino: {'accion': 'beat_media', 'id': 'b1', 'campo': 'audio_url'}, creada: DateTime(2026, 11, 11),
      );
      final b = Transferencia.fromMap(t.toMap());
      expect(b.estado, EstadoTransferencia.esperandoRed);
      expect(b.progreso, 0.4);
      expect(b.destino!['id'], 'b1');
      expect(b.enCurso, isTrue);
      expect(formatoBytes(3 * 1024 * 1024 + 300000), '3.3 MB');
    });
  });
}
