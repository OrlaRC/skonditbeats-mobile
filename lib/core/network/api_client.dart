import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../storage/secure_storage.dart';

/// Error de la API ya traducido a un mensaje para el usuario.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.sinRed = false});

  final String message;
  final int? statusCode;

  /// El fallo fue de conexión (sin internet, servidor caído o sin respuesta):
  /// la operación puede no haber llegado, o haber llegado sin que volviera la respuesta.
  final bool sinRed;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    final status = e.response?.statusCode;

    if (data is Map && data['error'] is String) {
      return ApiException(data['error'] as String, statusCode: status);
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException('El servidor tardó demasiado en responder. Intenta de nuevo.', sinRed: true);
      case DioExceptionType.connectionError:
        return ApiException('Sin conexión con el servidor. Revisa tu internet.', sinRed: true);
      case DioExceptionType.cancel:
        return ApiException('Operación cancelada.');
      default:
        if (status == 401) return ApiException('Tu sesión expiró. Inicia sesión de nuevo.', statusCode: status);
        if (status == 403) return ApiException('No tienes permiso para hacer esto.', statusCode: status);
        if (status != null && status >= 500) {
          return ApiException('El servidor tuvo un problema ($status). Intenta más tarde.', statusCode: status);
        }
        // Un corte a media respuesta llega como "unknown" sin código HTTP.
        if (status == null) return ApiException('Se perdió la conexión. Intenta de nuevo.', sinRed: true);
        return ApiException('Ocurrió un error inesperado ($status).', statusCode: status);
    }
  }

  @override
  String toString() => message;
}

// ── Idempotencia ──────────────────────────────────────────────────────────────

const cabeceraIdempotencia = 'Idempotency-Key';

/// UUID v4 aleatorio: identifica UNA operación de escritura (un pago, un ticket).
String nuevaClaveIdempotencia([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Marca una escritura como idempotente. La API guarda la clave junto al registro
/// (columna UNIQUE): si la respuesta se pierde y se reintenta con la MISMA clave,
/// devuelve el registro original en lugar de crear otro. Por eso estas peticiones
/// sí se pueden reintentar solas.
Options idempotente(String clave) => Options(headers: {cabeceraIdempotencia: clave});

// ── Reintentos con espera progresiva ──────────────────────────────────────────

/// Reintenta con espera exponencial y variación aleatoria (exponential backoff
/// con jitter) las peticiones que es seguro repetir:
///   - lecturas (GET/HEAD), y
///   - escrituras que llevan Idempotency-Key.
/// Una escritura sin clave NUNCA se repite sola: podría duplicar el registro.
///
/// Solo se reintenta ante fallos transitorios: sin conexión, timeout o 502/503/504.
/// Un 4xx o un 500 se entregan de inmediato a la pantalla.
class ReintentoInterceptor extends Interceptor {
  ReintentoInterceptor(
    this._dio, {
    this.maxReintentos = 2,
    this.base = const Duration(milliseconds: 500),
    this.tope = const Duration(seconds: 8),
    Future<void> Function(Duration)? esperar,
    Random? random,
  })  : _esperar = esperar ?? Future<void>.delayed,
        _random = random ?? Random();

  final Dio _dio;
  final int maxReintentos;
  final Duration base;
  final Duration tope;
  final Future<void> Function(Duration) _esperar;
  final Random _random;

  static const _intento = 'intento';
  static const _transitorios = {502, 503, 504};

  /// Espera antes del reintento [n] (0 = primero): base·2ⁿ con tope, la mitad fija
  /// y la otra mitad aleatoria para que muchos teléfonos no reintenten a la vez.
  Duration esperaPara(int n) {
    final ms = min(base.inMilliseconds * (1 << n), tope.inMilliseconds);
    return Duration(milliseconds: ms ~/ 2 + _random.nextInt(ms ~/ 2 + 1));
  }

  static bool esSeguroRepetir(RequestOptions o) =>
      o.method == 'GET' || o.method == 'HEAD' || o.headers.containsKey(cabeceraIdempotencia);

  static bool esTransitorio(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.connectionError =>
          true,
        DioExceptionType.badResponse => _transitorios.contains(e.response?.statusCode),
        // Conexión cortada a media respuesta.
        DioExceptionType.unknown => e.response == null,
        _ => false,
      };

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    final n = (o.extra[_intento] as int?) ?? 0;
    final cancelada = o.cancelToken?.isCancelled ?? false;

    if (cancelada || n >= maxReintentos || !esSeguroRepetir(o) || !esTransitorio(err)) {
      return handler.next(err);
    }

    await _esperar(esperaPara(n));
    o.extra[_intento] = n + 1;
    try {
      handler.resolve(await _dio.fetch<dynamic>(o));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

// ── Medición (Práctica 12) ───────────────────────────────────────────────────

/// En debug y profile imprime cuánto tardó cada petición y cuánto pesó:
///   [p12] GET /beats 200 · 84 ms · 5.4 KB · intento 1
/// Se lee con `flutter logs` y sirve de evidencia de PER-03. En release no hace nada.
class MedicionInterceptor extends Interceptor {
  static const _inicio = 'p12_inicio';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_inicio] ??= DateTime.now().microsecondsSinceEpoch;
    handler.next(options);
  }

  void _log(RequestOptions o, int? status, int? bytes) {
    final t0 = o.extra[_inicio] as int?;
    if (t0 == null) return;
    final ms = (DateTime.now().microsecondsSinceEpoch - t0) / 1000;
    final kb = bytes == null ? '?' : (bytes / 1024).toStringAsFixed(1);
    final intento = ((o.extra['intento'] as int?) ?? 0) + 1;
    debugPrint('[p12] ${o.method} ${o.path} ${status ?? 'sin respuesta'} · ${ms.toStringAsFixed(0)} ms · $kb KB · intento $intento');
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final r = response;
    _log(r.requestOptions, r.statusCode, int.tryParse(r.headers.value(Headers.contentLengthHeader) ?? '') ??
        (r.data is String ? (r.data as String).length : null));
    handler.next(r);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, null);
    handler.next(err);
  }
}

// ── Cliente ───────────────────────────────────────────────────────────────────

/// Avisa cuando la API rechaza el token guardado (401): la sesión ya no sirve.
final sesionExpiradaProvider = Provider<StreamController<void>>((ref) {
  final c = StreamController<void>.broadcast();
  ref.onDispose(c.close);
  return c;
});

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final sesionExpirada = ref.watch(sesionExpiradaProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiUrl,
      connectTimeout: Env.connectTimeout,
      receiveTimeout: Env.receiveTimeout,
      sendTimeout: Env.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      // Agrega el token Bearer a cada petición (excepto login/registro),
      // igual que el interceptor de la versión web.
      onRequest: (options, handler) async {
        final isAuthRoute =
            options.path.contains('/auth/login') || options.path.contains('/auth/register');
        if (!isAuthRoute) {
          final token = await storage.readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      // 401 con token enviado = token vencido, cuenta desactivada o borrada.
      // (Un 401 en /auth/* es solo una contraseña o un código incorrecto.)
      onError: (e, handler) {
        final o = e.requestOptions;
        if (e.response?.statusCode == 401 &&
            !o.path.contains('/auth/') &&
            o.headers.containsKey('Authorization') &&
            !sesionExpirada.isClosed) {
          sesionExpirada.add(null);
        }
        handler.next(e);
      },
    ),
  );
  dio.interceptors.add(ReintentoInterceptor(dio));
  if (!kReleaseMode) dio.interceptors.add(MedicionInterceptor());

  return dio;
});
