import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';

class Profile {
  const Profile({
    required this.nombre,
    required this.email,
    required this.rol,
    this.username,
    this.telefono,
    this.edad,
    this.fotoUrl,
    this.fechaRegistro,
  });

  final String nombre;
  final String email;
  final String rol;
  final String? username;
  final String? telefono;
  final int? edad;
  final String? fotoUrl;
  final DateTime? fechaRegistro;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        nombre: (j['nombre'] as String?) ?? '',
        email: j['email'] as String,
        rol: (j['rol'] as String?) ?? 'CLIENTE',
        username: j['username'] as String?,
        telefono: j['telefono'] as String?,
        edad: (j['edad'] as num?)?.toInt(),
        fotoUrl: j['foto_url'] as String?,
        fechaRegistro: DateTime.tryParse((j['fecha_registro'] as String?) ?? ''),
      );
}

/// Perfil del usuario y subida de la foto por URL preasignada (Práctica 3):
///   1. La API genera una URL firmada de Supabase Storage (/uploads/presign).
///   2. La app sube el archivo DIRECTO a esa URL (no pasa por la API).
///   3. La API guarda la URL pública en el perfil (/profile/foto).
class ProfileRepository {
  ProfileRepository(this._api);

  final Dio _api;

  /// Límite definido en el documento del proyecto para fotos de perfil.
  static const maxFotoBytes = 1024 * 1024; // 1 MB

  static const _mimePorExtension = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
  };

  Future<Profile> fetch() async {
    try {
      final res = await _api.get<Map<String, dynamic>>('/profile');
      return Profile.fromJson(res.data!['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Valida la foto antes de encolarla y devuelve su tipo MIME.
  static Future<String> validarFoto(File file) async {
    final mime = _mimePorExtension[p.extension(file.path).toLowerCase()];
    if (mime == null) throw ApiException('Formato no permitido. Usa JPG, PNG o WebP.');
    final bytes = await file.length();
    if (bytes > maxFotoBytes) {
      throw ApiException('La foto pesa ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB; el máximo es 1 MB.');
    }
    return mime;
  }

  /// Valida, sube la foto en una sola pieza y devuelve su URL pública.
  /// (La app usa la cola reanudable; esto queda para pruebas y compatibilidad.)
  Future<String> uploadFoto(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    final mime = _mimePorExtension[ext];
    if (mime == null) throw ApiException('Formato no permitido. Usa JPG, PNG o WebP.');

    final bytes = await file.readAsBytes();
    if (bytes.length > maxFotoBytes) {
      throw ApiException('La foto pesa ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB; '
          'el máximo es 1 MB.');
    }

    try {
      // 1. URL firmada
      final presign = (await _api.post<Map<String, dynamic>>('/uploads/presign', data: {
        'bucket': 'avatars',
        'contentType': mime,
        'fileName': 'avatar$ext',
      }))
          .data!;

      // 2. Subida directa a Supabase Storage. Se usa un Dio limpio para
      //    no mandar nuestro JWT a un servicio externo.
      await Dio().put<void>(
        presign['signedUrl'] as String,
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {
          Headers.contentTypeHeader: mime,
          Headers.contentLengthHeader: bytes.length,
          'x-upsert': 'true',
          'cache-control': 'public, max-age=31536000',
        }),
      );

      // 3. Guardar la URL en el perfil
      final publicUrl = presign['publicUrl'] as String;
      await _api.put<void>('/profile/foto', data: {'foto_url': publicUrl});
      return publicUrl;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(dioProvider)));
