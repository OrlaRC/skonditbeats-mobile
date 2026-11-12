import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricResult { success, canceled, lockedOut, unavailable, failed }

/// Envoltura de local_auth: huella, rostro o, como respaldo, el PIN/patrón del teléfono.
class BiometricService {
  BiometricService(this._auth);

  final LocalAuthentication _auth;

  /// true si el teléfono tiene algún bloqueo de pantalla configurado
  /// (biometría o PIN/patrón). Sin bloqueo no tiene sentido pedirlo.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout => BiometricResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => BiometricResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware => BiometricResult.unavailable,
        _ => BiometricResult.failed,
      };
    } catch (_) {
      return BiometricResult.failed;
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(LocalAuthentication()),
);
