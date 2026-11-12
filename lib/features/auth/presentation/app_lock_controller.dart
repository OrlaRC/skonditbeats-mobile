import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/biometric_service.dart';

/// Bloqueo de la app con biometría. true = bloqueada.
///
/// Se bloquea al reabrir la app con una sesión guardada y cuando la app
/// pasa más de [inactividad] en segundo plano.
class AppLockController extends Notifier<bool> {
  static const inactividad = Duration(seconds: 30);

  DateTime? _pausadaDesde;
  int _suspendido = 0;

  BiometricService get _bio => ref.read(biometricServiceProvider);

  @override
  bool build() => false;

  Future<void> lockIfAvailable() async {
    if (await _bio.isAvailable()) state = true;
  }

  void unlock() => state = false;

  Future<BiometricResult> unlockWithBiometrics() async {
    final result = await runWithoutLock(
      () => _bio.authenticate('Confirma tu identidad para entrar a SkonditBeats'),
    );
    if (result == BiometricResult.success) state = false;
    return result;
  }

  void onPaused() {
    if (_suspendido == 0) _pausadaDesde = DateTime.now();
  }

  Future<void> onResumed({required bool authenticated}) async {
    final desde = _pausadaDesde;
    _pausadaDesde = null;
    if (!authenticated || desde == null || state) return;
    if (DateTime.now().difference(desde) >= inactividad) await lockIfAvailable();
  }

  /// Para acciones que mandan la app a segundo plano a propósito
  /// (cámara, galería, diálogo biométrico) sin que eso la bloquee.
  Future<T> runWithoutLock<T>(Future<T> Function() action) async {
    _suspendido++;
    try {
      return await action();
    } finally {
      _suspendido--;
    }
  }
}

final appLockProvider = NotifierProvider<AppLockController, bool>(AppLockController.new);
