import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../../contact/domain/contact_thread.dart';
import '../../contact/presentation/thread_list.dart';
import '../../notifications/avisos.dart';
import '../data/admin_repository.dart';

/// Tickets cargados hasta ahora de la bandeja.
class TicketsLista {
  const TicketsLista({required this.tickets, required this.total, this.cargandoMas = false, this.error});
  final List<ContactThread> tickets;
  final int total;
  final bool cargandoMas;
  final String? error;
  bool get hayMas => tickets.length < total;
}

/// Bandeja paginada: 20 tickets por página, filtrados en la base. Antes se
/// descargaban todos los mensajes con todas sus respuestas en cada apertura.
class TicketsPager extends AsyncNotifier<TicketsLista> {
  TicketsPager(this.filtro);

  final TicketsFilter filtro;
  int _pagina = 1;

  @override
  Future<TicketsLista> build() async {
    _pagina = 1;
    final p = await ref.watch(adminRepositoryProvider).getTickets(filtro);
    return TicketsLista(tickets: p.tickets, total: p.total);
  }

  Future<void> cargarMas() async {
    final a = state.value;
    if (a == null || a.cargandoMas || !a.hayMas) return;
    state = AsyncData(TicketsLista(tickets: a.tickets, total: a.total, cargandoMas: true));
    try {
      final p = await ref.read(adminRepositoryProvider).getTickets(filtro, page: _pagina + 1);
      _pagina++;
      final vistos = a.tickets.map((t) => t.id).toSet();
      state = AsyncData(TicketsLista(
        tickets: [...a.tickets, ...p.tickets.where((t) => vistos.add(t.id))],
        total: p.tickets.isEmpty ? a.tickets.length : p.total,
      ));
    } on ApiException catch (e) {
      state = AsyncData(TicketsLista(tickets: a.tickets, total: a.total, error: e.message));
    }
  }
}

final ticketsPagerProvider =
    AsyncNotifierProvider.autoDispose.family<TicketsPager, TicketsLista, TicketsFilter>(TicketsPager.new);

enum _Vista {
  nuevos('Sin leer'),
  pendientes('Pendientes'),
  enProceso('En proceso'),
  mios('Asignados a mí'),
  errores('Errores'),
  respondidos('Respondidos'),
  cerrados('Cerrados'),
  todos('Todos');

  const _Vista(this.etiqueta);
  final String etiqueta;

  TicketsFilter filtro(String? miId, String q) => switch (this) {
        nuevos => TicketsFilter(noLeidos: true, q: q),
        pendientes => TicketsFilter(estado: EstadoTicket.abierto.api, q: q),
        enProceso => TicketsFilter(estado: EstadoTicket.enProceso.api, q: q),
        mios => TicketsFilter(asignado: miId, q: q),
        errores => TicketsFilter(tipo: 'ERROR', q: q),
        respondidos => TicketsFilter(estado: EstadoTicket.respondido.api, q: q),
        cerrados => TicketsFilter(estado: EstadoTicket.cerrado.api, q: q),
        todos => TicketsFilter(q: q),
      };
}

/// Mesa de ayuda: tickets de mensajes y reportes de error de los clientes.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  _Vista _vista = _Vista.nuevos;
  String _q = '';
  Timer? _debounce;
  final _scroll = ScrollController();

  TicketsFilter get _filtro =>
      _vista.filtro(ref.read(authControllerProvider).user?.id, _q);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) ref.read(ticketsPagerProvider(_filtro).notifier).cargarMas();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _buscar(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _q = texto);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtro = _filtro;
    final lista = ref.watch(ticketsPagerProvider(filtro));

    return Scaffold(
      appBar: AppBar(title: const Text('Mesa de ayuda')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: _buscar,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Folio (#41), nombre, correo o asunto',
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final v in _Vista.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(v.etiqueta),
                      selected: _vista == v,
                      selectedColor: AppColors.primary,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _vista == v ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _vista = v),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => ref.refresh(ticketsPagerProvider(filtro).future).then((_) {}, onError: (_) {}),
              child: lista.when(
                skipLoadingOnRefresh: true,
                loading: () => const LoadingList(),
                error: (e, _) => ErrorView(
                  message: e is ApiException ? e.message : 'No se pudieron cargar los tickets',
                  onRetry: () => ref.invalidate(ticketsPagerProvider(filtro)),
                ),
                data: (l) {
                  if (l.tickets.isEmpty) {
                    return const EmptyView(
                      icon: Icons.inbox_outlined,
                      title: 'Sin tickets',
                      message: 'No hay nada en esta vista',
                    );
                  }
                  return ListView.separated(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: l.tickets.length + 1,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) {
                      if (i == l.tickets.length) {
                        return PieDeLista(
                          cargando: l.cargandoMas,
                          hayMas: l.hayMas,
                          total: l.total,
                          error: l.error,
                          onReintentar: () => ref.read(ticketsPagerProvider(filtro).notifier).cargarMas(),
                        );
                      }
                      final m = l.tickets[i];
                      return ThreadTile(
                        hilo: m,
                        titulo: '${m.folioTexto} ${m.nombre}'.trim(),
                        mostrarPrioridad: true,
                        nuevo: m.noLeidoAdmin,
                        extra: m.asignadoNombre == null ? null : 'Asignado a ${m.asignadoNombre}',
                        onTap: () async {
                          await context.push(Routes.adminMessage(m.id));
                          // Al volver se refleja lo que cambió dentro del ticket.
                          ref.invalidate(ticketsPagerProvider);
                          ref.read(noLeidosProvider.notifier).refrescar();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
