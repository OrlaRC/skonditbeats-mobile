import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../data/admin_repository.dart';

/// Bitácora de la API: quién hizo qué, cuándo y desde qué IP.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String? _accion;
  List<String> _acciones = const [];

  static String _fecha(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  static bool _esAlerta(String accion) => accion.contains('FALLIDO') || accion.contains('ELIMINACION');

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(adminAuditProvider(_accion));
    // Se guardan las acciones para que los filtros no desaparezcan al recargar.
    if (page.value case final p? when p.acciones.isNotEmpty) _acciones = p.acciones;

    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final a in [null, ..._acciones])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(a == null ? 'Todas' : accionLegibleDe(a)),
                      selected: _accion == a,
                      selectedColor: AppColors.primary,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _accion == a ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _accion = a),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => ref.refresh(adminAuditProvider(_accion).future).then((_) {}, onError: (_) {}),
              child: page.when(
                skipLoadingOnRefresh: true,
                loading: () => const LoadingList(),
                error: (e, _) => ErrorView(
                  message: e is ApiException ? e.message : 'No se pudo cargar la bitácora',
                  onRetry: () => ref.invalidate(adminAuditProvider(_accion)),
                ),
                data: (p) => p.registros.isEmpty
                    ? const EmptyView(
                        icon: Icons.history,
                        title: 'Sin registros',
                        message: 'No hay movimientos con este filtro',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                        itemCount: p.registros.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final r = p.registros[i];
                          final alerta = _esAlerta(r.accion);
                          return ListTile(
                            leading: Icon(
                              alerta ? Icons.warning_amber_rounded : Icons.history,
                              color: alerta ? AppColors.error : AppColors.primary,
                            ),
                            title: Text(r.accionLegible, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              [
                                if (r.detalle.isNotEmpty) r.detalle,
                                [?r.email, ?r.ip].join(' · '),
                                if (r.fecha != null) _fecha(r.fecha!),
                              ].where((l) => l.isNotEmpty).join('\n'),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
