import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/auth_repository.dart';
import '../auth_controller.dart';
import '../widgets/auth_header.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading || !_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final result =
          await ref.read(authControllerProvider.notifier).login(_email.text, _password.text);

      // Si es LoginSuccess el router redirige solo al inicio según el rol.
      if (result is LoginNeedsOtp && mounted) {
        _password.clear();
        showAppSnack(context, result.message);
        context.push(Routes.otp, extra: OtpArgs(email: result.email, otpDev: result.otpDev));
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Google confirma la identidad en el navegador; después se pide el código OTP,
  /// igual que en la web.
  Future<void> _google() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await ref.read(authRepositoryProvider).loginConGoogle();
      if (result != null && mounted) {
        showAppSnack(context, result.message);
        context.push(Routes.otp, extra: OtpArgs(email: result.email, otpDev: result.otpDev));
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthHeader(
                        title: 'Inicia sesión',
                        subtitle: 'Descubre, escucha y compra beats desde tu teléfono',
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        enabled: !_loading,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        enabled: !_loading,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => Validators.required(v, 'Ingresa tu contraseña'),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : const Text('Iniciar sesión'),
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('o', style: TextStyle(color: AppColors.textMuted)),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _google,
                        icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        label: const Text('Continuar con Google'),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('¿No tienes cuenta?', style: TextStyle(color: AppColors.textMuted)),
                          TextButton(
                            onPressed: _loading ? null : () => context.push(Routes.register),
                            child: const Text('Regístrate'),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => context.push(Routes.terms),
                        child: const Text(
                          'Términos y condiciones',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
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
