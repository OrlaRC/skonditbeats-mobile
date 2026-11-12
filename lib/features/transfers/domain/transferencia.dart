import 'dart:convert';

enum TipoTransferencia { subida, descarga }

enum EstadoTransferencia {
  /// En cola, lista para empezar o continuar.
  pendiente('En cola'),
  activa('En curso'),

  /// La pausó el usuario; no se reanuda sola.
  pausada('En pausa'),

  /// Se cortó la red: continúa sola donde se quedó al volver la conexión.
  esperandoRed('Esperando conexión'),
  completada('Completada'),

  /// Fallo que reintentar no arregla (archivo borrado, permiso, formato).
  error('Con error');

  const EstadoTransferencia(this.etiqueta);
  final String etiqueta;
}

/// Una subida o descarga que sobrevive a cortes de red y a cerrar la app.
/// Se guarda en SQLite (tabla `transferencias`) con lo necesario para continuar:
/// dónde está el archivo, a qué URL iba y cuántos bytes llevaba.
class Transferencia {
  const Transferencia({
    required this.id,
    required this.userId,
    required this.tipo,
    required this.titulo,
    required this.rutaLocal,
    required this.creada,
    this.estado = EstadoTransferencia.pendiente,
    this.bucket,
    this.mime,
    this.nombreRemoto,
    this.url,
    this.token,
    this.urlPublica,
    this.etag,
    this.total = 0,
    this.avance = 0,
    this.cargaCompleta = false,
    this.destino,
    this.error,
    this.intentos = 0,
  });

  final String id;
  final String userId;
  final TipoTransferencia tipo;
  final String titulo;
  final EstadoTransferencia estado;

  /// Subida: copia del archivo dentro de la app. Descarga: archivo final.
  final String rutaLocal;

  // ── Solo subidas ──
  final String? bucket;
  final String? mime;
  final String? nombreRemoto;

  /// Token de la URL firmada; solo sirve para subir ESTE archivo.
  final String? token;

  /// URL pública que tendrá el archivo al terminar.
  final String? urlPublica;

  /// Los bytes ya están en el servidor; solo falta avisar a la API ([destino]).
  final bool cargaCompleta;

  /// Qué hacer al terminar, p. ej. `{accion: beat_media, id: …, campo: audio_url}`.
  final Map<String, dynamic>? destino;

  /// Subida: URL de la sesión de carga reanudable. Descarga: URL de origen.
  final String? url;

  /// Descarga: versión del archivo; si cambia en el servidor se empieza de cero.
  final String? etag;

  final int total;
  final int avance;
  final String? error;

  /// Reintentos automáticos seguidos sin avanzar (define la espera progresiva).
  final int intentos;
  final DateTime creada;

  bool get esSubida => tipo == TipoTransferencia.subida;
  double? get progreso => total > 0 ? (avance / total).clamp(0, 1).toDouble() : null;

  /// Todavía tiene trabajo por hacer (no terminó ni falló de forma definitiva).
  bool get enCurso =>
      estado != EstadoTransferencia.completada && estado != EstadoTransferencia.error;

  Transferencia copyWith({
    EstadoTransferencia? estado,
    String? Function()? url,
    String? Function()? token,
    String? Function()? urlPublica,
    String? Function()? etag,
    int? total,
    int? avance,
    bool? cargaCompleta,
    String? Function()? error,
    int? intentos,
  }) =>
      Transferencia(
        id: id,
        userId: userId,
        tipo: tipo,
        titulo: titulo,
        rutaLocal: rutaLocal,
        creada: creada,
        bucket: bucket,
        mime: mime,
        nombreRemoto: nombreRemoto,
        destino: destino,
        estado: estado ?? this.estado,
        url: url != null ? url() : this.url,
        token: token != null ? token() : this.token,
        urlPublica: urlPublica != null ? urlPublica() : this.urlPublica,
        etag: etag != null ? etag() : this.etag,
        total: total ?? this.total,
        avance: avance ?? this.avance,
        cargaCompleta: cargaCompleta ?? this.cargaCompleta,
        error: error != null ? error() : this.error,
        intentos: intentos ?? this.intentos,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'user_id': userId,
        'tipo': tipo.name,
        'titulo': titulo,
        'estado': estado.name,
        'ruta_local': rutaLocal,
        'bucket': bucket,
        'mime': mime,
        'nombre_remoto': nombreRemoto,
        'url': url,
        'token': token,
        'url_publica': urlPublica,
        'etag': etag,
        'total': total,
        'avance': avance,
        'carga_completa': cargaCompleta ? 1 : 0,
        'destino': destino == null ? null : jsonEncode(destino),
        'error': error,
        'intentos': intentos,
        'creada': creada.toIso8601String(),
      };

  factory Transferencia.fromMap(Map<String, Object?> m) => Transferencia(
        id: m['id']! as String,
        userId: m['user_id']! as String,
        tipo: TipoTransferencia.values.byName(m['tipo']! as String),
        titulo: m['titulo']! as String,
        estado: EstadoTransferencia.values.byName(m['estado']! as String),
        rutaLocal: m['ruta_local']! as String,
        bucket: m['bucket'] as String?,
        mime: m['mime'] as String?,
        nombreRemoto: m['nombre_remoto'] as String?,
        url: m['url'] as String?,
        token: m['token'] as String?,
        urlPublica: m['url_publica'] as String?,
        etag: m['etag'] as String?,
        total: (m['total'] as int?) ?? 0,
        avance: (m['avance'] as int?) ?? 0,
        cargaCompleta: m['carga_completa'] == 1,
        destino: m['destino'] == null ? null : jsonDecode(m['destino']! as String) as Map<String, dynamic>,
        error: m['error'] as String?,
        intentos: (m['intentos'] as int?) ?? 0,
        creada: DateTime.parse(m['creada']! as String),
      );
}

String formatoBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
