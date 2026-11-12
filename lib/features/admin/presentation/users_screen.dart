import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/roles.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../data/admin_repository.dart';
import 'user_forms.dart';

IconData iconoRol(Rol r) => switch (r) {
      Rol.superAdmin => Icons.shield_outlined,
      Rol.admin => Icons.admin_panel_settings_outlined,
      Rol.cliente => Icons.person_outline,
    };

/// Gestor de usuarios: alta, ficha, rol, activación y asignación masiva de roles.
/// Mantén presionado un usuario para empezar a seleccionar varios.
///
/// Un administrador solo gestiona clientes; el super administrador gestiona
/// también a los administradores. La API aplica la misma regla.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _seleccion = <String>{};
  bool _guardando = false;

  String? get _miRol => ref.read(authControllerProvider).user?.rol;

  void _alternar(String id) => setState(() {
        if (!_seleccion.remove(id)) _seleccion.add(id);
      });

  Future<bool> _confirmar(String titulo, String mensaje) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    return ok == true;
  }

  /// Aplica el cambio y siempre recarga la lista, para mostrar lo que quedó.
  Future<void> _aplicar(List<Future<void> Function()> cambios, String exito) async {
    setState(() => _guardando = true);
    var fallidos = 0;
    String? error;
    for (final cambio in cambios) {
      try {
        await cambio();
      } on ApiException catch (e) {
        fallidos++;
        error = e.message;
      }
    }
    ref.invalidate(adminUsersProvider);
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (fallidos == 0) _seleccion.clear();
    });
    if (fallidos == 0) {
      showAppSnack(context, exito, type: SnackType.success);
    } else {
      showAppSnack(context, '$fallidos cambio(s) no se aplicaron: $error', type: SnackType.error);
    }
  }

  Future<void> _rolMasivo(Rol rol) async {
    final total = _seleccion.length;
    if (!await _confirmar('Asignar rol', '¿Dar el rol de ${rol.etiqueta.toLowerCase()} a $total usuario(s)?')) return;
    final repo = ref.read(adminRepositoryProvider);
    await _aplicar(
      [for (final id in _seleccion) () => repo.setRol(id, rol.api)],
      'Rol asignado a $total usuario(s)',
    );
  }

  Future<void> _elegirRol(AdminUser u) async {
    final actual = Rol.desde(u.rol);
    final nuevo = await showModalBottomSheet<Rol>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('Rol de ${u.nombre}', style: const TextStyle(fontWeight: FontWeight.w700))),
            for (final r in rolesAsignables(_miRol))
              ListTile(
                leading: Icon(iconoRol(r), color: AppColors.primary),
                title: Text(r.etiqueta),
                trailing: r == actual ? const Icon(Icons.check, color: AppColors.primary) : null,
                enabled: r != actual,
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (nuevo == null || !mounted) return;
    if (!await _confirmar('Cambiar rol', '¿Hacer a ${u.nombre} ${nuevo.etiqueta.toLowerCase()}?')) return;
    await _aplicar([() => ref.read(adminRepositoryProvider).setRol(u.id, nuevo.api)], 'Rol actualizado');
  }

  Future<void> _editar(AdminUser u) async {
    final gestionable = puedeGestionar(_miRol, u.rol);
    final accion = await showModalBottomSheet<_Accion>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(u.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${u.email} · ${Rol.desde(u.rol).etiqueta}', style: const TextStyle(color: AppColors.textMuted)),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(gestionable ? 'Ver ficha, editar o cambiar contraseña' : 'Ver ficha'),
              onTap: () => Navigator.pop(ctx, _Accion.ficha),
            ),
            if (gestionable && rolesAsignables(_miRol).length > 1)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Cambiar rol'),
                onTap: () => Navigator.pop(ctx, _Accion.rol),
              ),
            if (gestionable)
              ListTile(
                leading: Icon(u.activo ? Icons.block : Icons.check_circle_outline),
                title: Text(u.activo ? 'Desactivar cuenta' : 'Reactivar cuenta'),
                onTap: () => Navigator.pop(ctx, _Accion.activo),
              ),
            if (!gestionable)
              const ListTile(
                leading: Icon(Icons.lock_outline, color: AppColors.textMuted),
                title: Text('Solo el super administrador gestiona administradores',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
    if (accion == null || !mounted) return;

    switch (accion) {
      case _Accion.ficha:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: AppColors.surface,
          builder: (_) => UserDetailSheet(id: u.id, gestionable: gestionable),
        );
      case _Accion.rol:
        await _elegirRol(u);
      case _Accion.activo:
        final titulo = u.activo ? 'Desactivar cuenta' : 'Reactivar cuenta';
        if (!await _confirmar(titulo, '¿Confirmas el cambio para ${u.nombre}?')) return;
        await _aplicar([() => ref.read(adminRepositoryProvider).setActivo(u.id, !u.activo)], 'Cuenta actualizada');
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider);
    final yo = ref.watch(authControllerProvider.select((s) => s.user));
    final seleccionando = _seleccion.isNotEmpty;
    final asignables = rolesAsignables(yo?.rol);

    return PopScope(
      canPop: !seleccionando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_seleccion.clear);
      },
      child: Scaffold(
        floatingActionButton: seleccionando
            ? null
            : FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Nuevo usuario'),
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  backgroundColor: AppColors.surface,
                  builder: (_) => const UserForm(),
                ),
              ),
        appBar: AppBar(
          title: Text(seleccionando ? '${_seleccion.length} seleccionados' : 'Gestor de usuarios'),
          actions: [
            if (seleccionando && asignables.length > 1)
              PopupMenuButton<Rol>(
                tooltip: 'Asignar rol',
                enabled: !_guardando,
                icon: const Icon(Icons.manage_accounts_outlined),
                onSelected: _rolMasivo,
                itemBuilder: (_) => [
                  for (final r in asignables) PopupMenuItem(value: r, child: Text('Hacer ${r.etiqueta.toLowerCase()}')),
                ],
              ),
          ],
        ),
        body: Column(
          children: [
            if (_guardando) const LinearProgressIndicator(color: AppColors.primary),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.refresh(adminUsersProvider.future).then((_) {}, onError: (_) {}),
                child: users.when(
                  skipLoadingOnRefresh: true,
                  loading: () => const LoadingList(),
                  error: (e, _) => ErrorView(
                    message: e is ApiException ? e.message : 'No se pudieron cargar los usuarios',
                    onRetry: () => ref.invalidate(adminUsersProvider),
                  ),
                  data: (list) => ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final u = list[i];
                      final rol = Rol.desde(u.rol);
                      final soyYo = u.id == yo?.id; // Evita quitarse a sí mismo el acceso.
                      final seleccionable = !soyYo && puedeGestionar(yo?.rol, u.rol);
                      return ListTile(
                        enabled: !soyYo && !_guardando,
                        selected: _seleccion.contains(u.id),
                        selectedTileColor: AppColors.surfaceHigh,
                        leading: seleccionando && seleccionable
                            ? Icon(
                                _seleccion.contains(u.id) ? Icons.check_circle : Icons.circle_outlined,
                                color: AppColors.primary,
                              )
                            : Icon(iconoRol(rol), color: u.activo ? AppColors.primary : AppColors.textMuted),
                        title: Text(soyYo ? '${u.nombre} (tú)' : u.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${u.email}\n${rol.etiqueta} · ${u.beatsComprados} beats${u.activo ? '' : ' · Desactivada'}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                        isThreeLine: true,
                        onLongPress: seleccionable ? () => _alternar(u.id) : null,
                        onTap: () => seleccionando ? (seleccionable ? _alternar(u.id) : null) : _editar(u),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Accion { ficha, rol, activo }
