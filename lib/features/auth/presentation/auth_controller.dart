import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../activity/data/acceso.dart';
import '../../activity/data/acceso_dao.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';
import 'app_lock_controller.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState._(this.status, [this.user]);

  const AuthState.unknown() : this._(AuthStatus.unknown);
  const AuthState.unauthenticated() : this._(AuthStatus.unauthenticated);
  const AuthState.authenticated(User user) : this._(AuthStatus.authenticated, user);

  final AuthStatus status;
  final User? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// Estado global de la sesión. El router escucha este provider para
/// redirigir según el usuario esté o no logueado y según su rol.
class AuthController extends Notifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  SecureStorage get _storage => ref.read(secureStorageProvider);
  AppLockController get _lock => ref.read(appLockProvider.notifier);

  @override
  AuthState build() {
    _restoreSession();
    return const AuthState.unknown();
  }

  Future<void> _restoreSession() async {
    final token = await _storage.readToken();
    final user = await _storage.readUser();
    if (token == null || user == null) {
      state = const AuthState.unauthenticated();
      return;
    }
    // Sesión guardada: se pide biometría antes de mostrar la app.
    await _lock.lockIfAvailable();
    state = AuthState.authenticated(user);
  }

  /// Devuelve [LoginNeedsOtp] si el usuario debe capturar el código.
  Future<LoginResult> login(String email, String password) async {
    final result = await _repo.login(email, password);
    if (result is LoginSuccess) await _startSession(result, MetodoAcceso.password);
    return result;
  }

  Future<void> verifyOtp(String email, String code) async {
    await _startSession(await _repo.verifyOtp(email, code), MetodoAcceso.passwordOtp);
  }

  Future<void> register(RegisterData data) async {
    await _startSession(await _repo.register(data), MetodoAcceso.registro);
  }

  Future<void> logout() async {
    await _repo.logout();
    await _storage.clear();
    _lock.unlock();
    state = const AuthState.unauthenticated();
  }

  /// Registra el desbloqueo biométrico en el historial local.
  Future<void> registerBiometricUnlock() async {
    final user = state.user;
    if (user != null) await _registrarAcceso(user.email, MetodoAcceso.biometria);
  }

  Future<void> updateFoto(String fotoUrl) async {
    final user = state.user;
    if (user == null) return;
    final updated = user.copyWith(fotoUrl: fotoUrl);
    await _storage.saveUser(updated);
    state = AuthState.authenticated(updated);
  }

  Future<void> _startSession(LoginSuccess s, String metodo) async {
    await _storage.saveSession(s.token, s.user);
    await _registrarAcceso(s.user.email, metodo);
    _lock.unlock();
    state = AuthState.authenticated(s.user);
  }

  Future<void> _registrarAcceso(String email, String metodo) async {
    try {
      await ref
          .read(accesoDaoProvider)
          .insertar(Acceso(email: email, metodo: metodo, fecha: DateTime.now()));
    } catch (_) {
      // El historial local nunca debe impedir el inicio de sesión.
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
