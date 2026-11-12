import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/user.dart';

/// Guarda la sesión cifrada: Android Keystore / iOS Keychain.
/// Nunca se usa shared_preferences para el token (queda en texto plano).
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  // Públicas para que la tarea de avisos en segundo plano lea la misma sesión.
  static const tokenKey = 'skondit_token';
  static const userKey = 'skondit_user';
  static const _tokenKey = tokenKey;
  static const _userKey = userKey;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<User?> readUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(String token, User user) async {
    await _storage.write(key: _tokenKey, value: token);
    await saveUser(user);
  }

  Future<void> saveUser(User user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}

/// Almacén cifrado crudo (Keystore / Keychain), compartido con los avisos.
final rawSecureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  ),
);

final secureStorageProvider = Provider<SecureStorage>((ref) => SecureStorage(ref.watch(rawSecureStorageProvider)));
