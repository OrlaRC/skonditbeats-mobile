// Prácticas 13 y 14 · AUT-06 (persistencia) · SQLite REAL (sqflite_common_ffi), con el
// mismo esquema y los mismos DAO que usa la app en el teléfono. No se simula la base.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skondit_beats_mobile/core/database/app_database.dart';
import 'package:skondit_beats_mobile/features/activity/data/acceso.dart';
import 'package:skondit_beats_mobile/features/activity/data/acceso_dao.dart';
import 'package:skondit_beats_mobile/features/auth/domain/user.dart';
import 'package:skondit_beats_mobile/features/auth/presentation/auth_controller.dart';
import 'package:skondit_beats_mobile/features/cart/data/cart_dao.dart';
import 'package:skondit_beats_mobile/features/cart/domain/cart_item.dart';
import 'package:skondit_beats_mobile/features/cart/presentation/cart_controller.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/beat.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Beat beat(String id, num precio) => Beat(id: id, nombre: 'Beat $id', genero: 'Trap', bpm: 140, precio: precio);

class ConSesion extends AuthController {
  @override
  AuthState build() => const AuthState.authenticated(User(id: 'u1', email: 'a@b.com', nombre: 'Ana', rol: 'CLIENTE'));
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory carpeta;
  late AppDatabase db;
  late CartDao carrito;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('skondit_p13_');
    db = AppDatabase(ruta: p.join(carpeta.path, 'skondit.db'));
    carrito = CartDao(db);
  });
  tearDown(() async {
    await db.cerrar();
    await carpeta.delete(recursive: true);
  });

  group('AUT-06 · Carrito en SQLite', () {
    test('a · guardar y leer: cada usuario ve solo lo suyo, en orden de llegada', () async {
      final a = CartItem.fromBeat(beat('a', 300));
      final b = CartItem.fromPack(Pack(id: 'p1', nombre: 'Pack', precio: 500, beats: [beat('x', 1), beat('y', 1)]));
      await carrito.insertar('u1', a);
      await carrito.insertar('u1', b);
      await carrito.insertar('u2', CartItem.fromBeat(beat('z', 100)));

      final u1 = await carrito.listar('u1');
      expect(u1.map((i) => i.itemId), ['a', 'p1']);
      expect(u1[1].beatIds, ['x', 'y']);
      expect(u1[1].precio, 500);
      expect((await carrito.listar('u2')).single.itemId, 'z');
      expect(await carrito.listar('nadie'), isEmpty);
    });

    test('b · el mismo artículo dos veces no se duplica (llave primaria)', () async {
      final a = CartItem.fromBeat(beat('a', 300));
      await carrito.insertar('u1', a);
      await carrito.insertar('u1', a);
      expect(await carrito.listar('u1'), hasLength(1));
    });

    test('c · eliminar uno y vaciar solo el carrito del usuario', () async {
      for (final id in ['a', 'b', 'c']) {
        await carrito.insertar('u1', CartItem.fromBeat(beat(id, 1)));
      }
      await carrito.insertar('u2', CartItem.fromBeat(beat('a', 1)));

      await carrito.eliminar('u1', CartItemType.beat, 'b');
      expect((await carrito.listar('u1')).map((i) => i.itemId), ['a', 'c']);

      await carrito.vaciar('u1');
      expect(await carrito.listar('u1'), isEmpty);
      expect(await carrito.listar('u2'), hasLength(1)); // el de otro usuario sigue
    });

    test('d · lo guardado sobrevive a cerrar y volver a abrir la app', () async {
      await carrito.insertar('u1', CartItem.fromBeat(beat('a', 300)));
      await db.cerrar();

      final reabierta = AppDatabase(ruta: db.ruta);
      final leido = await CartDao(reabierta).listar('u1');
      await reabierta.cerrar();
      expect(leido.single.nombre, 'Beat a');
    });

    test('e · la base rechaza un tipo de artículo inválido (CHECK)', () async {
      final base = await db.database;
      await expectLater(
        base.insert('carrito', {
          ...CartItem.fromBeat(beat('a', 1)).toMap('u1'),
          'tipo': 'cupon',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('f · integración controlador → DAO → SQLite: agregar al carrito queda guardado', () async {
      final c = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(ConSesion.new),
        cartDaoProvider.overrideWithValue(carrito),
      ]);
      addTearDown(c.dispose);
      c.read(cartProvider);

      final r = await c.read(cartProvider.notifier).addBeat(beat('a', 300), owned: {});
      expect(r.ok, isTrue);
      // Ya comprado → no se guarda.
      final r2 = await c.read(cartProvider.notifier).addBeat(beat('b', 300), owned: {'b'});
      expect(r2.ok, isFalse);

      expect((await carrito.listar('u1')).map((i) => i.itemId), ['a']);
    });
  });

  group('AUT-06 · Historial de accesos y migraciones', () {
    test('g · accesos: más reciente primero y con límite', () async {
      final dao = AccesoDao(db);
      for (var d = 1; d <= 5; d++) {
        await dao.insertar(Acceso(email: 'a@b.com', metodo: MetodoAcceso.password, fecha: DateTime(2026, 11, d)));
      }
      await dao.insertar(Acceso(email: 'otro@b.com', metodo: MetodoAcceso.registro, fecha: DateTime(2026, 11, 9)));

      final ultimos = await dao.listarPorEmail('a@b.com', limite: 3);
      expect(ultimos.map((a) => a.fecha.day), [5, 4, 3]);
      expect(ultimos.first.id, isNotNull);
      expect(await dao.eliminarPorEmail('a@b.com'), 5);
      expect(await dao.listarPorEmail('a@b.com'), isEmpty);
    });

    test('h · un teléfono con la versión 1 de la base migra a la ${AppDatabase.version} sin perder datos', () async {
      // Base como la dejó la primera versión de la app: solo la tabla accesos.
      final v1 = await databaseFactory.openDatabase(db.ruta!,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (d, _) async {
              await d.execute('CREATE TABLE accesos (id INTEGER PRIMARY KEY AUTOINCREMENT, '
                  'email TEXT NOT NULL, metodo TEXT NOT NULL, fecha TEXT NOT NULL)');
              await d.insert('accesos', {'email': 'viejo@b.com', 'metodo': 'Contraseña', 'fecha': '2025-01-01T00:00:00.000'});
            },
          ));
      await v1.close();

      final base = await db.database;
      expect(await base.getVersion(), AppDatabase.version);
      final tablas = (await base.query('sqlite_master', columns: ['name'], where: "type = 'table'"))
          .map((r) => r['name'])
          .toSet();
      expect(tablas, containsAll(['accesos', 'carrito', 'transferencias']));
      expect((await AccesoDao(db).listarPorEmail('viejo@b.com')).single.metodo, 'Contraseña');
      await carrito.insertar('u1', CartItem.fromBeat(beat('a', 1)));
      expect(await carrito.listar('u1'), hasLength(1));
    });
  });
}
