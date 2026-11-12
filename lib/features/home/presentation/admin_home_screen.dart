import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_controller.dart';
import 'home_placeholder.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final superAdmin = ref.watch(authControllerProvider.select((s) => s.user?.isSuperAdmin ?? false));
    return HomePlaceholder(
      title: 'Panel de administración',
      roleLabel: superAdmin ? 'Super admin' : 'Admin',
      modules: const [
        (Icons.insights_outlined, 'Dashboard y reportes', Routes.adminDashboard),
        (Icons.library_music_outlined, 'Gestor de beats', Routes.adminBeats),
        (Icons.group_outlined, 'Gestor de usuarios y roles', Routes.adminUsers),
        (Icons.confirmation_number_outlined, 'Mesa de ayuda (tickets)', Routes.adminMessages),
        (Icons.swap_vert, 'Subidas y descargas', Routes.transferencias),
        (Icons.history_outlined, 'Auditoría', Routes.adminAudit),
        (Icons.person_outline, 'Mi perfil', Routes.profile),
      ],
    );
  }
}
