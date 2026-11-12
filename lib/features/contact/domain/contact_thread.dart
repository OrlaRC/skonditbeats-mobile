/// Una respuesta dentro de la conversación de un ticket.
class ContactReply {
  const ContactReply({required this.autor, required this.esAdmin, required this.texto, this.fecha});

  final String autor;
  final bool esAdmin;
  final String texto;
  final DateTime? fecha;

  factory ContactReply.fromJson(Map<String, dynamic> j) => ContactReply(
        autor: (j['autor_nombre'] as String?) ?? '',
        esAdmin: (j['es_admin'] as bool?) ?? false,
        texto: (j['texto'] as String?) ?? '',
        fecha: DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal(),
      );
}

/// Estado de un ticket de soporte.
enum EstadoTicket {
  abierto('ABIERTO', 'Abierto'),
  enProceso('EN_PROCESO', 'En proceso'),
  respondido('RESPONDIDO', 'Respondido'),
  devuelto('DEVUELTO', 'Esperando tu respuesta'),
  resuelto('RESUELTO', 'Resuelto'),
  cerrado('CERRADO', 'Cerrado');

  const EstadoTicket(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static EstadoTicket desde(String? v) =>
      EstadoTicket.values.where((e) => e.api == v).firstOrNull ?? EstadoTicket.abierto;

  bool get terminado => this == resuelto || this == cerrado;

  /// Estados a los que el administrador puede moverlo a mano.
  static const manualesAdmin = [abierto, enProceso, resuelto, cerrado];
}

enum PrioridadTicket {
  baja('BAJA', 'Baja'),
  media('MEDIA', 'Media'),
  alta('ALTA', 'Alta');

  const PrioridadTicket(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static PrioridadTicket desde(String? v) =>
      PrioridadTicket.values.where((e) => e.api == v).firstOrNull ?? PrioridadTicket.media;
}

/// Ticket de soporte: un mensaje o reporte de error con folio, estado,
/// prioridad, admin asignado y su conversación.
class ContactThread {
  const ContactThread({
    required this.id,
    required this.nombre,
    required this.email,
    required this.mensaje,
    required this.esError,
    required this.estado,
    required this.respuestas,
    this.folio,
    this.asunto,
    this.prioridad = PrioridadTicket.media,
    this.numRespuestas,
    this.userId,
    this.asignadoId,
    this.asignadoNombre,
    this.fecha,
    this.actualizado,
    this.noLeidoCliente = false,
    this.noLeidoAdmin = false,
  });

  /// Hay algo nuevo que el cliente no ha visto (respuesta o cambio de estado).
  final bool noLeidoCliente;

  /// Ticket nuevo o respuesta del cliente que ningún admin ha visto.
  final bool noLeidoAdmin;

  bool noLeidoPara({required bool admin}) => admin ? noLeidoAdmin : noLeidoCliente;

  // Se conservan para el código que compara contra el texto de la API.
  static const abierto = 'ABIERTO';
  static const respondido = 'RESPONDIDO';
  static const devuelto = 'DEVUELTO';

  final String id;
  final int? folio;
  final String? asunto;
  final String nombre;
  final String email;
  final String mensaje;
  final bool esError;
  final String estado;
  final PrioridadTicket prioridad;
  final List<ContactReply> respuestas;

  /// En la bandeja paginada solo llega cuántas respuestas hay, no su texto.
  final int? numRespuestas;
  final String? userId;
  final String? asignadoId;
  final String? asignadoNombre;
  final DateTime? fecha;
  final DateTime? actualizado;

  EstadoTicket get estadoTicket => EstadoTicket.desde(estado);

  /// Sin cuenta (mensaje público de la web) solo se le puede contestar por correo.
  bool get tieneCuenta => userId != null;

  bool get cerrado => estadoTicket == EstadoTicket.cerrado;

  int get totalRespuestas => numRespuestas ?? respuestas.length;

  String get folioTexto => folio == null ? '' : '#$folio';

  /// "#41 · No suena el beat" o, sin asunto, el tipo de ticket.
  String get titulo {
    final base = asunto?.trim().isNotEmpty == true ? asunto!.trim() : (esError ? 'Reporte de error' : 'Mensaje');
    return folio == null ? base : '$folioTexto · $base';
  }

  String get estadoLegible => switch (estado) {
        devuelto => 'Devuelto al cliente',
        _ => estadoTicket.etiqueta,
      };

  factory ContactThread.fromJson(Map<String, dynamic> j) {
    final crudas = (j['contact_replies'] as List?) ?? [];
    // Bandeja paginada: [{count: 3}] en lugar de las respuestas.
    final conteo = crudas.length == 1 && (crudas.first as Map).containsKey('count') && !(crudas.first as Map).containsKey('texto')
        ? ((crudas.first as Map)['count'] as num).toInt()
        : null;
    final respuestas = conteo != null
        ? <ContactReply>[]
        : (crudas.cast<Map<String, dynamic>>().map(ContactReply.fromJson).toList()
          ..sort((a, b) => (a.fecha ?? DateTime(0)).compareTo(b.fecha ?? DateTime(0))));

    return ContactThread(
      id: j['id'].toString(),
      folio: (j['folio'] as num?)?.toInt(),
      asunto: j['asunto'] as String?,
      nombre: (j['nombre'] as String?) ?? '',
      email: (j['email'] as String?) ?? '',
      mensaje: (j['mensaje'] as String?) ?? '',
      esError: j['tipo'] == 'ERROR',
      estado: (j['estado'] as String?) ?? abierto,
      prioridad: PrioridadTicket.desde(j['prioridad'] as String?),
      respuestas: respuestas,
      numRespuestas: conteo,
      userId: j['user_id'] as String?,
      asignadoId: j['asignado_a'] as String?,
      asignadoNombre: (j['asignado'] as Map<String, dynamic>?)?['nombre'] as String?,
      fecha: DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal(),
      actualizado: DateTime.tryParse((j['updated_at'] as String?) ?? '')?.toLocal(),
      noLeidoCliente: (j['no_leido_cliente'] as bool?) ?? false,
      noLeidoAdmin: (j['no_leido_admin'] as bool?) ?? false,
    );
  }
}
