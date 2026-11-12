import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../admin/data/admin_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../../notifications/avisos.dart';
import '../data/contact_repository.dart';
import '../domain/contact_thread.dart';
import 'thread_list.dart';

String formatoFecha(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
}

/// Detalle de un ticket. Lo usan el cliente y el administrador; solo el
/// administrador cambia la prioridad, lo devuelve, lo pasa o lo elimina.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.id, required this.admin});

  final String id;
  final bool admin;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _texto = TextEditingController();
  bool _enviando = false;

  /// Clave de la respuesta que se está escribiendo. Se conserva si el envío
  /// falla, así el reintento no duplica la respuesta; se cambia al confirmarse.
  String _claveRespuesta = nuevaClaveIdempotencia();

  @override
  void initState() {
    super.initState();
    // Abrir el ticket apaga su aviso (insignia y notificación).
    Future.microtask(() => ref.read(noLeidosProvider.notifier).marcarVisto(widget.id));
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _recargar() {
    ref.invalidate(ticketProvider(widget.id));
    if (!widget.admin) ref.invalidate(myMessagesProvider);
  }

  /// Ejecuta la acción con su indicador, recarga el ticket y avisa el resultado.
  Future<bool> _ejecutar(Future<void> Function() accion, String exito) async {
    if (_enviando) return false;
    setState(() => _enviando = true);
    try {
      await accion();
      _recargar();
      HapticFeedback.mediumImpact();
      if (mounted) showAppSnack(context, exito, type: SnackType.success);
      return true;
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      // 409: alguien más cambió el ticket; se recarga para mostrar lo vigente.
      if (e.statusCode == 409) _recargar();
      if (mounted) {
        final msg = e.sinRed
            ? '${e.message} Tu respuesta sigue escrita: vuelve a enviarla cuando haya conexión.'
            : e.message;
        showAppSnack(context, msg, type: SnackType.error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _responder() async {
    final texto = _texto.text.trim();
    if (texto.length < 2 || _enviando) return;
    FocusScope.of(context).unfocus();
    final clave = _claveRespuesta;
    final ok = await _ejecutar(
      () => ref.read(contactRepositoryProvider).reply(widget.id, texto, clave: clave),
      'Respuesta enviada',
    );
    if (ok) {
      _texto.clear();
      _claveRespuesta = nuevaClaveIdempotencia();
    }
  }

  Future<void> _cambiarEstado(ContactThread h, EstadoTicket nuevo) => _ejecutar(
        () => ref.read(contactRepositoryProvider).setEstado(widget.id, nuevo, esperado: h.estado),
        'Ticket ${h.folioTexto} ${nuevo.etiqueta.toLowerCase()}',
      );

  Future<void> _elegirEstado(ContactThread h) async {
    final nuevo = await showModalBottomSheet<EstadoTicket>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Cambiar estado', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final e in EstadoTicket.manualesAdmin)
              ListTile(
                leading: Icon(Icons.circle, size: 14, color: colorEstado(e)),
                title: Text(e.etiqueta),
                trailing: e == h.estadoTicket ? const Icon(Icons.check, color: AppColors.primary) : null,
                enabled: e != h.estadoTicket,
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        ),
      ),
    );
    if (nuevo != null) await _cambiarEstado(h, nuevo);
  }

  Future<void> _elegirPrioridad(ContactThread h) async {
    final nueva = await showModalBottomSheet<PrioridadTicket>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Prioridad', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final p in PrioridadTicket.values)
              ListTile(
                leading: Icon(Icons.flag, color: colorPrioridad(p)),
                title: Text(p.etiqueta),
                trailing: p == h.prioridad ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (nueva == null || nueva == h.prioridad) return;
    await _ejecutar(
      () => ref.read(adminRepositoryProvider).setPrioridad(widget.id, nueva.api),
      'Prioridad ${nueva.etiqueta.toLowerCase()}',
    );
  }

  Future<void> _devolver() async {
    final motivo = await showDialog<String>(context: context, builder: (_) => const _DevolverDialog());
    if (motivo == null) return;
    await _ejecutar(
      () => ref.read(adminRepositoryProvider).returnToClient(widget.id, motivo),
      'Se devolvió al cliente',
    );
  }

  Future<void> _pasar(ContactThread hilo) async {
    final adminId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _AdminsSheet(excluir: {?hilo.asignadoId}),
    );
    if (adminId == null) return;
    await _ejecutar(
      () => ref.read(adminRepositoryProvider).assign(widget.id, adminId),
      'Ticket asignado',
    );
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ticket'),
        content: const Text('Se borrará con toda su conversación. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    final borrado = await _ejecutar(
      () => ref.read(adminRepositoryProvider).deleteMessage(widget.id),
      'Ticket eliminado',
    );
    if (borrado && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.id));
    final hilo = ticket.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(hilo == null ? 'Ticket' : 'Ticket ${hilo.folioTexto}'),
        actions: [
          if (hilo != null && !widget.admin)
            TextButton(
              onPressed: _enviando
                  ? null
                  : () => _cambiarEstado(hilo, hilo.estadoTicket.terminado ? EstadoTicket.abierto : EstadoTicket.cerrado),
              child: Text(hilo.estadoTicket.terminado ? 'Reabrir' : 'Cerrar'),
            ),
          if (widget.admin && hilo != null)
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              enabled: !_enviando,
              onSelected: (a) => switch (a) {
                'estado' => _elegirEstado(hilo),
                'prioridad' => _elegirPrioridad(hilo),
                'devolver' => _devolver(),
                'pasar' => _pasar(hilo),
                _ => _eliminar(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'estado', child: Text('Cambiar estado')),
                const PopupMenuItem(value: 'prioridad', child: Text('Cambiar prioridad')),
                if (hilo.tieneCuenta && !hilo.cerrado)
                  const PopupMenuItem(value: 'devolver', child: Text('Pedir más información')),
                const PopupMenuItem(value: 'pasar', child: Text('Pasar a otro admin')),
                const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
              ],
            ),
        ],
      ),
      body: ticket.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingList(count: 3),
        error: (e, _) => e is ApiException && e.statusCode == 404
            ? const EmptyView(
                icon: Icons.search_off,
                title: 'Ticket no disponible',
                message: 'Puede que ya se haya eliminado',
              )
            : ErrorView(
                message: e is ApiException ? e.message : 'No se pudo cargar el ticket',
                onRetry: _recargar,
              ),
        data: (h) => Column(
          children: [
            if (_enviando) const LinearProgressIndicator(color: AppColors.primary),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.refresh(ticketProvider(widget.id).future).then((_) {}, onError: (_) {}),
                child: _conversacion(h),
              ),
            ),
            h.cerrado ? _cerradoAviso(h) : _caja(h),
          ],
        ),
      ),
    );
  }

  Widget _conversacion(ContactThread h) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(h.asunto?.trim().isNotEmpty == true ? h.asunto! : (h.esError ? 'Reporte de error' : 'Mensaje'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            EtiquetaTicket(h.estadoLegible, colorEstado(h.estadoTicket)),
            if (widget.admin) EtiquetaTicket('Prioridad ${h.prioridad.etiqueta.toLowerCase()}', colorPrioridad(h.prioridad)),
            EtiquetaTicket(h.esError ? 'Error' : 'Mensaje', h.esError ? AppColors.error : AppColors.textMuted),
            if (widget.admin && h.asignadoNombre != null) EtiquetaTicket('Asignado a ${h.asignadoNombre}', AppColors.textMuted),
          ],
        ),
        if (!widget.admin && h.estado == ContactThread.devuelto)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Necesitamos más información: responde abajo para continuar.',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 14),
        _Burbuja(
          autor: widget.admin ? '${h.nombre} · ${h.email}' : 'Tú',
          texto: h.mensaje,
          fecha: h.fecha,
          derecha: !widget.admin,
        ),
        for (final r in h.respuestas)
          _Burbuja(
            autor: r.esAdmin == widget.admin ? 'Tú (${r.autor})' : r.autor,
            texto: r.texto,
            fecha: r.fecha,
            derecha: r.esAdmin == widget.admin,
          ),
      ],
    );
  }

  Widget _cerradoAviso(ContactThread h) => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: AppColors.surface,
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: AppColors.textMuted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Ticket cerrado. Reábrelo para seguir la conversación.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              TextButton(
                onPressed: _enviando ? null : () => _cambiarEstado(h, EstadoTicket.abierto),
                child: const Text('Reabrir'),
              ),
            ],
          ),
        ),
      );

  Widget _caja(ContactThread h) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _texto,
                enabled: !_enviando,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                // Si cambia el texto, es otra respuesta: otra clave.
                onChanged: (_) => _claveRespuesta = nuevaClaveIdempotencia(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: widget.admin && !h.tieneCuenta ? 'Responder por correo' : 'Escribe tu respuesta',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Enviar',
              color: AppColors.primary,
              onPressed: _enviando ? null : _responder,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.autor, required this.texto, required this.derecha, this.fecha});

  final String autor;
  final String texto;
  final bool derecha;
  final DateTime? fecha;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: derecha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: derecha ? AppColors.surfaceHigh : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(autor, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text(texto),
            if (fecha != null) ...[
              const SizedBox(height: 4),
              Text(formatoFecha(fecha!), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DevolverDialog extends StatefulWidget {
  const _DevolverDialog();

  @override
  State<_DevolverDialog> createState() => _DevolverDialogState();
}

class _DevolverDialogState extends State<_DevolverDialog> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pedir más información'),
      content: TextField(
        controller: _motivo,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: '¿Qué información necesitas?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: _motivo.text.trim().length < 2 ? null : () => Navigator.pop(context, _motivo.text.trim()),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

/// Elige un administrador activo, distinto de quien ya tiene el caso.
class _AdminsSheet extends ConsumerWidget {
  const _AdminsSheet({required this.excluir});

  final Set<String> excluir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);
    final miId = ref.watch(authControllerProvider.select((s) => s.user?.id));

    return SafeArea(
      child: users.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(e is ApiException ? e.message : 'No se pudieron cargar los administradores'),
        ),
        data: (list) {
          final admins = list.where((u) => u.isAdmin && u.activo && !excluir.contains(u.id)).toList();
          if (admins.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay otro administrador disponible', style: TextStyle(color: AppColors.textMuted)),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final a in admins)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
                  title: Text(a.id == miId ? '${a.nombre} (tú)' : a.nombre),
                  subtitle: Text(a.email, style: const TextStyle(color: AppColors.textMuted)),
                  onTap: () => Navigator.pop(context, a.id),
                ),
            ],
          );
        },
      ),
    );
  }
}
