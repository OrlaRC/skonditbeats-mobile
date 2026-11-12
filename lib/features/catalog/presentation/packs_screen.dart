import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_actions.dart';
import '../../cart/presentation/cart_controller.dart';
import '../data/catalog_repository.dart';
import '../domain/pack.dart';
import 'widgets/beat_tile.dart';
import 'widgets/cover_image.dart';
import 'widgets/state_views.dart';

/// Paquetes de beats con descuento.
class PacksScreen extends ConsumerWidget {
  const PacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(packsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paquetes')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(ownedBeatIdsProvider);
          return ref.refresh(packsProvider.future).then((_) {}, onError: (_) {});
        },
        child: packs.when(
          skipLoadingOnRefresh: true,
          loading: () => const LoadingList(count: 3),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'No se pudieron cargar los paquetes',
            onRetry: () => ref.invalidate(packsProvider),
          ),
          data: (list) => list.isEmpty
              ? const EmptyView(
                  icon: Icons.library_music_outlined,
                  title: 'Sin paquetes por ahora',
                  message: 'Vuelve pronto: aquí aparecerán las promociones',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => PackCard(pack: list[i]),
                ),
        ),
      ),
    );
  }
}

class PackCard extends ConsumerStatefulWidget {
  const PackCard({super.key, required this.pack});

  final Pack pack;

  @override
  ConsumerState<PackCard> createState() => _PackCardState();
}

class _PackCardState extends ConsumerState<PackCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final owned = ref.watch(ownedBeatIdsProvider).value ?? const <String>{};
    final yaTiene = pack.beats.where((b) => owned.contains(b.id)).length;
    ref.watch(cartProvider);
    final inCart = ref.read(cartProvider.notifier).contains(CartItemType.pack, pack.id);
    final disponible = yaTiene == 0 && pack.beats.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CoverImage(url: pack.imagenUrl, radius: 0, icon: Icons.library_music),
              ),
              if (pack.ahorro > 0)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                    child: Text('Ahorras ${formatMoney(pack.ahorro, currency: false)}',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.nombre,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                if (pack.descripcion != null && pack.descripcion!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(pack.descripcion!, style: const TextStyle(color: AppColors.textMuted)),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(pack.precio),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    if (pack.ahorro > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          formatMoney(pack.precioSeparado, currency: false),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
                if (yaTiene > 0) ...[
                  const SizedBox(height: 8),
                  Text('Ya tienes $yaTiene de estos beats, no se puede comprar el paquete.',
                      style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            label: Text('${_expanded ? 'Ocultar' : 'Ver'} los ${pack.beats.length} beats incluidos'),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        for (final b in pack.beats) BeatTile(beat: b, queue: pack.beats, showCartButton: false),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: disponible && !inCart ? () => addPackToCart(context, ref, pack) : null,
                    child: Text(inCart ? 'En el carrito' : 'Agregar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: disponible ? () => addPackToCart(context, ref, pack, goToPay: true) : null,
                    child: const Text('Comprar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
