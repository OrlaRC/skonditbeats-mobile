import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../catalog/presentation/widgets/cover_image.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../domain/cart_item.dart';
import 'cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar carrito'),
        content: const Text('Se quitarán todos los artículos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vaciar')),
        ],
      ),
    );
    if (ok == true) await ref.read(cartProvider.notifier).clear();
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, CartItem item) async {
    await ref.read(cartProvider.notifier).remove(item);
    HapticFeedback.selectionClick();
    if (context.mounted) showAppSnack(context, '${item.nombre} se quitó del carrito');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final total = ref.read(cartProvider.notifier).total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrito'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Vaciar carrito',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyView(
              icon: Icons.shopping_cart_outlined,
              title: 'Tu carrito está vacío',
              message: 'Explora la tienda y agrega los beats que te gusten',
              action: FilledButton(onPressed: () => context.go(Routes.store), child: const Text('Ir a la tienda')),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return Dismissible(
                        key: ValueKey('${item.tipo.name}-${item.itemId}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _remove(context, ref, item),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.delete_outline, color: AppColors.error),
                        ),
                        child: _CartTile(item: item, onRemove: () => _remove(context, ref, item)),
                      );
                    },
                  ),
                ),
                _Summary(count: items.length, total: total),
              ],
            ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.item, required this.onRemove});

  final CartItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CoverImage(
            url: item.imagenUrl,
            size: 56,
            radius: 10,
            icon: item.isPack ? Icons.library_music : Icons.music_note,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.isPack)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('PACK',
                            style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    Flexible(
                      child: Text(item.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item.detalle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          Text(formatMoney(item.precio, currency: false),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          IconButton(
            tooltip: 'Quitar ${item.nombre}',
            icon: const Icon(Icons.close, color: AppColors.textMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.total});

  final int count;
  final num total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('$count artículo${count == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.textMuted)),
                const Spacer(),
                const Text('Total  ', style: TextStyle(color: AppColors.textMuted)),
                Text(formatMoney(total),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => context.push(Routes.payment),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Ir a pagar'),
            ),
          ],
        ),
      ),
    );
  }
}
