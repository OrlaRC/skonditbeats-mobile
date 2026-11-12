import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/utils/roles.dart';
import 'package:skondit_beats_mobile/features/auth/domain/user.dart';
import 'package:skondit_beats_mobile/features/contact/domain/contact_thread.dart';
import 'package:skondit_beats_mobile/features/notifications/avisos.dart';

void main() {
  group('Roles', () {
    test('hay tres roles y los dos de administración entran al panel', () {
      expect(Rol.values.map((r) => r.api), ['SUPER_ADMIN', 'ADMIN', 'CLIENTE']);
      expect(const User(id: '1', email: 'a', nombre: 'A', rol: 'SUPER_ADMIN').isAdmin, isTrue);
      expect(const User(id: '1', email: 'a', nombre: 'A', rol: 'ADMIN').isSuperAdmin, isFalse);
      expect(const User(id: '1', email: 'a', nombre: 'A', rol: 'CLIENTE').isAdmin, isFalse);
      expect(Rol.desde('MODERADOR'), Rol.cliente, reason: 'un rol desconocido no da acceso');
    });

    test('un admin solo gestiona clientes; el super admin, a todos', () {
      expect(puedeGestionar('ADMIN', 'CLIENTE'), isTrue);
      expect(puedeGestionar('ADMIN', 'CLIENTE', 'ADMIN'), isFalse);
      expect(puedeGestionar('ADMIN', 'ADMIN'), isFalse);
      expect(puedeGestionar('ADMIN', 'SUPER_ADMIN'), isFalse);
      expect(puedeGestionar('SUPER_ADMIN', 'ADMIN', 'CLIENTE'), isTrue);
      expect(puedeGestionar('CLIENTE', 'CLIENTE'), isFalse);
      expect(rolesAsignables('ADMIN'), [Rol.cliente]);
      expect(rolesAsignables('SUPER_ADMIN'), hasLength(3));
    });
  });

  group('Avisos', () {
    test('el ticket indica si tiene novedades para el cliente o para el admin', () {
      final t = ContactThread.fromJson({
        'id': 'm1', 'nombre': 'A', 'email': 'a@b.c', 'mensaje': 'x',
        'no_leido_cliente': true, 'no_leido_admin': false,
      });
      expect(t.noLeidoPara(admin: false), isTrue);
      expect(t.noLeidoPara(admin: true), isFalse);
      expect(ContactThread.fromJson({'id': 'm2', 'nombre': 'A', 'email': 'a', 'mensaje': 'x'}).noLeidoCliente, isFalse);
    });

    test('una nueva respuesta en el mismo ticket es otro aviso', () {
      final a = AvisoTicket.fromJson({'id': 't1', 'folio': 4, 'updated_at': '2026-11-11T10:00:00Z'});
      final b = AvisoTicket.fromJson({'id': 't1', 'folio': 4, 'updated_at': '2026-11-11T11:00:00Z'});
      expect(a.huella, isNot(b.huella));
    });
  });
}
