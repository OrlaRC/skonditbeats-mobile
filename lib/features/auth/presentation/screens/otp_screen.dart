import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../auth_controller.dart';
import '../widgets/auth_header.dart';

class OtpArgs {
  const OtpArgs({required this.email, this.otpDev});
  final String email;
  final String? otpDev;
}

/// Paso 2 del login del cliente: código de 6 dígitos enviado por correo.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});

  final OtpArgs args;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _vigencia = Duration(minutes: 10); // igual que el backend

  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  late Duration _restante = _vigencia;
  Timer? _timer;
  bool _loading = false;

  bool get _expirado => _restante == Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _restante -= const Duration(seconds: 1);
        if (_restante <= Duration.zero) {
          _restante = Duration.zero;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_loading || _expirado || !_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).verifyOtp(widget.args.email, _code.text);
      // El router lleva al inicio al cambiar el estado de sesión.
    } on ApiException catch (e) {
      if (mounted) {
        _code.clear();
        showAppSnack(context, e.message, type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _reloj {
    final m = _restante.inMinutes.toString().padLeft(2, '0');
    final s = (_restante.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthHeader(
                        title: 'Verificación en 2 pasos',
                        subtitle: 'Escribe el código de 6 dígitos que enviamos a\n${widget.args.email}',
                      ),
                      if (widget.args.otpDev != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.error),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '[DEV] El correo no se envió. Código: ${widget.args.otpDev}',
                            style: const TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _code,
                        autofocus: true,
                        enabled: !_loading && !_expirado,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 14),
                        decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                        validator: Validators.otp,
                        onChanged: (v) {
                          if (v.length == 6) _verify();
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _expirado ? 'El código expiró' : 'El código vence en $_reloj',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _expirado ? AppColors.error : AppColors.textMuted),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: (_loading || _expirado) ? null : _verify,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : const Text('Verificar'),
                      ),
                      const SizedBox(height: 12),
                      // Por seguridad no se guarda la contraseña para reenviar:
                      // el usuario vuelve a iniciar sesión y se genera un código nuevo.
                      TextButton(
                        onPressed: _loading ? null : () => context.pop(),
                        child: const Text('¿No te llegó? Volver a iniciar sesión'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
