import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/roles.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/widgets/password_rules.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../../contact/presentation/thread_screen.dart' show formatoFecha;
import '../data/admin_repository.dart';

/// Alta de un usuario (o edición de sus datos si se pasa [usuario]).
class UserForm extends ConsumerStatefulWidget {
  const UserForm({super.key, this.usuario});

  final AdminUserDetail? usuario;

  @override
  ConsumerState<UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<UserForm> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.usuario?.user.nombre);
  late final _email = TextEditingController(text: widget.usuario?.user.email);
  late final _telefono = TextEditingController(text: widget.usuario?.telefono);
  final _password = TextEditingController();
  Rol _rol = Rol.cliente;
  bool _guardando = false;

  bool get _editando => widget.usuario != null;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_nombre, _email, _telefono, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final repo = ref.read(adminRepositoryProvider);
    try {
      if (_editando) {
        await repo.updateUser(widget.usuario!.user.id, nombre: _nombre.text, email: _email.text, telefono: _telefono.text);
      } else {
        await repo.createUser(
          nombre: _nombre.text,
          email: _email.text,
          password: _password.text,
          rol: _rol.api,
          telefono: _telefono.text,
        );
      }
      ref.invalidate(adminUsersProvider);
      if (_editando) ref.invalidate(adminUserDetailProvider(widget.usuario!.user.id));
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showAppSnack(context, _editando ? 'Datos actualizados' : 'Usuario creado', type: SnackType.success);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_editando ? 'Editar usuario' : 'Nuevo usuario', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombre,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline)),
                  validator: Validators.name,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_guardando,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  enabled: !_guardando,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: Validators.phone,
                ),
                if (!_editando) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    enabled: !_guardando,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña inicial', prefixIcon: Icon(Icons.lock_outline)),
                    validator: Validators.password,
                  ),
                  const SizedBox(height: 8),
                  PasswordRules(password: _password.text),
                  // Solo el super administrador puede crear administradores.
                  if (rolesAsignables(ref.watch(authControllerProvider).user?.rol).length > 1) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<Rol>(
                      segments: const [
                        ButtonSegment(value: Rol.cliente, label: Text('Cliente')),
                        ButtonSegment(value: Rol.admin, label: Text('Admin')),
                        ButtonSegment(value: Rol.superAdmin, label: Text('Super')),
                      ],
                      selected: {_rol},
                      onSelectionChanged: _guardando ? null : (s) => setState(() => _rol = s.first),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: Text(_guardando ? 'Guardando...' : 'Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo para que el admin asigne una contraseña nueva.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, required this.nombre});

  final String nombre;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valida = Validators.password(_c.text) == null;
    return AlertDialog(
      title: Text('Contraseña de ${widget.nombre}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nueva contraseña'),
          ),
          const SizedBox(height: 8),
          PasswordRules(password: _c.text),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: valida ? () => Navigator.pop(context, _c.text) : null, child: const Text('Guardar')),
      ],
    );
  }
}

/// Ficha del usuario con sus compras.
class UserDetailSheet extends ConsumerWidget {
  const UserDetailSheet({super.key, required this.id, this.gestionable = true});

  final String id;

  /// false si quien la ve no puede editar a esta cuenta (un admin viendo a otro admin).
  final bool gestionable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalle = ref.watch(adminUserDetailProvider(id));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: detalle.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'No se pudo cargar el usuario',
            onRetry: () => ref.invalidate(adminUserDetailProvider(id)),
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(d.user.nombre, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(d.user.email, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Text(
                [
                  Rol.desde(d.user.rol).etiqueta,
                  d.user.activo ? 'Activa' : 'Desactivada',
                  if (d.telefono != null && d.telefono!.isNotEmpty) d.telefono!,
                  if (d.fechaRegistro != null) 'Desde ${formatoFecha(d.fechaRegistro!).split(' ').first}',
                ].join(' · '),
              ),
              const SizedBox(height: 16),
              if (gestionable) Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                      onPressed: () => showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: AppColors.surface,
                        builder: (_) => UserForm(usuario: d),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Contraseña'),
                      onPressed: () async {
                        final nueva = await showDialog<String>(
                          context: context,
                          builder: (_) => PasswordDialog(nombre: d.user.nombre),
                        );
                        if (nueva == null) return;
                        try {
                          await ref.read(adminRepositoryProvider).setPassword(d.user.id, nueva);
                          if (context.mounted) showAppSnack(context, 'Contraseña actualizada', type: SnackType.success);
                        } on ApiException catch (e) {
                          if (context.mounted) showAppSnack(context, e.message, type: SnackType.error);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Compras (${d.compras.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (d.compras.isEmpty)
                const Text('Todavía no ha comprado nada', style: TextStyle(color: AppColors.textMuted)),
              for (final c in d.compras)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
                  title: Text(c.beats.isEmpty ? 'Compra' : c.beats, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(c.fecha == null ? '' : formatoFecha(c.fecha!), style: const TextStyle(color: AppColors.textMuted)),
                  trailing: Text(formatMoney(c.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
