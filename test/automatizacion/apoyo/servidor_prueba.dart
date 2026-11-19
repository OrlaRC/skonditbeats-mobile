// Prácticas 13 y 14 · Apoyo para las pruebas de integración.
// Un servidor HTTP real en 127.0.0.1 que hace el papel de la API de SkonditBeats.
// No usa Supabase ni internet: corre igual en la PC y en GitHub Actions.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';

/// Petición recibida, ya leída (método, ruta, cabeceras y cuerpo JSON).
class Recibida {
  Recibida(this.metodo, this.ruta, this.cabeceras, this.cuerpo);
  final String metodo;
  final String ruta;
  final HttpHeaders cabeceras;
  final Map<String, dynamic>? cuerpo;
}

typedef Respuesta = ({int status, Object? cuerpo});

class ServidorPrueba {
  late HttpServer _http;
  final recibidas = <Recibida>[];

  /// Cómo contesta cada prueba. `null` = no contesta nunca (servidor colgado).
  Respuesta? Function(Recibida r)? responder;

  String get url => 'http://127.0.0.1:${_http.port}/api';

  Future<void> iniciar() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((req) async {
      final texto = await utf8.decoder.bind(req).join();
      final r = Recibida(
        req.method,
        req.uri.path,
        req.headers,
        texto.isEmpty ? null : jsonDecode(texto) as Map<String, dynamic>,
      );
      recibidas.add(r);
      final resp = responder?.call(r);
      if (resp == null) return; // se queda sin responder
      req.response
        ..statusCode = resp.status
        ..headers.contentType = ContentType.json
        ..write(resp.cuerpo is String ? resp.cuerpo : jsonEncode(resp.cuerpo));
      await req.response.close();
    });
  }

  Future<void> cerrar() => _http.close(force: true);
}

/// Dio configurado como en la app (mismo interceptor de reintentos), con tiempos
/// cortos y sin esperas reales para que la prueba tarde milisegundos.
Dio dioDePrueba(String baseUrl, {Duration timeout = const Duration(seconds: 2)}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: timeout,
    receiveTimeout: timeout,
    contentType: Headers.jsonContentType,
  ));
  dio.interceptors.add(ReintentoInterceptor(dio, esperar: (_) async {}, random: Random(1)));
  return dio;
}

/// Una URL a la que no escucha nadie: simula "el servidor no responde / está caído".
Future<String> urlSinServidor() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final puerto = s.port;
  await s.close();
  return 'http://127.0.0.1:$puerto/api';
}
