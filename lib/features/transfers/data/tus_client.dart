import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// Subida reanudable con el protocolo abierto TUS 1.0.0 (https://tus.io), que es
/// el que ofrece Supabase Storage en /storage/v1/upload/resumable.
///
/// Cómo se reanuda:
///   1. [crear] abre una sesión de carga y el servidor devuelve su URL.
///   2. [enviar] manda el archivo por partes con PATCH, cada una con el byte
///      desde el que empieza (Upload-Offset).
///   3. Si se corta la red, [avance] pregunta con HEAD cuántos bytes guardó el
///      servidor y [enviar] continúa desde ahí: lo ya subido no se repite.
///
/// La sesión vive en el servidor (24 h en Supabase), así que se puede continuar
/// desde otra red o después de cerrar la app; basta guardar la URL.
class TusClient {
  TusClient(
    this._dio, {
    this.tamanoParte = 6 * 1024 * 1024,
    this.sinAvance = const Duration(seconds: 30),
  });

  final Dio _dio;

  /// Supabase pide partes de 6 MB exactos (menos la última).
  final int tamanoParte;

  /// Si la red se queda colgada este tiempo sin enviar nada, se corta la parte.
  final Duration sinAvance;

  static const _version = '1.0.0';

  /// El token de la URL firmada autoriza la subida (cabecera x-signature).
  Map<String, Object> _cabeceras(String token) => {'Tus-Resumable': _version, 'x-signature': token};

  static String _meta(Map<String, String> campos) =>
      campos.entries.map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}').join(',');

  /// Abre la sesión de carga y devuelve su URL.
  Future<String> crear({
    required String endpoint,
    required String token,
    required String bucket,
    required String objectName,
    required String mime,
    required int total,
    CancelToken? cancel,
  }) async {
    final res = await _dio.post<void>(
      endpoint,
      cancelToken: cancel,
      options: Options(headers: {
        ..._cabeceras(token),
        'Upload-Length': '$total',
        'Upload-Metadata': _meta({
          'bucketName': bucket,
          'objectName': objectName,
          'contentType': mime,
          'cacheControl': '31536000',
        }),
        'x-upsert': 'true',
      }),
    );
    final location = res.headers.value('location');
    if (location == null) {
      throw DioException.badResponse(
        statusCode: res.statusCode ?? 500,
        requestOptions: res.requestOptions,
        response: res,
      );
    }
    return Uri.parse(endpoint).resolve(location).toString();
  }

  /// Bytes que el servidor ya tiene de esta carga. Devuelve null si la sesión
  /// ya no existe o el token venció: hay que abrir una nueva y empezar de cero.
  Future<int?> avance(String url, String token, {CancelToken? cancel}) async {
    try {
      final res = await _dio.head<void>(url, cancelToken: cancel, options: Options(headers: _cabeceras(token)));
      return int.tryParse(res.headers.value('upload-offset') ?? '');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) return null;
      rethrow;
    }
  }

  /// Envía el archivo desde el byte [desde] hasta terminar.
  /// [onProgress] recibe el total de bytes enviados hasta el momento.
  Future<void> enviar({
    required String url,
    required String token,
    required File archivo,
    required int desde,
    required int total,
    void Function(int enviados)? onProgress,
    CancelToken? cancel,
  }) async {
    var offset = desde;
    var conflictos = 0;

    while (offset < total) {
      final inicio = offset;
      final fin = min(inicio + tamanoParte, total);

      // Vigía: cancela la parte si la conexión se cuelga sin enviar bytes.
      final parte = CancelToken();
      var colgada = false;
      Timer? vigia;
      void toque() {
        vigia?.cancel();
        vigia = Timer(sinAvance, () {
          colgada = true;
          parte.cancel('sin avance');
        });
      }

      unawaited(cancel?.whenCancel.then((e) {
        if (!parte.isCancelled) parte.cancel(e.message);
      }));

      toque();
      try {
        final res = await _dio.patch<void>(
          url,
          cancelToken: parte,
          data: archivo.openRead(inicio, fin).map((trozo) {
            toque();
            return trozo;
          }),
          onSendProgress: (enviados, _) => onProgress?.call(inicio + enviados),
          options: Options(headers: {
            ..._cabeceras(token),
            'Upload-Offset': '$inicio',
            Headers.contentLengthHeader: fin - inicio,
            Headers.contentTypeHeader: 'application/offset+octet-stream',
          }),
        );
        offset = int.tryParse(res.headers.value('upload-offset') ?? '') ?? fin;
        onProgress?.call(offset);
      } on DioException catch (e) {
        if (colgada) throw DioException.sendTimeout(timeout: sinAvance, requestOptions: e.requestOptions);
        // 409: el servidor tiene otro avance (p. ej. guardó parte de un envío
        // cortado). Se le pregunta y se continúa desde lo que diga.
        if (e.response?.statusCode == 409 && conflictos++ < 3) {
          final real = await avance(url, token, cancel: cancel);
          if (real != null) {
            offset = real;
            continue;
          }
        }
        rethrow;
      } finally {
        vigia?.cancel();
      }
    }
  }
}
