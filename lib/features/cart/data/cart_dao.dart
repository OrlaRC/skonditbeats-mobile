import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/cart_item.dart';

/// DAO de la tabla carrito. Cada usuario tiene su propio carrito en el teléfono.
class CartDao {
  CartDao(this._db);

  final AppDatabase _db;

  Future<List<CartItem>> listar(String userId) async {
    final rows = await (await _db.database).query(
      'carrito',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'agregado ASC',
    );
    return rows.map(CartItem.fromMap).toList();
  }

  Future<void> insertar(String userId, CartItem item) async {
    await (await _db.database).insert(
      'carrito',
      item.toMap(userId),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> eliminar(String userId, CartItemType tipo, String itemId) async {
    await (await _db.database).delete(
      'carrito',
      where: 'user_id = ? AND tipo = ? AND item_id = ?',
      whereArgs: [userId, tipo.name, itemId],
    );
  }

  Future<void> vaciar(String userId) async {
    await (await _db.database).delete('carrito', where: 'user_id = ?', whereArgs: [userId]);
  }
}

final cartDaoProvider = Provider<CartDao>((ref) => CartDao(ref.watch(appDatabaseProvider)));
