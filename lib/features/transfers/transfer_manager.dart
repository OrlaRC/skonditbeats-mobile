import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/conectividad.dart';
import '../auth/presentation/auth_controller.dart';
import '../catalog/data/catalog_repository.dart';
import 'data/descarga_reanudable.dart';
import 'data/transferencia_dao.dart';
import 'data/tus_client.dart';
import 'domain/transferencia.dart';

/// Cliente HTTP para hablar con el almacenamiento (Supabase Storage). Va aparte
/// del de la API para no mandar nuestro JWT a un servicio externo. No tiene
/// timeout de envío global: una parte de 6 MB puede tardar minutos en una red
/// lenta; quien detecta una conexión colgada es el vigía de [TusClient].
final transferDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
  ));
  ref.onDispose(dio.close);
  return dio;
});

final tusClientProvider = Provider<TusClient>((ref) => TusClient(ref.watch(transferDioProvider)));

final descargadorProvider =
    Provider<DescargaReanudable>((ref) => DescargaReanudable(ref.watch(transferDioProvider)));

/// Carpeta privada de la app donde viven las copias por subir y las descargas.
final carpetaTransferenciasProvider =
    FutureProvider<Directory>((ref) => getApplicationDocumentsDirectory());

/// Qué hacer con el archivo cuando termina de subir.
abstract final class DestinoSubida {
  static Map<String, dynamic> beat(String id, {required bool audio}) =>
      {'accion': 'beat_media', 'id': id, 'campo': audio ? 'audio_url' : 'imagen_url'};
  static Map<String, dynamic> pack(String id) => {'accion': 'pack_imagen', 'id': id};
  static Map<String, dynamic> fotoPerfil() => {'accion': 'perfil_foto'};
}

/// Cola de subidas y descargas reanudables.
///
/// Cada transferencia se guarda en SQLite y avanza de una en una. Si se pierde
/// la conexión queda "esperando conexión" y continúa donde se quedó cuando el
/// teléfono vuelve a tener red (la misma u otra), al abrir la app, o tras una
/// espera progresiva (2 s, 4 s, 8 s… hasta 60 s). No depende de que la pantalla
/// que la inició siga abierta.
class TransferManager extends Notifier<List<Transferencia>> {
  static const _esperaBase = Duration(seconds: 2);
  static const _esperaTope = Duration(seconds: 60);

  TransferenciaDao get _dao => ref.read(transferenciaDaoProvider);
  Dio get _api => ref.read(dioProvider);

  String? _userId;
  bool _trabajando = false;
  int _generacion = 0;
  CancelToken? _cancel;
  String? _activaId;
  Timer? _reintento;
  DateTime _ultimoAviso = DateTime(0);
  DateTime _ultimoGuardado = DateTime(0);

