import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:skondit_beats_mobile/core/security/biometric_service.dart';
import 'package:skondit_beats_mobile/features/activity/data/acceso.dart';
import 'package:skondit_beats_mobile/features/auth/presentation/app_lock_controller.dart';

class FakeBiometrics extends BiometricService {
  FakeBiometrics({this.available = true, this.result = BiometricResult.success})
      : super(LocalAuthentication());

  bool available;
  BiometricResult result;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricResult> authenticate(String reason) async => result;
}

void main() {
  late FakeBiometrics bio;
  late ProviderContainer container;
  AppLockController lock() => container.read(appLockProvider.notifier);
  bool locked() => container.read(appLockProvider);

  setUp(() {
    bio = FakeBiometrics();
    container = ProviderContainer(overrides: [biometricServiceProvider.overrideWithValue(bio)]);
  });
  tearDown(() => container.dispose());

  test('se bloquea si el teléfono tiene bloqueo de pantalla', () async {
    await lock().lockIfAvailable();
    expect(locked(), isTrue);
  });

  test('no se bloquea si el teléfono no tiene bloqueo de pantalla', () async {
    bio.available = false;
    await lock().lockIfAvailable();
    expect(locked(), isFalse);
  });

  test('una pausa corta no bloquea la app', () async {
    lock().onPaused();
    await lock().onResumed(authenticated: true);
    expect(locked(), isFalse);
  });

  test('la cámara/galería no cuenta como inactividad', () async {
    await lock().runWithoutLock(() async => lock().onPaused());
    await lock().onResumed(authenticated: true);
    expect(locked(), isFalse);
  });

  test('desbloquear con biometría correcta / cancelada', () async {
    await lock().lockIfAvailable();
    bio.result = BiometricResult.canceled;
    expect(await lock().unlockWithBiometrics(), BiometricResult.canceled);
    expect(locked(), isTrue);
    bio.result = BiometricResult.success;
    expect(await lock().unlockWithBiometrics(), BiometricResult.success);
    expect(locked(), isFalse);
  });

  test('Acceso se convierte a fila SQLite y de regreso', () {
    final a = Acceso(email: 'a@b.com', metodo: MetodoAcceso.biometria, fecha: DateTime(2026, 10, 8, 9, 30));
    final b = Acceso.fromMap({...a.toMap(), 'id': 1});
    expect(b.id, 1);
    expect(b.email, a.email);
    expect(b.metodo, a.metodo);
    expect(b.fecha, a.fecha);
  });
}
