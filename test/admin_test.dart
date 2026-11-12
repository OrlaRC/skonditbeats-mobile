import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/features/admin/data/admin_repository.dart';
import 'package:skondit_beats_mobile/features/contact/domain/contact_thread.dart';

void main() {
  test('una conversación ordena sus respuestas y lee el admin asignado', () {
    final h = ContactThread.fromJson({
      'id': 'm1',
      'nombre': 'Ana',
      'email': 'a@b.c',
      'mensaje': 'No suena el beat',
      'tipo': 'ERROR',
      'estado': 'DEVUELTO',
      'user_id': 'u1',
      'asignado_a': 'a2',
      'asignado': {'nombre': 'Luis'},
      'created_at': '2026-11-05T10:00:00Z',
      'contact_replies': [
        {'autor_nombre': 'Ana', 'es_admin': false, 'texto': 'Segunda', 'created_at': '2026-11-05T12:00:00Z'},
        {'autor_nombre': 'Luis', 'es_admin': true, 'texto': 'Primera', 'created_at': '2026-11-05T11:00:00Z'},
      ],
    });
    expect(h.esError, isTrue);
    expect(h.estadoLegible, 'Devuelto al cliente');
    expect(h.asignadoNombre, 'Luis');
    expect(h.respuestas.map((r) => r.texto), ['Primera', 'Segunda']);
    expect(h.tieneCuenta, isTrue);
  });

  test('un mensaje antiguo de la web, sin los campos nuevos, se sigue leyendo', () {
    final h = ContactThread.fromJson({'id': 'm2', 'nombre': 'Ana', 'email': 'a@b.c', 'mensaje': 'Hola a todos'});
    expect(h.esError, isFalse);
    expect(h.estado, ContactThread.abierto);
    expect(h.respuestas, isEmpty);
    expect(h.tieneCuenta, isFalse);
  });

  test('un registro de auditoría se lee aunque falten datos opcionales', () {
    final r = AuditEntry.fromJson({
      'id': 1,
      'accion': 'LOGIN_FALLIDO',
      'detalle': 'Contraseña incorrecta',
      'email': null,
      'ip': '127.0.0.1',
      'created_at': '2026-11-05T20:00:00Z',
    });
    expect(r.accionLegible, 'Login fallido');
    expect(r.email, isNull);
    expect(r.fecha, isNotNull);
  });

  test('los reportes aceptan números como texto y listas vacías', () {
    final s = AdminStats.fromJson({
      'totalUsuarios': 3,
      'totalBeats': '12',
      'beatsMasComprados': [
        {'nombre': 'Noche', 'genero': 'Trap', 'ventas': 4},
      ],
      'generosMasComprados': <Object>[],
      'topClientes': [
        {'nombre': 'Ana', 'email': 'a@b.c', 'total': '1500.50', 'ordenes': 2},
      ],
    });
    expect(s.totalBeats, 12);
    expect(s.masVendidos.single.ventas, 4);
    expect(s.ventasPorGenero, isEmpty);
    expect(s.topClientes.single.total, 1500.5);
  });
}
