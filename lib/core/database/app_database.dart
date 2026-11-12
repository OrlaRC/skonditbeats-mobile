import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Base de datos local (SQLite). Misma organización que la Práctica 4:
/// entidad → DAO → base de datos.
///
/// Versiones:
///   1. accesos (historial de inicios de sesión del dispositivo)
///   2. carrito (artículos por usuario)
///   3. transferencias (subidas y descargas reanudables)
class AppDatabase {
  static const _name = 'skondit.db';
  static const _version = 3;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _name);
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await _crearAccesos(db);
        await _crearCarrito(db);
        await _crearTransferencias(db);
      },
      // Migraciones: cada teléfono solo crea las tablas que le faltan.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _crearCarrito(db);
        if (oldVersion < 3) await _crearTransferencias(db);
      },
    );
  }

  static Future<void> _crearAccesos(Database db) async {
    await db.execute('''
      CREATE TABLE accesos (
        id     INTEGER PRIMARY KEY AUTOINCREMENT,
        email  TEXT    NOT NULL,
        metodo TEXT    NOT NULL,
        fecha  TEXT    NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_accesos_email ON accesos (email)');
  }

  static Future<void> _crearCarrito(Database db) async {
    await db.execute('''
      CREATE TABLE carrito (
        user_id    TEXT    NOT NULL,
        tipo       TEXT    NOT NULL CHECK (tipo IN ('beat', 'pack')),
        item_id    TEXT    NOT NULL,
        nombre     TEXT    NOT NULL,
        detalle    TEXT    NOT NULL,
        precio     REAL    NOT NULL,
        imagen_url TEXT,
        beat_ids   TEXT    NOT NULL DEFAULT '',
        agregado   TEXT    NOT NULL,
        PRIMARY KEY (user_id, tipo, item_id)
      )
    ''');
  }

  static Future<void> _crearTransferencias(Database db) async {
    await db.execute('''
      CREATE TABLE transferencias (
        id             TEXT    PRIMARY KEY,
        user_id        TEXT    NOT NULL,
        tipo           TEXT    NOT NULL CHECK (tipo IN ('subida', 'descarga')),
        titulo         TEXT    NOT NULL,
        estado         TEXT    NOT NULL,
        ruta_local     TEXT    NOT NULL,
        bucket         TEXT,
        mime           TEXT,
        nombre_remoto  TEXT,
        url            TEXT,
        token          TEXT,
        url_publica    TEXT,
        etag           TEXT,
        total          INTEGER NOT NULL DEFAULT 0,
        avance         INTEGER NOT NULL DEFAULT 0,
        carga_completa INTEGER NOT NULL DEFAULT 0,
        destino        TEXT,
        error          TEXT,
        intentos       INTEGER NOT NULL DEFAULT 0,
        creada         TEXT    NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_transferencias_user ON transferencias (user_id, creada)');
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
