import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/money.dart';
import '../../../cart/presentation/cart_actions.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../player/player_controller.dart';
import '../../../transfers/domain/transferencia.dart';
import '../../../transfers/transfer_manager.dart';
import '../../data/catalog_repository.dart';
import '../../domain/beat.dart';
import 'cover_image.dart';

Future<void> showBeatDetail(BuildContext context, Beat beat) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _BeatDetail(beat: beat),
    );

class _BeatDetail extends ConsumerWidget {
  const _BeatDetail({required this.beat});

  final Beat beat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(playerProvider);
    final playing = now.isBeat(beat.id) && now.playing;
    final owned = ref.watch(ownedBeatIdsProvider).value?.contains(beat.id) ?? false;
    ref.watch(cartProvider);
    final inCart = ref.read(cartProvider.notifier).containsBeat(beat.id);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: CoverImage(url: beat.imagenUrl, size: 180, radius: 20)),
            const SizedBox(height: 20),
            Text(beat.nombre,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                Chip(label: Text(beat.genero), visualDensity: VisualDensity.compact),
                Chip(label: Text('${beat.bpm} BPM'), visualDensity: VisualDensity.compact),
              ],
            ),
            if (beat.descripcion != null && beat.descripcion!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(beat.descripcion!,
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            ],
            const SizedBox(height: 16),
            Text(formatMoney(beat.precio),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: beat.tieneAudio ? () => ref.read(playerProvider.notifier).toggle(beat) : null,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(beat.tieneAudio ? (playing ? 'Pausar' : 'Escuchar vista previa') : 'Sin vista previa'),
            ),
            if (owned && beat.tieneAudio) ...[
              const SizedBox(height: 12),
              _BotonDescarga(beat: beat),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (owned || inCart)
                  ? null
                  : () async {
                      if (await addBeatToCart(context, ref, beat) && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
              icon: Icon(owned ? Icons.check : Icons.add_shopping_cart),
              label: Text(owned ? 'Ya es tuyo' : inCart ? 'Ya está en tu carrito' : 'Agregar al carrito'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Descarga el audio del beat comprado. Si se corta la red, la descarga
/// continúa donde se quedó al reconectarse (peticiones de rango).
class _BotonDescarga extends ConsumerWidget {
  const _BotonDescarga({required this.beat});

  final Beat beat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(transferManagerProvider
        .select((l) => l.where((t) => !t.esSubida && t.url == beat.audioUrl).firstOrNull));
    final listo = t?.estado == EstadoTransferencia.completada;
    final texto = switch (t?.estado) {
      null => 'Descargar MP3',
      EstadoTransferencia.completada => 'Descargado en el teléfono',
      EstadoTransferencia.error => 'Reintentar descarga',
      EstadoTransferencia.pausada => 'Descarga en pausa · continuar',
      final e => '${e.etiqueta} · ${((t!.progreso ?? 0) * 100).round()} %',
    };
    return OutlinedButton.icon(
      onPressed: listo
          ? null
          : () async {
              final cola = ref.read(transferManagerProvider.notifier);
              if (t != null) return cola.reanudar(t.id);
              await cola.descargar(url: beat.audioUrl!, titulo: beat.nombre, nombreArchivo: '${beat.nombre}.mp3');
            },
      icon: Icon(listo ? Icons.download_done : Icons.download),
      label: Text(texto),
    );
  }
}
