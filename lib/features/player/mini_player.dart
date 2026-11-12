import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../catalog/presentation/widgets/cover_image.dart';
import 'player_controller.dart';

/// Barra del reproductor que se queda visible mientras se navega por la tienda.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(playerProvider);
    final beat = now.beat;
    if (beat == null) return const SizedBox.shrink();

    final pos = ref.watch(playerPositionProvider).value;
    final progress = (pos != null && pos.$2 != null && pos.$2!.inMilliseconds > 0)
        ? (pos.$1.inMilliseconds / pos.$2!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: AppColors.surfaceHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            color: AppColors.primary,
            backgroundColor: AppColors.border,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                CoverImage(url: beat.imagenUrl, size: 44, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(beat.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        now.error ?? '${beat.genero} · ${beat.bpm} BPM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: now.error != null ? AppColors.error : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (now.loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                    ),
                  )
                else
                  IconButton(
                    tooltip: now.playing ? 'Pausar' : 'Reproducir',
                    iconSize: 32,
                    color: AppColors.primary,
                    icon: Icon(now.playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                    onPressed: () => ref.read(playerProvider.notifier).toggle(beat),
                  ),
                IconButton(
                  tooltip: 'Cerrar reproductor',
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => ref.read(playerProvider.notifier).stop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
