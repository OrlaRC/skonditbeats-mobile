// Práctica 11 · Caja blanca del MÉTODO DE PROCESAMIENTO: CartController.addPack
// (y addBeat). Recorre los caminos del grafo de flujo (docs/practica11, M3).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/database/app_database.dart';
import 'package:skondit_beats_mobile/features/auth/domain/user.dart';
import 'package:skondit_beats_mobile/features/auth/presentation/auth_controller.dart';
import 'package:skondit_beats_mobile/features/cart/data/cart_dao.dart';
import 'package:skondit_beats_mobile/features/cart/domain/cart_item.dart';
import 'package:skondit_beats_mobile/features/cart/presentation/cart_controller.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/beat.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/pack.dart';

class SesionIniciada extends AuthController {
  @override
  AuthState build() => const AuthState.authenticated(
        User(id: 'u1', email: 'a@b.com', nombre: 'Ana', rol: 'CLIENTE'),
      );
}

class SinSesion extends AuthController {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

/// DAO en memoria. [fallarAlInsertar] simula un error de SQLite (disco lleno, base bloqueada).
class DaoMemoria extends CartDao {
  DaoMemoria() : super(AppDatabase());
  final filas = <String, CartItem>{};
  bool fallarAlInsertar = false;
  String _k(String u, CartItemType t, String id) => '$u|${t.name}|$id';

  @override
  Future<List<CartItem>> listar(String userId) async =>
      filas.entries.where((e) => e.key.startsWith('$userId|')).map((e) => e.value).toList();
  @override
  Future<void> insertar(String userId, CartItem item) async {
    if (fallarAlInsertar) throw StateError('database is locked');
    filas[_k(userId, item.tipo, item.itemId)] = item;
  }

  @override
  Future<void> eliminar(String userId, CartItemType tipo, String itemId) async =>
      filas.remove(_k(userId, tipo, itemId));
  @override
  Future<void> vaciar(String userId) async => filas.removeWhere((k, _) => k.startsWith('$userId|'));
}

Beat beat(String id, num precio) => Beat(id: id, nombre: 'Beat $id', genero: 'Trap', bpm: 140, precio: precio);

void main() {
  late ProviderContainer c;
  late DaoMemoria dao;
  CartController cart() => c.read(cartProvider.notifier);
  List<String> ids() => c.read(cartProvider).map((i) => i.itemId).toList();
  final pack = Pack(id: 'p1', nombre: 'Pack', precio: 500, beats: [beat('a', 300), beat('b', 300)]);

  ProviderContainer crear(AuthController Function() auth) => ProviderContainer(overrides: [
        authControllerProvider.overrideWith(auth),
        cartDaoProvider.overrideWithValue(dao),
      ])
        ..read(cartProvider);

  setUp(() {
    dao = DaoMemoria();
    c = crear(SesionIniciada.new);
  });
  tearDown(() => c.dispose());

  group('M3 · addPack — caminos independientes', () {
    test('P1 el paquete ya está en el carrito → rechazado', () async {
      await cart().addPack(pack, owned: {});
      final r = await cart().addPack(pack, owned: {});
      expect(r.ok, isFalse);
      expect(r.message, 'Este paquete ya está en tu carrito');
    });

    test('P2 ya tiene 1 beat del paquete → mensaje en singular', () async {
      final r = await cart().addPack(pack, owned: {'a'});
      expect(r.ok, isFalse);
      expect(r.message, 'Ya tienes 1 beat de este paquete');
      expect(ids(), isEmpty);
    });

    test('P3 ya tiene 2 beats del paquete → mensaje en plural', () async {
      final r = await cart().addPack(pack, owned: {'a', 'b'});
      expect(r.message, 'Ya tienes 2 beats de este paquete');
    });

    test('P4 sin beats sueltos repetidos: el ciclo no itera', () async {
      final r = await cart().addPack(pack, owned: {});
      expect(r.ok, isTrue);
      expect(r.message, 'Pack se agregó al carrito');
      expect(cart().total, 500);
    });

    test('P5 con beats sueltos repetidos: el ciclo los quita (no se pagan dos veces)', () async {
      await cart().addBeat(beat('a', 300), owned: {});
      await cart().addBeat(beat('b', 300), owned: {});
      await cart().addBeat(beat('c', 200), owned: {});
      final r = await cart().addPack(pack, owned: {});
      expect(r.ok, isTrue);
      expect(r.message, contains('Quitamos 2 beat(s)'));
      expect(ids(), ['c', 'p1']);
      expect(cart().total, 700, reason: '200 + 500, sin cobrar a y b sueltos');
      expect(dao.filas.length, 2, reason: 'SQLite queda igual que la memoria');
    });
  });

  group('M3 · addBeat — caminos independientes', () {
    test('P1 ya comprado', () async {
      expect((await cart().addBeat(beat('a', 1), owned: {'a'})).message, 'Ya compraste este beat');
    });
    test('P2 ya en el carrito', () async {
      await cart().addBeat(beat('a', 1), owned: {});
      expect((await cart().addBeat(beat('a', 1), owned: {})).message, 'Este beat ya está en tu carrito');
    });
    test('P3 ya viene en un paquete del carrito', () async {
      await cart().addPack(pack, owned: {});
      expect((await cart().addBeat(beat('b', 1), owned: {})).message, contains('paquete'));
    });
    test('P4 se agrega', () async {
      final r = await cart().addBeat(beat('a', 300), owned: {});
      expect(r.ok, isTrue);
      expect(ids(), ['a']);
    });
  });

  group('Sin sesión y excepciones', () {
    test('sin sesión no se informa "se agregó" si no se guardó nada', () async {
      // DEF-02: _insert() salía sin guardar cuando no había usuario, pero addBeat
      // y addPack devolvían ok = true y el mensaje "se agregó al carrito".
      c.dispose();
      c = crear(SinSesion.new);
      final r1 = await cart().addBeat(beat('a', 300), owned: {});
      final r2 = await cart().addPack(pack, owned: {});
      expect(r1.ok, isFalse);
      expect(r2.ok, isFalse);
      expect(ids(), isEmpty);
      expect(dao.filas, isEmpty);
    });

    test('si SQLite falla, el error llega a quien llama y el estado no cambia', () async {
      dao.fallarAlInsertar = true;
      await expectLater(cart().addBeat(beat('a', 300), owned: {}), throwsStateError);
      expect(ids(), isEmpty, reason: 'la memoria no debe mostrar algo que no se guardó');
    });

    test('total con valores límite: carrito vacío y precio 0', () async {
      expect(cart().total, 0);
      await cart().addBeat(beat('g', 0), owned: {});
      expect(cart().total, 0);
    });

    test('vaciar y quitar persisten en SQLite', () async {
      await cart().addBeat(beat('a', 1), owned: {});
      await cart().addBeat(beat('b', 2), owned: {});
      await cart().remove(c.read(cartProvider).first);
      expect(dao.filas.length, 1);
      await cart().clear();
      expect(dao.filas, isEmpty);
      expect(ids(), isEmpty);
    });
  });
}
