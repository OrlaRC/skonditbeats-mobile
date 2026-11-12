import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../catalog/domain/beat.dart';
import '../../catalog/domain/pack.dart';
import '../data/cart_dao.dart';
import '../domain/cart_item.dart';

/// Resultado de agregar algo al carrito, con el mensaje para el usuario.
class CartResult {
  const CartResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Carrito del usuario actual. Se guarda en SQLite y se recarga al cambiar de cuenta.
///
/// Reglas (para que el pago no falle a medias en la API):
///  - no se repiten artículos,
///  - no se agregan beats que el usuario ya compró,
///  - un beat no puede estar suelto y dentro de un paquete a la vez.
class CartController extends Notifier<List<CartItem>> {
  String? _userId;

  CartDao get _dao => ref.read(cartDaoProvider);

  @override
  List<CartItem> build() {
    _userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
    if (_userId != null) _load(_userId!);
    return const [];
  }

  Future<void> _load(String userId) async {
    final items = await _dao.listar(userId);
    if (_userId == userId) state = items;
  }

  num get total => state.fold<num>(0, (s, i) => s + i.precio);

  bool contains(CartItemType tipo, String id) =>
      state.any((i) => i.tipo == tipo && i.itemId == id);

  /// true si el beat ya está en el carrito, suelto o dentro de un paquete.
  bool containsBeat(String beatId) => state.any((i) => i.beatIds.contains(beatId));

  Future<CartResult> addBeat(Beat beat, {required Set<String> owned}) async {
    if (owned.contains(beat.id)) return const CartResult(false, 'Ya compraste este beat');
    if (contains(CartItemType.beat, beat.id)) {
      return const CartResult(false, 'Este beat ya está en tu carrito');
    }
    if (containsBeat(beat.id)) {
      return const CartResult(false, 'Este beat ya viene en un paquete de tu carrito');
    }
    await _insert(CartItem.fromBeat(beat));
    return CartResult(true, '${beat.nombre} se agregó al carrito');
  }

  Future<CartResult> addPack(Pack pack, {required Set<String> owned}) async {
    if (contains(CartItemType.pack, pack.id)) {
      return const CartResult(false, 'Este paquete ya está en tu carrito');
    }
    final yaTiene = pack.beats.where((b) => owned.contains(b.id)).length;
    if (yaTiene > 0) {
      return CartResult(false, 'Ya tienes $yaTiene beat${yaTiene == 1 ? '' : 's'} de este paquete');
    }

    // Los beats sueltos que ya vienen en el paquete se quitan para no pagarlos dos veces.
    final repetidos = state
        .where((i) => !i.isPack && pack.beats.any((b) => b.id == i.itemId))
        .toList();
    for (final r in repetidos) {
      await remove(r);
    }

    await _insert(CartItem.fromPack(pack));
    return CartResult(
      true,
      repetidos.isEmpty
          ? '${pack.nombre} se agregó al carrito'
          : '${pack.nombre} se agregó. Quitamos ${repetidos.length} beat(s) sueltos que ya incluye.',
    );
  }

  Future<void> remove(CartItem item) async {
    final uid = _userId;
    if (uid == null) return;
    await _dao.eliminar(uid, item.tipo, item.itemId);
    state = state.where((i) => !(i.tipo == item.tipo && i.itemId == item.itemId)).toList();
  }

  /// Quita lo que el usuario ya tiene, por ejemplo si lo compró en otro
  /// dispositivo con la misma cuenta. Devuelve los artículos quitados.
  Future<List<CartItem>> removeOwned(Set<String> owned) async {
    final comprados = state.where((i) => i.beatIds.any(owned.contains)).toList();
    for (final item in comprados) {
      await remove(item);
    }
    return comprados;
  }

  Future<void> clear() async {
    final uid = _userId;
    if (uid == null) return;
    await _dao.vaciar(uid);
    state = const [];
  }

  Future<void> _insert(CartItem item) async {
    final uid = _userId;
    if (uid == null) return;
    await _dao.insertar(uid, item);
    state = [...state, item];
  }
}

final cartProvider = NotifierProvider<CartController, List<CartItem>>(CartController.new);
