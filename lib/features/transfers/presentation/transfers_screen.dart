import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/conectividad.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../domain/transferencia.dart';
import '../transfer_manager.dart';

/// Subidas y descargas: progreso, pausa, reanudar y quitar.
class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(transferManagerProvider).reversed.toList();
    final hayRed = ref.watch(conectividadProvider).value ?? true;
    final cola = ref.read(transferManagerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transferencias'),
        actions: [
          if (lista.any((t) => t.estado == EstadoTransferencia.completada && t.esSubida))
            TextButton(onPressed: cola.limpiarCompletadas, child: const Text('Limpiar')),
        ],
      ),
      body: Column(
        children: [
          if (!hayRed)
            Container(
              width: double.infinity,
              color: AppColors.surfaceHigh,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Sin conexión. Lo pendiente continuará solo donde se quedó al conectarte a cualquier red.',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          Expanded(
            child: lista.isEmpty
                ? const EmptyView(
                    icon: Icons.swap_vert,
                    title: 'Sin transferencias',
                    message: 'Aquí verás las subidas de audio y portadas, y tus descargas',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) => _TransferenciaTile(t: lista[i], cola: cola),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TransferenciaTile extends StatelessWidget {
  const _TransferenciaTile({required this.t, required this.cola});

  final Transferencia t;
  final TransferManager cola;

  @override
  Widget build(BuildContext context) {
    final color = switch (t.estado) {
      EstadoTransferencia.completada => AppColors.success,
      EstadoTransferencia.error => AppColors.error,
      EstadoTransferencia.esperandoRed || EstadoTransferencia.pausada => AppColors.textMuted,
      _ => AppColors.primary,
    };
    final bytes = t.total > 0 ? '${formatoBytes(t.avance)} de ${formatoBytes(t.total)}' : formatoBytes(t.avance);

    return ListTile(
      leading: Icon(t.esSubida ? Icons.upload : Icons.download, color: color),
      title: Text(t.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          if (t.estado != EstadoTransferencia.completada)
            LinearProgressIndicator(
              value: t.estado == EstadoTransferencia.activa ? t.progreso : (t.progreso ?? 0),
              color: color,
              backgroundColor: AppColors.surfaceHigh,
            ),
          const SizedBox(height: 4),
          Text(
            [t.estado.etiqueta, if (t.estado != EstadoTransferencia.completada) bytes, ?t.error].join(' · '),
            style: TextStyle(color: t.error != null ? AppColors.error : AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t.estado == EstadoTransferencia.activa || t.estado == EstadoTransferencia.pendiente)
            IconButton(tooltip: 'Pausar', icon: const Icon(Icons.pause), onPressed: () => cola.pausar(t.id)),
          if (t.estado == EstadoTransferencia.pausada ||
              t.estado == EstadoTransferencia.error ||
              t.estado == EstadoTransferencia.esperandoRed)
            IconButton(tooltip: 'Reanudar', icon: const Icon(Icons.play_arrow), onPressed: () => cola.reanudar(t.id)),
          IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.close),
            onPressed: () => cola.eliminar(t.id, conservarArchivo: t.estado == EstadoTransferencia.completada),
          ),
        ],
      ),
    );
  }
}
