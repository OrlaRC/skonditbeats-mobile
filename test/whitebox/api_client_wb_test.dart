// Práctica 11 · Caja blanca del MÉTODO DE COMUNICACIÓN: ApiException.fromDio
// (traduce cada falla de red/HTTP) y ReintentoInterceptor.onError (decide si se
// repite una petición). Ver docs/practica11, M4 y M5.
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';

DioException err(DioExceptionType tipo, {int? status, Object? data, String method = 'GET'}) {
  final o = RequestOptions(path: '/x', method: method);
  return DioException(
    requestOptions: o,
    type: tipo,
    response: status == null ? null : Response(requestOptions: o, statusCode: status, data: data),
  );
}

ApiException traducir(DioExceptionType t, {int? status, Object? data}) =>
    ApiException.fromDio(err(t, status: status, data: data));

void main() {
  group('M4 · ApiException.fromDio — un caso por camino', () {
    const bad = DioExceptionType.badResponse;

    test('P1 la API manda {error} → se usa su mensaje y su código', () {
      final e = traducir(bad, status: 409, data: {'error': 'Ya tienes uno o más de estos beats'});
      expect(e.message, 'Ya tienes uno o más de estos beats');
      expect(e.statusCode, 409);
      expect(e.sinRed, isFalse);
    });
    test('P2 connectionTimeout / receiveTimeout / sendTimeout → sinRed', () {
      for (final t in [DioExceptionType.connectionTimeout, DioExceptionType.receiveTimeout, DioExceptionType.sendTimeout]) {
        final e = traducir(t);
        expect(e.sinRed, isTrue, reason: '$t');
        expect(e.message, contains('tardó demasiado'));
      }
    });
    test('P3 connectionError → sin conexión', () {
      expect(traducir(DioExceptionType.connectionError).message, contains('Sin conexión'));
    });
    test('P4 cancel', () => expect(traducir(DioExceptionType.cancel).message, 'Operación cancelada.'));
    test('P5 401 sin cuerpo → sesión expirada', () {
      expect(traducir(bad, status: 401).message, contains('sesión expiró'));
    });
    test('P6 403 sin cuerpo → sin permiso (no se confunde con 401)', () {
      final e = traducir(bad, status: 403);
      expect(e.message, contains('permiso'));
      expect(e.statusCode, 403);
    });
    test('P7 500 / 503 → problema del servidor con el código', () {
      expect(traducir(bad, status: 500).message, contains('(500)'));
      expect(traducir(bad, status: 503).message, contains('(503)'));
    });
    test('P8 sin código HTTP (corte a media respuesta) → sinRed', () {
      final e = traducir(DioExceptionType.unknown);
      expect(e.sinRed, isTrue);
      expect(e.message, contains('Se perdió la conexión'));
    });
    test('P9 otro 4xx sin cuerpo → mensaje genérico con el código', () {
      expect(traducir(bad, status: 418).message, contains('(418)'));
    });
    test('valor límite 499 / 500: 499 no es error de servidor', () {
      expect(traducir(bad, status: 499).message, isNot(contains('servidor tuvo')));
      expect(traducir(bad, status: 500).message, contains('servidor tuvo'));
    });
  });

  group('M4 · errores generados por Fastify (no por las rutas)', () {
    const bad = DioExceptionType.badResponse;
    test('400 de validación de esquema → mensaje en español, no "Bad Request"', () {
      // DEF-01: Fastify responde {statusCode, code, error:"Bad Request", message}.
      // Como trae `error`, la app mostraba "Bad Request" al usuario.
      final e = traducir(bad, status: 400, data: {
        'statusCode': 400,
        'code': 'FST_ERR_VALIDATION',
        'error': 'Bad Request',
        'message': 'body/beats must NOT have fewer than 1 items',
      });
      expect(e.message, isNot('Bad Request'));
      expect(e.message, contains('Revisa los datos'));
      expect(e.statusCode, 400);
    });
    test('404 de ruta inexistente → mensaje en español, no "Not Found"', () {
      final e = traducir(bad, status: 404, data: {'statusCode': 404, 'error': 'Not Found', 'message': 'Route GET:/x not found'});
      expect(e.message, isNot('Not Found'));
      expect(e.statusCode, 404);
    });
    test('422 sin cuerpo → mensaje de validación', () {
      expect(traducir(bad, status: 422).message, contains('Revisa los datos'));
    });
    test('422 de la API con {error} → se respeta el mensaje', () {
      final e = traducir(bad, status: 422, data: {'error': 'Uno o más beats no existen o ya no están a la venta'});
      expect(e.message, startsWith('Uno o más beats'));
    });
    test('cuerpo que no es mapa (HTML de un proxy) → no truena', () {
      expect(() => traducir(bad, status: 502, data: '<html>Bad gateway</html>'), returnsNormally);
      expect(traducir(bad, status: 502, data: '<html>').message, contains('(502)'));
    });
  });

  group('M5 · ReintentoInterceptor — cobertura de condiciones', () {
    // Decisión: cancelada || n >= max || !esSeguroRepetir || !esTransitorio
    RequestOptions op(String m, {bool clave = false}) =>
        RequestOptions(path: '/x', method: m, headers: clave ? {cabeceraIdempotencia: 'k'} : {});

    test('esSeguroRepetir: GET, HEAD, POST con clave = V; POST/PUT/DELETE sin clave = F', () {
      expect(ReintentoInterceptor.esSeguroRepetir(op('GET')), isTrue);
      expect(ReintentoInterceptor.esSeguroRepetir(op('HEAD')), isTrue);
      expect(ReintentoInterceptor.esSeguroRepetir(op('POST', clave: true)), isTrue);
      expect(ReintentoInterceptor.esSeguroRepetir(op('POST')), isFalse);
      expect(ReintentoInterceptor.esSeguroRepetir(op('PUT')), isFalse);
      expect(ReintentoInterceptor.esSeguroRepetir(op('DELETE')), isFalse);
    });

    test('esTransitorio: cada tipo de error y los códigos límite 501/502/504/505', () {
      bool t(DioExceptionType tipo, [int? s]) => ReintentoInterceptor.esTransitorio(err(tipo, status: s));
      expect(t(DioExceptionType.connectionTimeout), isTrue);
      expect(t(DioExceptionType.receiveTimeout), isTrue);
      expect(t(DioExceptionType.sendTimeout), isTrue);
      expect(t(DioExceptionType.connectionError), isTrue);
      expect(t(DioExceptionType.unknown), isTrue);
      expect(t(DioExceptionType.unknown, 200), isFalse, reason: 'unknown con respuesta no es corte');
      expect(t(DioExceptionType.cancel), isFalse);
      expect(t(DioExceptionType.badCertificate), isFalse);
      expect(t(DioExceptionType.badResponse, 501), isFalse);
      expect(t(DioExceptionType.badResponse, 502), isTrue);
      expect(t(DioExceptionType.badResponse, 503), isTrue);
      expect(t(DioExceptionType.badResponse, 504), isTrue);
      expect(t(DioExceptionType.badResponse, 505), isFalse);
      expect(t(DioExceptionType.badResponse, 500), isFalse);
    });

    test('esperaPara: valores límite del backoff (n = 0, n grande con tope)', () {
      final r = ReintentoInterceptor(Dio(), base: const Duration(milliseconds: 500), tope: const Duration(seconds: 8), random: Random(3));
      for (var i = 0; i < 50; i++) {
        final e0 = r.esperaPara(0).inMilliseconds;
        expect(e0, inInclusiveRange(250, 500));
        final e20 = r.esperaPara(20).inMilliseconds;
        expect(e20, inInclusiveRange(4000, 8000), reason: 'nunca pasa del tope');
      }
    });
  });

  group('M5 · onError contra un servidor local (sin red externa)', () {
    late HttpServer srv;
    var golpes = 0;
    var respuestas = <int>[];

    setUp(() async {
      golpes = 0;
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((r) async {
        final s = respuestas[min(golpes, respuestas.length - 1)];
        golpes++;
        await r.drain<void>();
        r.response
          ..statusCode = s
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
        await r.response.close();
      });
    });
    tearDown(() => srv.close(force: true));

    Dio cliente({int max = 2}) {
      final d = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${srv.port}'));
      d.interceptors.add(ReintentoInterceptor(d, maxReintentos: max, esperar: (_) async {}));
      return d;
    }

    test('n >= max: con max = 0 no se reintenta nunca (valor límite)', () async {
      respuestas = [503];
      await expectLater(cliente(max: 0).get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(golpes, 1);
    });
    test('503, 503, 200 → se recupera en el tercer intento (max = 2)', () async {
      respuestas = [503, 503, 200];
      final r = await cliente().get<dynamic>('/x');
      expect(r.statusCode, 200);
      expect(golpes, 3);
    });
    test('503 siempre → se rinde después de 1 + 2 intentos', () async {
      respuestas = [503];
      await expectLater(cliente().get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(golpes, 3);
    });
    test('petición cancelada → no se reintenta', () async {
      respuestas = [503];
      final ct = CancelToken();
      final d = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${srv.port}'));
      d.interceptors.add(ReintentoInterceptor(d, esperar: (_) async => ct.cancel()));
      await expectLater(d.get<dynamic>('/x', cancelToken: ct), throwsA(isA<DioException>()));
      expect(golpes, lessThanOrEqualTo(2));
    });
    test('POST sin clave con 503 → un solo intento (no duplica registros)', () async {
      respuestas = [503];
      await expectLater(cliente().post<dynamic>('/x', data: {'a': 1}), throwsA(isA<DioException>()));
      expect(golpes, 1);
    });
    test('POST con clave con 503, 201 → se repite con la misma clave', () async {
      respuestas = [503, 201];
      final r = await cliente().post<dynamic>('/x', data: {'a': 1}, options: idempotente('k-1'));
      expect(r.statusCode, 201);
      expect(golpes, 2);
    });
  });

  test('MedicionInterceptor: con reintentos registra UNA línea por petición (DEF-12)', () async {
    final lineas = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lineas.add(m ?? '');
    addTearDown(() => debugPrint = original);

    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((r) async {
      await r.drain<void>();
      r.response.statusCode = 503;
      await r.response.close();
    });
    final d = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${srv.port}'));
    d.interceptors
      ..add(ReintentoInterceptor(d, esperar: (_) async {}))
      ..add(MedicionInterceptor());
    await expectLater(d.get<dynamic>('/beats'), throwsA(isA<DioException>()));
    await srv.close(force: true);

    final p12 = lineas.where((l) => l.startsWith('[p12]')).toList();
    expect(p12, hasLength(1), reason: p12.join('\n'));
    expect(p12.single, contains('503'));
    expect(p12.single, contains('intento 3'));
  });

  test('MedicionInterceptor registra la petición sin alterar la respuesta', () async {
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((r) async {
      r.response
        ..statusCode = 200
        ..write('{"beats":[]}');
      await r.response.close();
    });
    final d = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${srv.port}'))..interceptors.add(MedicionInterceptor());
    final r = await d.get<dynamic>('/beats');
    expect(r.statusCode, 200);
    await expectLater(d.get<dynamic>('http://127.0.0.1:1/'), throwsA(isA<DioException>()));
    await srv.close(force: true);
  });
}