  @override
  List<Transferencia> build() {
    final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));

    // Volvió la red (Wi-Fi de casa, datos…): continuar lo que quedó a medias.
    ref.listen(conectividadProvider, (antes, ahora) {
      if (ahora.value == true && antes?.value != true) reanudarPendientes();
    });

    final generacion = ++_generacion;
    ref.onDispose(() {
      if (generacion != _generacion) return;
      _cancel?.cancel('cierre');
      _reintento?.cancel();
    });

    // Al cambiar de usuario se suelta lo que estuviera en curso.
    _cancel?.cancel('cambio de sesión');
    _reintento?.cancel();
    _userId = userId;
    if (userId != null) _cargar(userId, generacion);
    return const [];
  }

  Future<void> _cargar(String userId, int generacion) async {
    final List<Transferencia> guardadas;
    try {
      guardadas = await _dao.listar(userId);
    } catch (_) {
      return; // Sin base local no hay cola que continuar.
    }
    if (generacion != _generacion) return;
    // Lo que quedó "en curso" o esperando red al cerrarse la app vuelve a la cola.
    state = [
      for (final t in guardadas)
        t.estado == EstadoTransferencia.activa || t.estado == EstadoTransferencia.esperandoRed
            ? t.copyWith(estado: EstadoTransferencia.pendiente)
            : t,
    ];
    unawaited(_bombear());
  }

  // ── Encolar ────────────────────────────────────────────────────────────────

  /// Encola la subida de [archivo] al [bucket]. El archivo se copia dentro de
  /// la app para que siga disponible aunque el sistema limpie su caché.
  Future<Transferencia> subir({
    required File archivo,
    required String bucket,
    required String mime,
    required String titulo,
    Map<String, dynamic>? destino,
  }) async {
    final userId = _userId;
    if (userId == null) throw ApiException('Inicia sesión para subir archivos.');

    final id = nuevaClaveIdempotencia();
    final carpeta = Directory(p.join((await ref.read(carpetaTransferenciasProvider.future)).path, 'subidas'));
    await carpeta.create(recursive: true);
    final ext = p.extension(archivo.path).toLowerCase();
    final copia = await archivo.copy(p.join(carpeta.path, '$id$ext'));

    final t = Transferencia(
      id: id,
      userId: userId,
      tipo: TipoTransferencia.subida,
      titulo: titulo,
      rutaLocal: copia.path,
      bucket: bucket,
      mime: mime,
      nombreRemoto: 'archivo$ext',
      total: await copia.length(),
      destino: destino,
      creada: DateTime.now(),
    );
    await _agregar(t);
    return t;
  }

  /// Encola la descarga de [url] a la carpeta de descargas de la app.
  /// Si ya existe una descarga de esa URL, devuelve la existente.
  Future<Transferencia> descargar({
    required String url,
    required String titulo,
    required String nombreArchivo,
  }) async {
    final userId = _userId;
    if (userId == null) throw ApiException('Inicia sesión para descargar.');

    final previa = state.where((t) => !t.esSubida && t.url == url).firstOrNull;
    if (previa != null) {
      if (previa.estado != EstadoTransferencia.completada || File(previa.rutaLocal).existsSync()) {
        if (previa.estado == EstadoTransferencia.error || previa.estado == EstadoTransferencia.pausada) {
          await reanudar(previa.id);
        }
        return previa;
      }
      await eliminar(previa.id); // El archivo ya no está: se baja otra vez.
    }

    final carpeta = Directory(p.join((await ref.read(carpetaTransferenciasProvider.future)).path, 'descargas'));
    await carpeta.create(recursive: true);
    final id = nuevaClaveIdempotencia();
    final nombre = nombreArchivo.replaceAll(RegExp(r'[^\w.\- ]'), '_');

    final t = Transferencia(
      id: id,
      userId: userId,
      tipo: TipoTransferencia.descarga,
      titulo: titulo,
      rutaLocal: p.join(carpeta.path, '${id.substring(0, 8)}_$nombre'),
      url: url,
      creada: DateTime.now(),
    );
    await _agregar(t);
    return t;
  }

  Future<void> _agregar(Transferencia t) async {
    await _dao.guardar(t);
    state = [...state, t];
    unawaited(_bombear());
  }

  // ── Controles ──────────────────────────────────────────────────────────────

  Future<void> pausar(String id) async {
    final t = _buscar(id);
    if (t == null || !t.enCurso) return;
    await _cambiar(id, (t) => t.copyWith(estado: EstadoTransferencia.pausada));
    if (_activaId == id) _cancel?.cancel('pausa');
  }

  /// Continúa una transferencia pausada o con error, desde donde se quedó.
  Future<void> reanudar(String id) async {
    final t = _buscar(id);
    if (t == null || t.estado == EstadoTransferencia.completada || t.estado == EstadoTransferencia.activa) return;
    await _cambiar(id, (t) => t.copyWith(estado: EstadoTransferencia.pendiente, error: () => null, intentos: 0));
    unawaited(_bombear());
  }

  /// Vuelve a intentar todo lo que esperaba conexión.
  void reanudarPendientes() {
    _reintento?.cancel();
    var hubo = false;
    state = [
      for (final t in state)
        if (t.estado == EstadoTransferencia.esperandoRed)
          () {
            hubo = true;
            return t.copyWith(estado: EstadoTransferencia.pendiente);
          }()
        else
          t,
    ];
    if (hubo || state.any((t) => t.estado == EstadoTransferencia.pendiente)) unawaited(_bombear());
  }

  /// Cancela (si está en curso) y borra la transferencia. Una descarga
  /// completada conserva su archivo solo si [conservarArchivo] es true.
  Future<void> eliminar(String id, {bool conservarArchivo = false}) async {
    final t = _buscar(id);
    if (t == null) return;
    state = state.where((x) => x.id != id).toList();
    if (_activaId == id) _cancel?.cancel('eliminada');
    await _dao.eliminar(id);
    if (t.esSubida || !conservarArchivo) await _borrarArchivos(t);
  }

  Future<void> limpiarCompletadas() async {
    final listas = state.where((t) => t.estado == EstadoTransferencia.completada && t.esSubida).toList();
    for (final t in listas) {
      await eliminar(t.id);
    }
  }

  /// Archivo local de una descarga terminada de [url], si sigue en el teléfono.
  File? archivoDescargado(String? url) {
    if (url == null) return null;
    final t = state
        .where((t) => !t.esSubida && t.url == url && t.estado == EstadoTransferencia.completada)
        .firstOrNull;
    if (t == null) return null;
    final f = File(t.rutaLocal);
    return f.existsSync() ? f : null;
  }

  // ── Cola ───────────────────────────────────────────────────────────────────

  Transferencia? _buscar(String id) => state.where((t) => t.id == id).firstOrNull;

  /// Aplica el cambio en memoria y en SQLite. Devuelve null si ya no existe.
  Future<Transferencia?> _cambiar(String id, Transferencia Function(Transferencia) cambio) async {
    final actual = _buscar(id);
    if (actual == null) return null;
    final nueva = cambio(actual);
    state = [for (final t in state) t.id == id ? nueva : t];
    await _dao.guardar(nueva);
    return nueva;
  }

  Future<void> _bombear() async {
    if (_trabajando) return;
    _trabajando = true;
    final generacion = _generacion;
    try {
      while (generacion == _generacion) {
        final siguiente = state.where((t) => t.estado == EstadoTransferencia.pendiente).firstOrNull;
        if (siguiente == null) break;
        await _procesar(siguiente.id);
      }
    } finally {
      _trabajando = false;
    }
  }

  Future<void> _procesar(String id) async {
    final cancel = _cancel = CancelToken();
    _activaId = id;
    try {
      final t = await _cambiar(id, (t) => t.copyWith(estado: EstadoTransferencia.activa, error: () => null));
      if (t == null) return;

      if (t.esSubida) {
        if (!t.cargaCompleta) await _subirBytes(t, cancel);
        await _avisarDestino(_buscar(id) ?? t);
        await _borrarArchivos(t);
      } else {
        await _bajarBytes(t, cancel);
      }
      await _cambiar(
        id,
        (t) => t.copyWith(
          estado: EstadoTransferencia.completada,
          avance: t.total,
          intentos: 0,
          token: () => null,
        ),
      );
    } on DioException catch (e) {
      // Cancelada por pausa, eliminación o cierre de sesión: su estado ya se fijó.
      if (CancelToken.isCancel(e)) return;
      if (ReintentoInterceptor.esTransitorio(e)) {
        await _esperarRed(id);
      } else {
        await _fallar(id, ApiException.fromDio(e).message);
      }
    } on FileSystemException {
      await _fallar(id, 'El archivo ya no está en el teléfono. Vuelve a elegirlo.');
    } on ApiException catch (e) {
      await _fallar(id, e.message);
    } catch (_) {
      await _fallar(id, 'No se pudo completar la transferencia.');
    } finally {
      if (_activaId == id) _activaId = null;
    }
  }

  Future<void> _fallar(String id, String mensaje) =>
      _cambiar(id, (t) => t.copyWith(estado: EstadoTransferencia.error, error: () => mensaje));

  /// Sin red: queda en espera y se programa un reintento con espera progresiva.
  /// Si antes vuelve la conexión, [reanudarPendientes] se adelanta.
  Future<void> _esperarRed(String id) async {
    final t = await _cambiar(
      id,
      (t) => t.copyWith(estado: EstadoTransferencia.esperandoRed, intentos: t.intentos + 1),
    );
    if (t == null) return;
    final espera = Duration(
      milliseconds: min(_esperaBase.inMilliseconds * (1 << min(t.intentos - 1, 10)), _esperaTope.inMilliseconds),
    );
    _reintento?.cancel();
    _reintento = Timer(espera, reanudarPendientes);
  }

  void _progreso(String id, int bytes) {
    final ahora = DateTime.now();
    final actual = _buscar(id);
    if (actual == null) return;
    final nueva = actual.copyWith(avance: bytes, intentos: 0);
    // La pantalla se refresca como mucho 8 veces por segundo y SQLite cada 2 s:
    // el avance real siempre se le vuelve a preguntar al servidor al reanudar.
    if (ahora.difference(_ultimoAviso) >= const Duration(milliseconds: 120) || bytes >= actual.total) {
      _ultimoAviso = ahora;
      state = [for (final t in state) t.id == id ? nueva : t];
    }
    if (ahora.difference(_ultimoGuardado) >= const Duration(seconds: 2)) {
      _ultimoGuardado = ahora;
      unawaited(_dao.guardar(nueva).catchError((_) {}));
    }
  }

  // ── Subida ─────────────────────────────────────────────────────────────────

  Future<void> _subirBytes(Transferencia t, CancelToken cancel) async {
    final archivo = File(t.rutaLocal);
    final total = await archivo.length();
    final tus = ref.read(tusClientProvider);

    // ¿Hay una sesión de carga abierta? Se le pregunta al servidor cuánto tiene.
    int? desde;
    if (t.url != null && t.token != null) {
      desde = await tus.avance(t.url!, t.token!, cancel: cancel);
    }

    var actual = t;
    if (desde == null) {
      // Primera vez, o la sesión venció: URL firmada nueva y se empieza de cero.
      final presign = (await _api.post<Map<String, dynamic>>(
        '/uploads/presign',
        cancelToken: cancel,
        data: {'bucket': t.bucket, 'contentType': t.mime, 'fileName': t.nombreRemoto},
      ))
          .data!;
      final resumable = presign['resumable'] as Map<String, dynamic>?;

      if (resumable == null) {
        // API anterior, sin carga reanudable: subida directa de una sola pieza.
        await ref.read(transferDioProvider).put<void>(
              presign['signedUrl'] as String,
              data: archivo.openRead(),
              cancelToken: cancel,
              onSendProgress: (n, _) => _progreso(t.id, n),
              options: Options(headers: {
                Headers.contentTypeHeader: t.mime,
                Headers.contentLengthHeader: total,
                'x-upsert': 'true',
              }),
            );
        await _cambiar(
          t.id,
          (t) => t.copyWith(cargaCompleta: true, avance: total, total: total, urlPublica: () => presign['publicUrl'] as String),
        );
        return;
      }

      final token = resumable['token'] as String;
      final url = await tus.crear(
        endpoint: resumable['endpoint'] as String,
        token: token,
        bucket: resumable['bucket'] as String,
        objectName: resumable['objectName'] as String,
        mime: t.mime!,
        total: total,
        cancel: cancel,
      );
      actual = await _cambiar(
            t.id,
            (t) => t.copyWith(
              url: () => url,
              token: () => token,
              urlPublica: () => presign['publicUrl'] as String,
              total: total,
              avance: 0,
            ),
          ) ??
          t;
      desde = 0;
    } else {
      await _cambiar(t.id, (t) => t.copyWith(avance: desde, total: total));
    }

    await tus.enviar(
      url: actual.url!,
      token: actual.token!,
      archivo: archivo,
      desde: desde,
      total: total,
      cancel: cancel,
      onProgress: (n) => _progreso(t.id, n),
    );
    await _cambiar(t.id, (t) => t.copyWith(cargaCompleta: true, avance: total));
  }

  /// Registra en la API la URL del archivo ya subido. Son PUT que fijan un
  /// valor: repetirlos tras un corte deja el mismo resultado (idempotentes).
  Future<void> _avisarDestino(Transferencia t) async {
    final destino = t.destino;
    final url = t.urlPublica;
    if (destino == null || url == null) return;

    switch (destino['accion']) {
      case 'beat_media':
        await _api.put<void>('/beats/${destino['id']}/media', data: {destino['campo'] as String: url});
        ref.invalidate(beatsPagerProvider);
        ref.invalidate(novedadesProvider);
      case 'pack_imagen':
        await _api.put<void>('/packs/${destino['id']}/imagen', data: {'imagen_url': url});
        ref.invalidate(packsProvider);
      case 'perfil_foto':
        await _api.put<void>('/profile/foto', data: {'foto_url': url});
        await ref.read(authControllerProvider.notifier).updateFoto(url);
    }
  }

  // ── Descarga ───────────────────────────────────────────────────────────────

  Future<void> _bajarBytes(Transferencia t, CancelToken cancel) async {
    await ref.read(descargadorProvider).bajar(
          url: t.url!,
          destino: File(t.rutaLocal),
          etag: t.etag,
          cancel: cancel,
          alIniciar: (total, etag) =>
              unawaited(_cambiar(t.id, (t) => t.copyWith(total: total, etag: () => etag))),
          onProgress: (n) => _progreso(t.id, n),
        );
  }

  Future<void> _borrarArchivos(Transferencia t) async {
    for (final ruta in [t.rutaLocal, '${t.rutaLocal}.part']) {
      try {
        final f = File(ruta);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Un archivo temporal que no se pudo borrar no debe romper la cola.
      }
    }
  }
}

final transferManagerProvider =
    NotifierProvider<TransferManager, List<Transferencia>>(TransferManager.new);

/// Cuántas transferencias siguen trabajando o esperando (para el indicador).
final transferenciasEnCursoProvider = Provider<int>(
  (ref) => ref.watch(transferManagerProvider).where((t) => t.enCurso).length,
);
