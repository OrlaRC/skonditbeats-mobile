import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/database/app_database.dart';
import 'package:skondit_beats_mobile/core/utils/card_formatters.dart';
import 'package:skondit_beats_mobile/core/utils/money.dart';
import 'package:skondit_beats_mobile/core/utils/validators.dart';
import 'package:skondit_beats_mobile/features/auth/domain/user.dart';
import 'package:skondit_beats_mobile/features/auth/presentation/auth_controller.dart';
import 'package:skondit_beats_mobile/features/cart/data/cart_dao.dart';
import 'package:skondit_beats_mobile/features/cart/domain/cart_item.dart';
import 'package:skondit_beats_mobile/features/cart/presentation/cart_controller.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/beat.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/pack.dart';
import 'package:skondit_beats_mobile/features/checkout/data/orders_repository.dart';

class FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthState.authenticated(
        User(id: 'u1', email: 'a@b.com', nombre: 'Ana', rol: 'CLIENTE'),
      );
}

class MemoryCartDao extends CartDao {
  MemoryCartDao() : super(AppDatabase());
  final rows = <String, CartItem>{};
  String _k(String u, CartItemType t, String id) => '$u|${t.name}|$id';

  @override
  Future<List<CartItem>> listar(String userId) async =>
      rows.entries.where((e) => e.key.startsWith('$userId|')).map((e) => e.value).toList();
  @override
  Future<void> insertar(String userId, CartItem item) async => rows[_k(userId, item.tipo, item.itemId)] = item;
  @override
  Future<void> eliminar(String userId, CartItemType tipo, String itemId) async => rows.remove(_k(userId, tipo, itemId));
  @override
  Future<void> vaciar(String userId) async => rows.removeWhere((k, _) => k.startsWith('$userId|'));
}

Beat beat(String id, num precio) =>
    Beat(id: id, nombre: 'Beat $id', genero: 'Trap', bpm: 140, precio: precio);

void main() {
  group('Carrito', () {
    late ProviderContainer c;
    late MemoryCartDao dao;
    CartController cart() => c.read(cartProvider.notifier);
    final pack = Pack(id: 'p1', nombre: 'Pack', precio: 500, beats: [beat('a', 300), beat('b', 300)]);

    setUp(() {
      dao = MemoryCartDao();
      c = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(FakeAuth.new),
        cartDaoProvider.overrideWithValue(dao),
      ]);
      c.read(cartProvider);
    });
    tearDown(() => c.dispose());

    test('no repite beats ni agrega los ya comprados', () async {
      expect((await cart().addBeat(beat('a', 300), owned: {})).ok, isTrue);
      expect((await cart().addBeat(beat('a', 300), owned: {})).ok, isFalse);
      expect((await cart().addBeat(beat('z', 100), owned: {'z'})).ok, isFalse);
      expect(c.read(cartProvider), hasLength(1));
      expect(dao.rows, hasLength(1)); // se guardó en "SQLite"
    });

    test('al agregar un paquete quita los beats sueltos que incluye', () async {
      await cart().addBeat(beat('a', 300), owned: {});
      await cart().addBeat(beat('c', 200), owned: {});
      final r = await cart().addPack(pack, owned: {});
      expect(r.ok, isTrue);
      expect(c.read(cartProvider).map((i) => i.itemId), ['c', 'p1']);
      expect(cart().total, 700);
    });

    test('no deja agregar un beat que ya viene en un paquete del carrito', () async {
      await cart().addPack(pack, owned: {});
      expect((await cart().addBeat(beat('b', 300), owned: {})).ok, isFalse);
    });

    test('no deja comprar un paquete si ya tienes alguno de sus beats', () async {
      final r = await cart().addPack(pack, owned: {'b'});
      expect(r.ok, isFalse);
      expect(r.message, contains('Ya tienes 1'));
    });

    test('quita lo que ya se compró en otro dispositivo, suelto o en paquete', () async {
      await cart().addBeat(beat('c', 200), owned: {});
      await cart().addBeat(beat('d', 100), owned: {});
      await cart().addPack(pack, owned: {});

      final quitados = await cart().removeOwned({'c', 'b'});

      expect(quitados.map((i) => i.itemId), ['c', 'p1']);
      expect(c.read(cartProvider).map((i) => i.itemId), ['d']);
      expect(dao.rows, hasLength(1));
    });
  });

  test('las órdenes se agrupan como espera la API', () {
    final items = [
      CartItem.fromBeat(beat('a', 1)),
      CartItem.fromPack(Pack(id: 'p1', nombre: 'P', precio: 1, beats: const [])),
      CartItem.fromBeat(beat('b', 1)),
      CartItem.fromPack(Pack(id: 'p2', nombre: 'P2', precio: 1, beats: const [])),
    ];
    final g = groupForCheckout(items);
    expect(g.map((x) => x.map((i) => i.itemId).toList()).toList(), [
      ['a', 'b'],
      ['p1'],
      ['p2'],
    ]);
  });

  test('CartItem ida y vuelta a fila SQLite', () {
    final item = CartItem.fromPack(Pack(id: 'p1', nombre: 'P', precio: 500, beats: [beat('a', 1), beat('b', 1)]));
    final back = CartItem.fromMap(item.toMap('u1'));
    expect(back.isPack, isTrue);
    expect(back.beatIds, ['a', 'b']);
    expect(back.precio, 500);
  });

  test('ahorro del paquete', () {
    final p = Pack(id: 'p', nombre: 'P', precio: 1000, beats: [beat('a', 249), beat('b', 300), beat('c', 299)]);
    expect(p.precioSeparado, 848);
    expect(p.ahorro, 0); // el paquete cuesta más que separado: no se muestra ahorro
  });

  test('formato de precios y números de la API', () {
    expect(formatMoney(1000), r'$1,000 MXN');
    expect(formatMoney(249, currency: false), r'$249');
    expect(formatMoney(1234567), r'$1,234,567 MXN');
    expect(parseNum('300'), 300);
    expect(parseNum(null), 0);
  });

  group('Tarjeta', () {
    test('número con Luhn', () {
      expect(Validators.cardNumber('4242 4242 4242 4242'), isNull);
      expect(Validators.cardNumber('4242 4242 4242 4241'), isNotNull);
      expect(Validators.cardNumber('4242'), isNotNull);
    });

    test('vencimiento', () {
      final hoy = DateTime(2026, 10, 8);
      expect(Validators.cardExpiry('12/28', now: hoy), isNull);
      expect(Validators.cardExpiry('10/26', now: hoy), isNull);
      expect(Validators.cardExpiry('09/26', now: hoy), 'La tarjeta está vencida');
      expect(Validators.cardExpiry('13/28', now: hoy), 'Mes no válido');
      expect(Validators.cardExpiry('1228', now: hoy), isNotNull);
    });

    test('formateadores', () {
      TextEditingValue v(String t) => TextEditingValue(text: t);
      expect(CardNumberFormatter().formatEditUpdate(v(''), v('42424242424242429999')).text,
          '4242 4242 4242 4242');
      expect(CardExpiryFormatter().formatEditUpdate(v('1'), v('12')).text, '12/');
      expect(CardExpiryFormatter().formatEditUpdate(v('12/'), v('12')).text, '12');
      expect(CardExpiryFormatter().formatEditUpdate(v('12/2'), v('12/28')).text, '12/28');
      expect(cardBrand('4242'), 'Visa');
    });
  });
}
