import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/transferencia.dart';

/// DAO de la tabla transferencias: la cola de subidas y descargas de cada usuario.
class TransferenciaDao {
  TransferenciaDao(this._db);

  final AppDatabase _db;

  Future<List<Transferencia>> listar(String userId) async {
    final rows = await (await _db.database).query(
      'transferencias',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'creada ASC',
    );
    return rows.map(Transferencia.fromMap).toList();
  }

  Future<void> guardar(Transferencia t) async {
    await (await _db.database).insert(
      'transferencias',
      t.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> eliminar(String id) async {
    await (await _db.database).delete('transferencias', where: 'id = ?', whereArgs: [id]);
  }
}

final transferenciaDaoProvider =
    Provider<TransferenciaDao>((ref) => TransferenciaDao(ref.watch(appDatabaseProvider)));
