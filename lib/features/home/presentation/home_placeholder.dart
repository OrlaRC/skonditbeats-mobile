import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/avisos.dart';

/// Pide confirmación y cierra la sesión. La usan el inicio del admin y el del cliente.
Future<void> confirmarCerrarSesion(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cerrar sesión'),
      content: const Text('¿Seguro que quieres salir de tu cuenta?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
      ],
    ),
  );
  if (ok == true) await ref.read(authControllerProvider.notifier).logout();
}

/// Pantalla base de inicio mientras se construyen los módulos de cada rol.
class HomePlaceholder extends ConsumerWidget {
  const HomePlaceholder({
    super.key,
    required this.title,
    required this.roleLabel,
    required this.modules,
  });

  final String title;
  final String roleLabel;
  /// (ícono, nombre, ruta).
  final List<(IconData, String, String)> modules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final noLeidos = ref.watch(noLeidosProvider).total;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Mi perfil',
            icon: CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.surfaceHigh,
              foregroundImage: user?.fotoUrl != null ? NetworkImage(user!.fotoUrl!) : null,
              onForegroundImageError: user?.fotoUrl != null ? (_, _) {} : null,
              child: const Icon(Icons.person, size: 18, color: AppColors.primary),
            ),
            onPressed: () => context.push(Routes.profile),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => confirmarCerrarSesion(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Hola, ${user?.nombre ?? ''}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(
              children: [
                Chip(
                  label: Text(roleLabel),
                  backgroundColor: AppColors.primary,
                  labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(user?.email ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Módulos', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            for (final (icon, label, route) in modules)
              Card(
                color: AppColors.surface,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  leading: Icon(icon, color: AppColors.primary),
                  title: Text(label),
                  // Insignia de tickets sin leer en la mesa de ayuda.
                  subtitle: route == Routes.adminMessages && noLeidos > 0
                      ? Text('$noLeidos sin leer', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(route),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
