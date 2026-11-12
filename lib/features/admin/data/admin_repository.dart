import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/money.dart';
import '../../catalog/domain/beat.dart';
import '../../contact/domain/contact_thread.dart';

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.nombre,
    required this.rol,
    required this.activo,
    required this.beatsComprados,
  });

  final String id;
  final String email;
  final String nombre;
  final String rol;
  final bool activo;
  final int beatsComprados;

  bool get isAdmin => rol == 'ADMIN' || rol == 'SUPER_ADMIN';

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        email: j['email'] as String,
        nombre: (j['nombre'] as String?) ?? '',
        rol: (j['rol'] as String?) ?? 'CLIENTE',
        activo: (j['activo'] as bool?) ?? true,
        beatsComprados: parseNum(j['beats_comprados']).toInt(),
      );
}

/// Ficha completa de un usuario con sus compras (GET /api/users/:id).
class AdminUserDetail {
  const AdminUserDetail({
    required this.user,
    required this.compras,
    this.username,
    this.telefono,
    this.fechaRegistro,
  });

  final AdminUser user;
  final String? username;
  final String? telefono;
  final DateTime? fechaRegistro;
  final List<({String beats, num total, DateTime? fecha})> compras;

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) {
    final u = j['user'] as Map<String, dynamic>;
    return AdminUserDetail(
      user: AdminUser.fromJson(u),
      username: u['username'] as String?,
      telefono: u['telefono'] as String?,
      fechaRegistro: DateTime.tryParse((u['fecha_registro'] as String?) ?? '')?.toLocal(),
      compras: [
        for (final o in ((j['compras'] as List?) ?? []).cast<Map<String, dynamic>>())
          (
            beats: ((o['order_items'] as List?) ?? [])
                .map((i) => ((i as Map)['beats'] as Map?)?['nombre'])
                .whereType<String>()
                .join(', '),
            total: parseNum(o['total']),
            fecha: DateTime.tryParse((o['created_at'] as String?) ?? '')?.toLocal(),
          ),
      ],
    );
  }
}

/// Datos de un beat para crearlo o editarlo.
class BeatInput {
  const BeatInput({
    required this.nombre,
    required this.genero,
    required this.bpm,
    required this.precio,
    this.descripcion,
  });

  final String nombre;
  final String genero;
  final int bpm;
  final num precio;
  final String? descripcion;

  Map<String, dynamic> toJson() => {
        'nombre': nombre.trim(),
        'genero': genero.trim(),
        'bpm': bpm,
        'precio': precio,
        'descripcion': (descripcion?.trim().isEmpty ?? true) ? null : descripcion!.trim(),
      };
}

/// Una página de la bandeja de tickets.
class TicketsPage {
  const TicketsPage({required this.tickets, required this.total});
  final List<ContactThread> tickets;
  final int total;
}

/// Filtros de la bandeja de tickets (los mismos que acepta GET /api/contact).
class TicketsFilter {
  const TicketsFilter({this.estado, this.tipo, this.asignado, this.q = '', this.noLeidos = false});

  /// Solo los que tienen novedades sin leer.
  final bool noLeidos;

  final String? estado;
  final String? tipo;
  final String? asignado;
  final String q;

  Map<String, dynamic> toQuery() => {
        'estado': ?estado,
        'tipo': ?tipo,
        'asignado': ?asignado,
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (noLeidos) 'no_leidos': 1,
      };

  @override
  bool operator ==(Object other) =>
      other is TicketsFilter &&
      other.estado == estado &&
      other.tipo == tipo &&
      other.asignado == asignado &&
      other.q == q &&
      other.noLeidos == noLeidos;

  @override
  int get hashCode => Object.hash(estado, tipo, asignado, q, noLeidos);
}

/// Un registro de la bitácora de la API.
class AuditEntry {
  const AuditEntry({required this.accion, required this.detalle, this.email, this.ip, this.fecha});

  final String accion;
  final String detalle;
  final String? email;
  final String? ip;
  final DateTime? fecha;

  /// "LOGIN_FALLIDO" -> "Login fallido".
  String get accionLegible => accionLegibleDe(accion);

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        accion: (j['accion'] as String?) ?? '',
        detalle: (j['detalle'] as String?) ?? '',
        email: j['email'] as String?,
        ip: j['ip'] as String?,
        fecha: DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal(),
      );
}

String accionLegibleDe(String accion) {
  final texto = accion.replaceAll('_', ' ').toLowerCase();
  return texto.isEmpty ? texto : '${texto[0].toUpperCase()}${texto.substring(1)}';
}

class AuditPage {
  const AuditPage({required this.registros, required this.acciones});
  final List<AuditEntry> registros;
  final List<String> acciones;
}

/// Reporte general del negocio (GET /api/stats).
class AdminStats {
  const AdminStats({
    required this.totalClientes,
    required this.totalBeats,
    required this.masVendidos,
    required this.ventasPorGenero,
    required this.topClientes,
  });

  final int totalClientes;
  final int totalBeats;
  final List<({String nombre, String genero, int ventas})> masVendidos;
  final List<({String genero, int ventas})> ventasPorGenero;
  final List<({String nombre, String email, num total, int ordenes})> topClientes;

