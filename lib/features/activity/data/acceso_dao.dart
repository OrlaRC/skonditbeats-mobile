import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'acceso.dart';

/// DAO de la tabla accesos (operaciones CRUD).
class AccesoDao {
  AccesoDao(this._db);

  final AppDatabase _db;

  Future<int> insertar(Acceso acceso) async =>
      (await _db.database).insert('accesos', acceso.toMap());

  Future<List<Acceso>> listarPorEmail(String email, {int limite = 20}) async {
    final rows = await (await _db.database).query(
      'accesos',
      where: 'email = ?',
      whereArgs: [email],
      orderBy: 'fecha DESC',
      limit: limite,
    );
    return rows.map(Acceso.fromMap).toList();
  }

  Future<int> eliminarPorEmail(String email) async =>
      (await _db.database).delete('accesos', where: 'email = ?', whereArgs: [email]);
}

final accesoDaoProvider = Provider<AccesoDao>((ref) => AccesoDao(ref.watch(appDatabaseProvider)));
