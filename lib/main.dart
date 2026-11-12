import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/api_client.dart';
import 'core/network/conectividad.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/app_lock_controller.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/player/beat_audio_handler.dart';
import 'features/notifications/avisos.dart';
import 'features/transfers/transfer_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await AudioService.init(
    builder: BeatAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.skonditbeats.skondit_beats_mobile.audio',
      androidNotificationChannelName: 'Reproductor',
      androidNotificationIcon: 'drawable/ic_notification',
      // El servicio sigue activo en pausa: Android 12+ no deja reiniciarlo
      // desde segundo plano al reanudar desde la pantalla de bloqueo.
      androidStopForegroundOnPause: false,
    ),
  );
  runApp(ProviderScope(
    overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
    child: const SkonditApp(),
  ));
}

class SkonditApp extends ConsumerStatefulWidget {
  const SkonditApp({super.key});

  @override
  ConsumerState<SkonditApp> createState() => _SkonditAppState();
}

class _SkonditAppState extends ConsumerState<SkonditApp> {
  late final AppLifecycleListener _lifecycle;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Bloqueo por inactividad: si la app pasa tiempo en segundo plano,
    // al volver se pide biometría.
    _lifecycle = AppLifecycleListener(
      onPause: () => ref.read(appLockProvider.notifier).onPaused(),
      onResume: () {
        ref.read(appLockProvider.notifier).onResumed(
              authenticated: ref.read(authControllerProvider).isAuthenticated,
            );
        // Al volver a la app se reintenta lo que esperaba conexión.
        ref.read(transferManagerProvider.notifier).reanudarPendientes();
      },
    );

    // Notificaciones de tickets: al tocarlas se abre el ticket.
    unawaited(_iniciarAvisos());

    // RES-05: la API rechazó el token (vencido o cuenta desactivada).
    ref.read(sesionExpiradaProvider).stream.listen((_) async {
      if (!ref.read(authControllerProvider).isAuthenticated) return;
      await ref.read(authControllerProvider.notifier).logout();
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('Tu sesión expiró o la cuenta cambió. Inicia sesión de nuevo.')),
      );
    });
  }

  Future<void> _iniciarAvisos() async {
    try {
      await iniciarNotificaciones(alTocar: _abrirTicket);
      await pedirPermisoNotificaciones();
      final id = await ticketDeArranque();
      if (id != null) _abrirTicket(id);
    } catch (_) {
      // Sin notificaciones la app sigue funcionando; las insignias siguen.
    }
  }

  /// Espera a que haya sesión (y no esté bloqueada) y abre el ticket.
  void _abrirTicket(String id) {
    void abrir() {
      final user = ref.read(authControllerProvider).user;
      if (user == null || ref.read(appLockProvider)) {
        Future.delayed(const Duration(milliseconds: 500), abrir);
        return;
      }
      ref.read(routerProvider).push(user.isAdmin ? Routes.adminMessage(id) : Routes.myMessage(id));
    }

    abrir();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene viva la cola: reanuda subidas y descargas desde que abre la app.
    ref.listen(transferManagerProvider, (_, _) {});
    // Consulta de avisos de tickets mientras haya sesión.
    ref.listen(noLeidosProvider, (_, _) {});
    final hayRed = ref.watch(conectividadProvider).value ?? true;

    return MaterialApp.router(
      title: 'SkonditBeats',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      scaffoldMessengerKey: _messenger,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => Column(
        children: [
          // RES-01/06: aviso visible mientras no hay red; desaparece al volver.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: hayRed
                ? const SizedBox(width: double.infinity)
                : Material(
                    color: AppColors.error,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        child: Row(
                          children: const [
                            Icon(Icons.wifi_off, size: 16, color: Colors.black),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('Sin conexión · lo pendiente continuará al reconectar',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: hayRed
                ? child!
                : MediaQuery.removePadding(context: context, removeTop: true, child: child!),
          ),
        ],
      ),
    );
  }
}
