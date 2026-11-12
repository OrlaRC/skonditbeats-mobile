import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/contact_thread.dart';

/// Tickets de soporte: abrir uno, seguir la conversación y cerrarlo.
/// Lo usan el cliente y el administrador; la API valida quién puede qué.
class ContactRepository {
  ContactRepository(this._dio);

  final Dio _dio;

  /// Abre un ticket y devuelve su folio. [clave] identifica el envío: si la red
  /// se corta después de que el servidor lo guardó, reintentar con la misma
  /// clave devuelve el mismo ticket en lugar de abrir otro.
  Future<int?> send({
    required String nombre,
    required String email,
    required String mensaje,
    required String clave,
    String? asunto,
    bool esError = false,
  }) =>
      _run(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/contact',
          options: idempotente(clave),
          data: {
            'nombre': nombre.trim(),
            'email': email.trim(),
            'mensaje': mensaje.trim(),
            'tipo': esError ? 'ERROR' : 'MENSAJE',
            if (asunto != null && asunto.trim().isNotEmpty) 'asunto': asunto.trim(),
          },
        );
        return ((res.data?['ticket'] as Map?)?['folio'] as num?)?.toInt();
      });

  Future<List<ContactThread>> getMine() => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>('/contact/mios');
        return (res.data!['messages'] as List)
            .cast<Map<String, dynamic>>()
            .map(ContactThread.fromJson)
            .toList();
      });

  /// Un ticket con toda su conversación.
  Future<ContactThread> getTicket(String id) => _run(() async {
        final res = await _dio.get<Map<String, dynamic>>('/contact/$id');
        return ContactThread.fromJson(res.data!['message'] as Map<String, dynamic>);
      });

  /// Responde (cliente o admin). Con clave para que un reintento no duplique la respuesta.
  Future<void> reply(String id, String texto, {required String clave}) => _run(
        () => _dio.post<void>('/contact/$id/respuestas', data: {'texto': texto.trim()}, options: idempotente(clave)),
      );

  /// Cambia el estado. [esperado] es el que se veía en pantalla: si alguien más
  /// lo cambió antes, la API responde 409 y no se pisa ese cambio.
  Future<void> setEstado(String id, EstadoTicket estado, {String? esperado}) => _run(
        () => _dio.put<void>('/contact/$id/estado', data: {'estado': estado.api, 'esperado': ?esperado}),
      );

  Future<T> _run<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final contactRepositoryProvider =
    Provider<ContactRepository>((ref) => ContactRepository(ref.watch(dioProvider)));

final myMessagesProvider = FutureProvider.autoDispose<List<ContactThread>>(
  (ref) => ref.watch(contactRepositoryProvider).getMine(),
);

/// Detalle de un ticket (cliente o admin).
final ticketProvider = FutureProvider.autoDispose.family<ContactThread, String>(
  (ref, id) => ref.watch(contactRepositoryProvider).getTicket(id),
);
