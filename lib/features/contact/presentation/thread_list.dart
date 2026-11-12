import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/contact_thread.dart';
import 'thread_screen.dart';

Color colorEstado(EstadoTicket e) => switch (e) {
      EstadoTicket.abierto => AppColors.primary,
      EstadoTicket.enProceso => const Color(0xFF60A5FA),
      EstadoTicket.devuelto => const Color(0xFFFB923C),
      EstadoTicket.respondido => AppColors.success,
      EstadoTicket.resuelto || EstadoTicket.cerrado => AppColors.textMuted,
    };

Color colorPrioridad(PrioridadTicket p) => switch (p) {
      PrioridadTicket.alta => AppColors.error,
      PrioridadTicket.media => AppColors.primary,
      PrioridadTicket.baja => AppColors.textMuted,
    };

/// Etiqueta pequeña de color (estado o prioridad).
class EtiquetaTicket extends StatelessWidget {
  const EtiquetaTicket(this.texto, this.color, {super.key});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// Renglón de un ticket en las listas del cliente y del administrador.
class ThreadTile extends StatelessWidget {
  const ThreadTile({
    super.key,
    required this.hilo,
    required this.titulo,
    required this.onTap,
    this.extra,
    this.mostrarPrioridad = false,
    this.nuevo = false,
  });

  /// Tiene una novedad sin leer: se resalta con un punto y en negritas.
  final bool nuevo;

  final ContactThread hilo;
  final String titulo;
  final String? extra;
  final bool mostrarPrioridad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Badge(
        isLabelVisible: nuevo,
        smallSize: 10,
        backgroundColor: AppColors.primary,
        child: Icon(
          hilo.esError ? Icons.bug_report_outlined : Icons.confirmation_number_outlined,
          color: hilo.esError ? AppColors.error : AppColors.primary,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: nuevo ? FontWeight.w900 : FontWeight.w700)),
          ),
          if (nuevo) const EtiquetaTicket('Nuevo', AppColors.primary),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hilo.asunto?.trim().isNotEmpty == true ? hilo.asunto! : hilo.mensaje.replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              EtiquetaTicket(hilo.estadoLegible, colorEstado(hilo.estadoTicket)),
              if (mostrarPrioridad)
                EtiquetaTicket('Prioridad ${hilo.prioridad.etiqueta.toLowerCase()}', colorPrioridad(hilo.prioridad)),
              Text(
                [
                  if (hilo.totalRespuestas > 0) '${hilo.totalRespuestas} resp.',
                  ?extra,
                  if (hilo.fecha != null) formatoFecha(hilo.fecha!),
                ].join(' · '),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