  factory AdminStats.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> lista(String k) => ((j[k] as List?) ?? []).cast<Map<String, dynamic>>();
    return AdminStats(
      totalClientes: parseNum(j['totalUsuarios']).toInt(),
      totalBeats: parseNum(j['totalBeats']).toInt(),
      masVendidos: [
        for (final b in lista('beatsMasComprados'))
          (
            nombre: (b['nombre'] as String?) ?? '',
            genero: (b['genero'] as String?) ?? '',
            ventas: parseNum(b['ventas']).toInt(),
          ),
      ],
      ventasPorGenero: [
        for (final g in lista('generosMasComprados'))
          (genero: (g['genero'] as String?) ?? '', ventas: parseNum(g['ventas']).toInt()),
      ],
      topClientes: [
        for (final c in lista('topClientes'))
          (
            nombre: (c['nombre'] as String?) ?? '',
            email: (c['email'] as String?) ?? '',
            total: parseNum(c['total']),
            ordenes: parseNum(c['ordenes']).toInt(),
          ),
      ],
    );
  }
}

/// Gestión del administrador. La API valida el rol en cada petición.
class AdminRepository {
  AdminRepository(this._dio);

  final Dio _dio;

  Future<List<AdminUser>> getUsers() => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>('/users');
        return (res.data!['users'] as List).cast<Map<String, dynamic>>().map(AdminUser.fromJson).toList();
      });

  Future<void> setRol(String id, String rol) =>
      _run(() => _dio.put<void>('/users/$id/rol', data: {'rol': rol}));

  Future<void> setActivo(String id, bool activo) =>
      _run(() => _dio.put<void>('/users/$id', data: {'activo': activo}));

  Future<AdminUserDetail> getUser(String id) => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>('/users/$id');
        return AdminUserDetail.fromJson(res.data!);
      });

  /// Alta de un usuario. Si se corta la red y se reintenta, la API responde
  /// 409 "ya registrado" (el email es único): nunca quedan dos cuentas.
  Future<void> createUser({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String? telefono,
  }) =>
      _run(() => _dio.post<void>('/users', data: {
            'nombre': nombre.trim(),
            'email': email.trim().toLowerCase(),
            'password': password,
            'rol': rol,
            if (telefono != null && telefono.trim().isNotEmpty) 'telefono': telefono.trim(),
          }));

  Future<void> updateUser(String id, {required String nombre, required String email, String? telefono}) =>
      _run(() => _dio.put<void>('/users/$id', data: {
            'nombre': nombre.trim(),
            'email': email.trim().toLowerCase(),
            'telefono': telefono?.trim() ?? '',
          }));

  Future<void> setPassword(String id, String password) =>
      _run(() => _dio.put<void>('/users/$id/password', data: {'password': password}));

  // ── Beats ──────────────────────────────────────────────────────────────────

  /// Alta de un beat. [clave] identifica la operación: si la respuesta se pierde
  /// y se reintenta con la misma clave, la API devuelve el beat ya creado.
  Future<Beat> createBeat(BeatInput b, {required String clave}) => _run(() async {
        final res = await _dio.post<Map<String, dynamic>>('/beats', data: b.toJson(), options: idempotente(clave));
        return Beat.fromJson(res.data!['beat'] as Map<String, dynamic>);
      });

  Future<Beat> updateBeat(String id, BeatInput b) => _run(() async {
        final res = await _dio.put<Map<String, dynamic>>('/beats/$id', data: b.toJson());
        return Beat.fromJson(res.data!['beat'] as Map<String, dynamic>);
      });

  /// Eliminación lógica: deja de venderse, pero sigue en las compras hechas.
  Future<void> deleteBeat(String id) => _run(() => _dio.delete<void>('/beats/$id'));

  // ── Tickets ────────────────────────────────────────────────────────────────

  Future<TicketsPage> getTickets(TicketsFilter f, {int page = 1, int limit = 20}) => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/contact',
          queryParameters: {...f.toQuery(), 'limit': limit, 'page': page},
        );
        final list =
            (res.data!['messages'] as List).cast<Map<String, dynamic>>().map(ContactThread.fromJson).toList();
        return TicketsPage(tickets: list, total: (res.data!['total'] as num?)?.toInt() ?? list.length);
      });

  Future<void> setPrioridad(String id, String prioridad) =>
      _run(() => _dio.put<void>('/contact/$id/prioridad', data: {'prioridad': prioridad}));

  Future<void> deleteMessage(String id) => _run(() => _dio.delete<void>('/contact/$id'));

  /// Regresa el caso al cliente pidiéndole más información.
  Future<void> returnToClient(String id, String motivo) =>
      _run(() => _dio.put<void>('/contact/$id/devolver', data: {'motivo': motivo.trim()}));

  /// Pasa el caso a otro administrador.
  Future<void> assign(String id, String adminId) =>
      _run(() => _dio.put<void>('/contact/$id/asignar', data: {'adminId': adminId}));

  Future<AuditPage> getAudit(String? accion) => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/audit',
          queryParameters: {'accion': ?accion},
        );
        return AuditPage(
          registros: (res.data!['registros'] as List)
              .cast<Map<String, dynamic>>()
              .map(AuditEntry.fromJson)
              .toList(),
          acciones: ((res.data!['acciones'] as List?) ?? []).cast<String>(),
        );
      });

  Future<AdminStats> getStats() => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>('/stats');
        return AdminStats.fromJson(res.data!);
      });

  Future<T> _run<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final adminRepositoryProvider =
    Provider<AdminRepository>((ref) => AdminRepository(ref.watch(dioProvider)));

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>(
  (ref) => ref.watch(adminRepositoryProvider).getUsers(),
);

final adminUserDetailProvider = FutureProvider.autoDispose.family<AdminUserDetail, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).getUser(id),
);

final adminAuditProvider = FutureProvider.autoDispose.family<AuditPage, String?>(
  (ref, accion) => ref.watch(adminRepositoryProvider).getAudit(accion),
);

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>(
  (ref) => ref.watch(adminRepositoryProvider).getStats(),
);
