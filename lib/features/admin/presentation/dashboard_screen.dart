import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../data/admin_repository.dart';

/// Reportes del negocio: totales, beats más vendidos, géneros y mejores clientes.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard y reportes')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.refresh(adminStatsProvider.future).then((_) {}, onError: (_) {}),
        child: stats.when(
          skipLoadingOnRefresh: true,
          loading: () => const LoadingList(count: 4),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'No se pudieron cargar los reportes',
            onRetry: () => ref.invalidate(adminStatsProvider),
          ),
          data: (s) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _Total(Icons.group_outlined, 'Clientes activos', s.totalClientes)),
                  const SizedBox(width: 12),
                  Expanded(child: _Total(Icons.music_note_outlined, 'Beats activos', s.totalBeats)),
                ],
              ),
              _Reporte(
                titulo: 'Beats más vendidos',
                vacio: 'Todavía no hay ventas',
                filas: [
                  for (final b in s.masVendidos) (b.nombre, b.genero, '${b.ventas} ventas'),
                ],
              ),
              _Reporte(
                titulo: 'Ventas por género',
                vacio: 'Todavía no hay ventas',
                filas: [
                  for (final g in s.ventasPorGenero) (g.genero, null, '${g.ventas} ventas'),
                ],
              ),
              _Reporte(
                titulo: 'Mejores clientes',
                vacio: 'Todavía no hay compras',
                filas: [
                  for (final c in s.topClientes)
                    (c.nombre, '${c.email} · ${c.ordenes} compras', formatMoney(c.total)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 8),
          Text('$value', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Reporte extends StatelessWidget {
  const _Reporte({required this.titulo, required this.vacio, required this.filas});

  final String titulo;
  final String vacio;
  final List<(String, String?, String)> filas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: filas.isEmpty
                  ? [ListTile(title: Text(vacio, style: const TextStyle(color: AppColors.textMuted)))]
                  : [
                      for (final (nombre, detalle, valor) in filas)
                        ListTile(
                          dense: true,
                          title: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: detalle == null
                              ? null
                              : Text(detalle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textMuted)),
                          trailing: Text(valor,
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}
