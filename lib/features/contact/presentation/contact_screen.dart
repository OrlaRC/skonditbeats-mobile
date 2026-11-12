import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/contact_repository.dart';

/// Formulario de contacto: el mensaje o reporte de error le llega al administrador.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  static const _maxMensaje = 1000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _email;
  final _mensaje = TextEditingController();
  final _asunto = TextEditingController();
  bool _enviando = false;
  bool _esError = false;

  /// Folio del ticket creado; null mientras no se ha enviado.
  int? _folio;
  bool _enviado = false;

  /// Identifica ESTE ticket. Si el envío falla por la red, el reintento usa la
  /// misma clave: aunque el servidor sí lo hubiera guardado, no se abre otro.
  String _clave = nuevaClaveIdempotencia();

  @override
  void initState() {
    super.initState();
    // Igual que en la web: se precargan los datos del usuario.
    final user = ref.read(authControllerProvider).user;
    _nombre = TextEditingController(text: user?.nombre ?? '');
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _mensaje.dispose();
    _asunto.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (_enviando || !_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      final folio = await ref.read(contactRepositoryProvider).send(
            nombre: _nombre.text,
            email: _email.text,
            mensaje: _mensaje.text,
            asunto: _asunto.text,
            esError: _esError,
            clave: _clave,
          );
      HapticFeedback.mediumImpact();
      ref.invalidate(myMessagesProvider);
      if (mounted) {
        setState(() {
          _enviado = true;
          _folio = folio;
        });
      }
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        // Sin confirmación del servidor no se dice "enviado": puede o no haber
        // llegado. Reintentar es seguro porque se usa la misma clave.
        final msg = e.sinRed ? '${e.message} No se confirmó el envío; reintenta sin miedo a duplicarlo.' : e.message;
        showAppSnack(context, msg, type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacto'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(Routes.myMessages),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Mis tickets'),
          ),
        ],
      ),
      body: SafeArea(
        child: _enviado ? _enviadoView() : _form(),
      ),
    );
  }

  Widget _enviadoView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_read_outlined, size: 80, color: AppColors.success),
              const SizedBox(height: 16),
              Text(_folio == null ? '¡Ticket creado!' : 'Ticket #$_folio creado',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Guarda el folio para darle seguimiento. Verás las respuestas en Mis tickets y te avisaremos a ${_email.text.trim()}.',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => setState(() {
                  _enviado = false;
                  _folio = null;
                  _mensaje.clear();
                  _asunto.clear();
                  _clave = nuevaClaveIdempotencia();
                }),
                child: const Text('Abrir otro ticket'),
              ),
            ],
          ),
        ),
      );

  Widget _form() => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.support_agent, size: 56, color: AppColors.primary),
              const SizedBox(height: 12),
              Text('¿En qué te ayudamos?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Dudas sobre licencias, beats personalizados o problemas con una compra.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Mensaje'), icon: Icon(Icons.mail_outline)),
                  ButtonSegment(value: true, label: Text('Reportar error'), icon: Icon(Icons.bug_report_outlined)),
                ],
                selected: {_esError},
                onSelectionChanged: _enviando ? null : (s) => setState(() => _esError = s.first),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nombre,
                enabled: !_enviando,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline)),
                validator: Validators.name,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                enabled: !_enviando,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Correo de respuesta', prefixIcon: Icon(Icons.mail_outline)),
                validator: Validators.email,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _asunto,
                enabled: !_enviando,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _clave = nuevaClaveIdempotencia(),
                decoration: const InputDecoration(
                  labelText: 'Asunto',
                  hintText: 'Resumen en pocas palabras',
                  prefixIcon: Icon(Icons.short_text),
                  counterText: '',
                ),
                validator: (v) => (v == null || v.trim().length < 3) ? 'Escribe un asunto' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _mensaje,
                onChanged: (_) => _clave = nuevaClaveIdempotencia(),
                enabled: !_enviando,
                minLines: 5,
                maxLines: 8,
                maxLength: _maxMensaje,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _esError ? '¿Qué falló?' : 'Mensaje',
                  alignLabelWithHint: true,
                  hintText: _esError
                      ? 'Qué estabas haciendo y qué pasó (mínimo 10 caracteres)'
                      : 'Cuéntanos con detalle (mínimo 10 caracteres)',
                ),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Escribe al menos 10 caracteres'
                    : null,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                      )
                    : const Icon(Icons.send),
                label: Text(_enviando ? 'Enviando...' : 'Crear ticket'),
              ),
            ],
          ),
        ),
      );
}
