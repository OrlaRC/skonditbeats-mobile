import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/money.dart';
import '../../../cart/presentation/cart_actions.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../player/player_controller.dart';
import '../../data/catalog_repository.dart';
import '../../domain/beat.dart';
import 'beat_detail_sheet.dart';
import 'cover_image.dart';

/// Renglón de un beat: portada con play, datos, precio y botón de carrito.
class BeatTile extends ConsumerWidget {
  const BeatTile({super.key, required this.beat, this.queue, this.showCartButton = true});

  final Beat beat;

  /// Lista a la que pertenece, para "anterior" y "siguiente" en el reproductor.
  final List<Beat>? queue;
  final bool showCartButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(playerProvider);
    final isCurrent = now.isBeat(beat.id);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showBeatDetail(context, beat),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            _PlayCover(beat: beat, queue: queue, isCurrent: isCurrent, now: now),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    beat.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isCurrent ? AppColors.primary : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${beat.genero} · ${beat.bpm} BPM',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(formatMoney(beat.precio),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
            if (showCartButton) BeatCartButton(beat: beat),
          ],
        ),
      ),
    );
  }
}

class _PlayCover extends ConsumerWidget {
  const _PlayCover({required this.beat, this.queue, required this.isCurrent, required this.now});

  final Beat beat;
  final List<Beat>? queue;
  final bool isCurrent;
  final NowPlaying now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = isCurrent && now.playing;
    return Semantics(
      button: true,
      label: playing ? 'Pausar ${beat.nombre}' : 'Escuchar ${beat.nombre}',
      child: GestureDetector(
        onTap: () => ref.read(playerProvider.notifier).toggle(beat, queue: queue),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CoverImage(url: beat.imagenUrl, size: 64),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: isCurrent ? Border.all(color: AppColors.primary, width: 2) : null,
              ),
            ),
            if (isCurrent && now.loading)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
              )
            else
              Icon(
                beat.tieneAudio
                    ? (playing ? Icons.pause_rounded : Icons.play_arrow_rounded)
                    : Icons.volume_off_outlined,
                size: 32,
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón de carrito con 3 estados: comprado, en el carrito, agregar.
class BeatCartButton extends ConsumerWidget {
  const BeatCartButton({super.key, required this.beat});

  final Beat beat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedBeatIdsProvider).value?.contains(beat.id) ?? false;
    ref.watch(cartProvider);
    final inCart = ref.read(cartProvider.notifier).containsBeat(beat.id);

    if (owned) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Chip(
          label: Text('Comprado', style: TextStyle(fontSize: 12)),
          avatar: Icon(Icons.check, size: 16, color: AppColors.success),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return IconButton(
      tooltip: inCart ? 'En tu carrito' : 'Agregar al carrito',
      icon: Icon(
        inCart ? Icons.shopping_cart : Icons.add_shopping_cart_outlined,
        color: inCart ? AppColors.primary : Colors.white,
      ),
      onPressed: inCart ? null : () => addBeatToCart(context, ref, beat),
    );
  }
}
