import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../../notifications/avisos.dart';
import '../data/contact_repository.dart';
import 'thread_list.dart';

/// Mensajes y reportes que el cliente ha enviado, con sus respuestas.
class MyMessagesScreen extends ConsumerWidget {
  const MyMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(myMessagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis tickets')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.refresh(myMessagesProvider.future).then((_) {}, onError: (_) {}),
        child: messages.when(
          skipLoadingOnRefresh: true,
          loading: () => const LoadingList(),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'No se pudieron cargar tus mensajes',
            onRetry: () => ref.invalidate(myMessagesProvider),
          ),
          data: (list) => list.isEmpty
              ? const EmptyView(
                  icon: Icons.mail_outline,
                  title: 'Sin tickets',
                  message: 'Aquí verás el seguimiento de lo que envíes desde Contacto',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) => ThreadTile(
                    hilo: list[i],
                    nuevo: list[i].noLeidoCliente,
                    titulo: list[i].titulo,
                    onTap: () async {
                      await context.push(Routes.myMessage(list[i].id));
                      ref.invalidate(myMessagesProvider);
                      ref.read(noLeidosProvider.notifier).refrescar();
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
