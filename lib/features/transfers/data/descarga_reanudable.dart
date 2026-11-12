import 'dart:io';

import 'package:dio/dio.dart';

/// Descarga reanudable con peticiones de rango de HTTP.
///
/// Lo recibido se va guardando en `<archivo>.part`. Si se corta la red, la
/// siguiente vez se pide solo lo que falta (`Range: bytes=N-`) y se agrega al
/// final. `If-Range` lleva la versión (ETag) con la que se empezó: si el archivo
/// cambió en el servidor, este responde 200 con todo y se empieza de cero, para
/// no pegar dos mitades de archivos distintos.
class DescargaReanudable {
  DescargaReanudable(this._dio);

  final Dio _dio;

  Future<void> bajar({
    required String url,
    required File destino,
    String? etag,
    void Function(int total, String? etag)? alIniciar,
    void Function(int recibidos)? onProgress,
    CancelToken? cancel,
  }) async {
    final parcial = File('${destino.path}.part');
    await parcial.parent.create(recursive: true);
    var desde = await parcial.exists() ? await parcial.length() : 0;

    final res = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (s) => s == 200 || s == 206 || s == 416,
        headers: {
          if (desde > 0) 'Range': 'bytes=$desde-',
          if (desde > 0 && etag != null) 'If-Range': etag,
        },
      ),
    );

    final rango = res.headers.value('content-range'); // "bytes 100-999/1000" o "bytes */1000"
    final totalRango = int.tryParse(rango?.split('/').last ?? '');

    if (res.statusCode == 416) {
      // El rango pedido no existe: o el parcial ya está completo, o no corresponde.
      await res.data?.stream.drain<void>();
      if (totalRango != null && totalRango == desde) {
        await parcial.rename(destino.path);
        return;
      }
      await parcial.delete();
      return bajar(url: url, destino: destino, alIniciar: alIniciar, onProgress: onProgress, cancel: cancel);
    }

    // 200 = el servidor manda el archivo completo (no acepta rangos o cambió).
    if (res.statusCode == 200) desde = 0;
    final total = res.statusCode == 206
        ? (totalRango ?? 0)
        : (int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '') ?? 0);
    alIniciar?.call(total, res.headers.value('etag'));

    final salida = parcial.openWrite(mode: desde > 0 ? FileMode.append : FileMode.write);
    var recibidos = desde;
    try {
      await for (final trozo in res.data!.stream) {
        salida.add(trozo);
        recibidos += trozo.length;
        onProgress?.call(recibidos);
      }
    } on DioException {
      rethrow;
    } catch (e) {
      // Un corte a media descarga llega como error del socket: se reporta como
      // fallo de conexión para que la cola lo reanude.
      throw DioException.connectionError(requestOptions: res.requestOptions, reason: '$e');
    } finally {
      // Lo recibido queda en disco aunque la descarga se haya cortado.
      await salida.flush();
      await salida.close();
    }

    if (total > 0 && recibidos < total) {
      throw DioException.connectionError(requestOptions: res.requestOptions, reason: 'descarga incompleta');
    }
    await parcial.rename(destino.path);
  }
}
