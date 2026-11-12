import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/biometric_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../app_lock_controller.dart';
import '../auth_controller.dart';

/// Se muestra cuando hay sesión guardada y la app está bloqueada.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _autenticando = false;

  @override
  void initState() {
    super.initState();
    // Lanza el diálogo en cuanto aparece la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_autenticando) return;
    setState(() => _autenticando = true);

    final result = await ref.read(appLockProvider.notifier).unlockWithBiometrics();
    if (!mounted) return;
    setState(() => _autenticando = false);

    switch (result) {
      case BiometricResult.success:
        HapticFeedback.lightImpact();
        await ref.read(authControllerProvider.notifier).registerBiometricUnlock();
      case BiometricResult.canceled:
        break;
      case BiometricResult.lockedOut:
        HapticFeedback.heavyImpact();
        showAppSnack(context, 'Demasiados intentos. Espera un momento o usa el PIN del teléfono.',
            type: SnackType.error);
      case BiometricResult.unavailable:
        // El teléfono ya no tiene bloqueo de pantalla: por seguridad se pide login.
        showAppSnack(context, 'Configura un bloqueo de pantalla. Inicia sesión de nuevo.',
            type: SnackType.error);
        await ref.read(authControllerProvider.notifier).logout();
      case BiometricResult.failed:
        HapticFeedback.heavyImpact();
        showAppSnack(context, 'No se pudo verificar tu identidad', type: SnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppLogo(width: 150),
                  const SizedBox(height: 24),
                  Text(
                    'Hola de nuevo${user != null ? ', ${user.nombre.split(' ').first}' : ''}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Usa tu huella, rostro o PIN del teléfono para continuar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: _autenticando ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Desbloquear'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _autenticando
                        ? null
                        : () => ref.read(authControllerProvider.notifier).logout(),
                    child: const Text('Usar otra cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
