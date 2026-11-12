import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/password_rules.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _edad = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _aceptaTerminos = false;
  bool _loading = false;
  late final TapGestureRecognizer _termsTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => context.push(Routes.terms);
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_nombre, _username, _email, _telefono, _edad, _password, _confirm]) {
      c.dispose();
    }
    _termsTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_loading || !_formKey.currentState!.validate()) return;
    if (!_aceptaTerminos) {
      showAppSnack(context, 'Debes aceptar los términos y condiciones', type: SnackType.error);
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            RegisterData(
              nombre: _nombre.text,
              username: _username.text,
              email: _email.text,
              telefono: _telefono.text,
              edad: int.parse(_edad.text),
              password: _password.text,
            ),
          );
      // Al quedar autenticado el router lleva al inicio del cliente.
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _deco(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixIcon: suffix);

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthHeader(
                        title: 'Crea tu cuenta',
                        subtitle: 'Regístrate para comprar beats y paquetes',
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _nombre,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: _deco('Nombre completo', Icons.person_outline),
                        validator: Validators.name,
                      ),
                      gap,
                      TextFormField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.newUsername],
                        decoration: _deco('Nombre artístico (opcional)', Icons.alternate_email),
                      ),
                      gap,
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: _deco('Correo electrónico', Icons.mail_outline),
                        validator: Validators.email,
                      ),
                      gap,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _telefono,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.telephoneNumber],
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: _deco('Teléfono (opcional)', Icons.phone_outlined),
                              validator: Validators.phone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _edad,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              decoration: _deco('Edad', Icons.cake_outlined),
                              validator: Validators.age,
                            ),
                          ),
                        ],
                      ),
                      gap,
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.next,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: _deco(
                          'Contraseña',
                          Icons.lock_outline,
                          suffix: IconButton(
                            tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      PasswordRules(password: _password.text),
                      gap,
                      TextFormField(
                        controller: _confirm,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: _deco(
                          'Confirmar contraseña',
                          Icons.lock_reset_outlined,
                          suffix: IconButton(
                            tooltip: _obscureConfirm ? 'Mostrar contraseña' : 'Ocultar contraseña',
                            icon: Icon(
                                _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) => v == _password.text ? null : 'Las contraseñas no coinciden',
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _aceptaTerminos,
                        onChanged: _loading ? null : (v) => setState(() => _aceptaTerminos = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text.rich(
                          TextSpan(
                            text: 'Acepto los ',
                            style: const TextStyle(fontSize: 14),
                            children: [
                              TextSpan(
                                text: 'términos y condiciones',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.primary,
                                ),
                                recognizer: _termsTap,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: (_loading || !_aceptaTerminos) ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : const Text('Crear cuenta'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('¿Ya tienes cuenta?', style: TextStyle(color: AppColors.textMuted)),
                          TextButton(
                            onPressed: _loading ? null : () => context.go(Routes.login),
                            child: const Text('Inicia sesión'),
                          ),
                        ],
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
