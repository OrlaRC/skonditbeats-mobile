import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Envuelve una pantalla con datos sensibles (pago, OTP): mientras está
/// visible, Android bloquea capturas de pantalla y grabación (FLAG_SECURE).
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  static const _channel = MethodChannel('com.skonditbeats/secure_screen');

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    _set(true);
  }

  @override
  void dispose() {
    _set(false);
    super.dispose();
  }

  Future<void> _set(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await SecureScreen._channel.invokeMethod<void>(enabled ? 'enable' : 'disable');
    } on PlatformException {
      // Si falla, la app sigue funcionando; solo no se bloquean capturas.
    } on MissingPluginException {
      // Pruebas o plataformas sin el canal nativo.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
