import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/beat.dart';
import '../../catalog/domain/pack.dart';
import '../domain/cart_item.dart';
import 'cart_controller.dart';

/// Acciones de "agregar al carrito" compartidas por tienda, paquetes e inicio.
/// Dan retroalimentación con vibración + mensaje.
Future<bool> addBeatToCart(BuildContext context, WidgetRef ref, Beat beat) async {
  final owned = await ref.read(ownedBeatIdsProvider.future).catchError((_) => <String>{});
  final result = await ref.read(cartProvider.notifier).addBeat(beat, owned: owned);
  if (context.mounted) _feedback(context, result);
  return result.ok;
}

Future<bool> addPackToCart(BuildContext context, WidgetRef ref, Pack pack, {bool goToPay = false}) async {
  final owned = await ref.read(ownedBeatIdsProvider.future).catchError((_) => <String>{});
  final result = await ref.read(cartProvider.notifier).addPack(pack, owned: owned);
  if (!context.mounted) return result.ok;

  // "Comprar ahora": si ya estaba en el carrito también se va al pago.
  final yaEstaba = !result.ok && ref.read(cartProvider.notifier).contains(CartItemType.pack, pack.id);
  if (goToPay && (result.ok || yaEstaba)) {
    HapticFeedback.lightImpact();
    context.push(Routes.payment);
    return true;
  }
  _feedback(context, result);
  return result.ok;
}

void _feedback(BuildContext context, CartResult result) {
  result.ok ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
  showAppSnack(context, result.message, type: result.ok ? SnackType.success : SnackType.info);
}
