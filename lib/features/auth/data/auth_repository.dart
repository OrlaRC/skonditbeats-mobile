import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/user.dart';

/// Resultado del login: el admin entra directo, el cliente necesita OTP.
sealed class LoginResult {}

class LoginSuccess extends LoginResult {
  LoginSuccess(this.token, this.user);
  final String token;
  final User user;
}

class LoginNeedsOtp extends LoginResult {
  LoginNeedsOtp({required this.email, required this.message, this.otpDev});
  final String email;
  final String message;

  /// Solo llega en desarrollo cuando el backend no pudo enviar el correo.
  final String? otpDev;
}

class RegisterData {
  const RegisterData({
    required this.nombre,
    required this.email,
    required this.password,
    required this.edad,
    this.username,
    this.telefono,
  });

  final String nombre;
  final String email;
  final String password;
  final int edad;
  final String? username;
  final String? telefono;

  Map<String, dynamic> toJson() => {
        'nombre': nombre.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
        'edad': edad,
        if (username != null && username!.trim().isNotEmpty) 'username': username!.trim(),
        if (telefono != null && telefono!.trim().isNotEmpty) 'telefono': telefono!.trim(),
      };
}

/// Endpoints de /api/auth (mismos que consume la web).
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<LoginResult> login(String email, String password) async {
    final data = await _post('/auth/login', {
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    if (data['requires2fa'] == true) {
      return LoginNeedsOtp(
        email: data['email'] as String,
        message: (data['message'] as String?) ?? 'Código enviado a tu correo',
        otpDev: data['otpDev'] as String?,
      );
    }
    return LoginSuccess(data['token'] as String, User.fromJson(data['user']));
  }

  Future<LoginSuccess> verifyOtp(String email, String code) async {
    final data = await _post('/auth/verify-otp', {'email': email, 'code': code});
    return LoginSuccess(data['token'] as String, User.fromJson(data['user']));
  }

  Future<LoginSuccess> register(RegisterData body) async {
    final data = await _post('/auth/register', body.toJson());
    return LoginSuccess(data['token'] as String, User.fromJson(data['user']));
  }

  /// Registra el cierre de sesión en la bitácora. Si falla no importa.
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout', data: {});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      return res.data ?? {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});
