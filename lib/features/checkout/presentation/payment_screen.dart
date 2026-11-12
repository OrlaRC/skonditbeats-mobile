import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/app_router.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/security/secure_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/card_formatters.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/presentation/app_lock_controller.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../data/orders_repository.dart';

/// Pago simulado. Nunca se guarda ni se envía la tarjeta: solo se valida
/// en el teléfono y después se crean las órdenes en la API.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _nombre = TextEditingController();
  final _expira = TextEditingController();
  final _cvv = TextEditingController();

  bool _procesando = false;

  /// Claves de idempotencia de cada cobro de este pago. Se reutilizan si el
  /// usuario reintenta tras un error de red, y se descartan al terminar.
  final _claves = <String, String>{};

  /// Lo que se pagó, para mostrar el comprobante después de vaciar el carrito.
  List<CartItem>? _pagado;

  @override
  void initState() {
    super.initState();
    _numero.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_numero, _nombre, _expira, _cvv]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirmarIdentidad(num total) async {
    final bio = ref.read(biometricServiceProvider);
    if (!await bio.isAvailable()) return true; // sin bloqueo de pantalla no se puede pedir
    final result = await ref.read(appLockProvider.notifier).runWithoutLock(
          () => bio.authenticate('Confirma el pago de ${formatMoney(total)}'),
        );
    switch (result) {
      case BiometricResult.success:
      case BiometricResult.unavailable:
        return true;
      case BiometricResult.lockedOut:
        if (mounted) showAppSnack(context, 'Demasiados intentos. Espera un momento.', type: SnackType.error);
        return false;
      case BiometricResult.canceled:
      case BiometricResult.failed:
        return false;
    }
  }

  /// La cuenta se comparte entre dispositivos: antes de cobrar se comprueba si
  /// algo del carrito ya se compró en otro. Devuelve true si se quitó algo, para
  /// que el usuario revise el nuevo total antes de pagar.
  Future<bool> _quitarCompradosEnOtroDispositivo() async {
    final Set<String> owned;
    try {
      ref.invalidate(ownedBeatIdsProvider);
      owned = await ref.read(ownedBeatIdsProvider.future);
    } on ApiException {
      return false; // Sin datos frescos, la API rechaza la compra repetida con un 409.
    }
    final quitados = await ref.read(cartProvider.notifier).removeOwned(owned);
    if (quitados.isEmpty) return false;
    HapticFeedback.heavyImpact();
    if (mounted) {
      showAppSnack(
        context,
        'Ya tenías ${quitados.map((i) => i.nombre).join(', ')}. Lo quitamos del carrito; revisa el total.',
        type: SnackType.error,
      );
    }
    return true;
  }

  Future<void> _pagar() async {
    FocusScope.of(context).unfocus();
    final items = ref.read(cartProvider);
    if (_procesando || items.isEmpty || !_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }

    if (await _quitarCompradosEnOtroDispositivo()) return;

    final total = ref.read(cartProvider.notifier).total;
    if (!await _confirmarIdentidad(total)) return;

    setState(() => _procesando = true);
    final orders = ref.read(ordersRepositoryProvider);
    final cart = ref.read(cartProvider.notifier);
    final pagados = <CartItem>[];

    try {
      // Una petición por grupo; lo que se paga se quita del carrito enseguida,
      // así un error a la mitad nunca cobra dos veces lo mismo al reintentar.
      for (final grupo in groupForCheckout(items)) {
        final clave = _claves.putIfAbsent(firmaDeGrupo(grupo), nuevaClaveIdempotencia);
        if (grupo.first.isPack) {
          await orders.buyPack(grupo.first.itemId, clave: clave);
        } else {
          await orders.buyBeats(grupo.map((i) => i.itemId).toList(), clave: clave);
        }
        for (final i in grupo) {
          await cart.remove(i);
        }
        pagados.addAll(grupo);
      }
      ref.invalidate(ownedBeatIdsProvider);
      _claves.clear();
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _pagado = pagados);
    } on ApiException catch (e) {
      ref.invalidate(ownedBeatIdsProvider);
      HapticFeedback.heavyImpact();
      if (mounted) {
        final parcial = pagados.isEmpty ? '' : ' Se pagaron ${pagados.length} artículo(s); el resto sigue en tu carrito.';
        // Sin respuesta no sabemos si se cobró: se dice así, y reintentar es
        // seguro porque se reenvía con la misma clave.
        final red = e.sinRed ? ' No se confirmó el cobro: vuelve a tocar Pagar, no se cobrará dos veces.' : '';
        showAppSnack(context, '${e.message}$parcial$red', type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pagado != null) return _Comprobante(items: _pagado!);

    final items = ref.watch(cartProvider);
    final total = ref.read(cartProvider.notifier).total;
    final brand = cardBrand(_numero.text);

    return SecureScreen(
      child: PopScope(
        canPop: !_procesando,
        child: Scaffold(
          appBar: AppBar(title: const Text('Pago')),
          body: items.isEmpty
              ? EmptyView(
                  icon: Icons.shopping_cart_outlined,
                  title: 'No hay nada que pagar',
                  message: 'Tu carrito está vacío',
                  action: FilledButton(onPressed: () => context.go(Routes.store), child: const Text('Ir a la tienda')),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Resumen(items: items, total: total),
                        const SizedBox(height: 24),
                        const Text('Datos de la tarjeta', style: TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _numero,
                          enabled: !_procesando,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.creditCardNumber],
                          inputFormatters: [CardNumberFormatter()],
                          decoration: InputDecoration(
                            labelText: 'Número de tarjeta',
                            prefixIcon: const Icon(Icons.credit_card),
                            suffixText: brand,
                          ),
                          validator: Validators.cardNumber,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _nombre,
                          enabled: !_procesando,
                          textCapitalization: TextCapitalization.characters,
                          autofillHints: const [AutofillHints.creditCardName],
                          decoration: const InputDecoration(
                            labelText: 'Nombre del titular',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: Validators.cardName,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _expira,
                                enabled: !_procesando,
                                keyboardType: TextInputType.number,
                                autofillHints: const [AutofillHints.creditCardExpirationDate],
                                inputFormatters: [CardExpiryFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'Vence (MM/AA)',
                                  prefixIcon: Icon(Icons.event_outlined),
                                ),
                                validator: (v) => Validators.cardExpiry(v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _cvv,
                                enabled: !_procesando,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                autofillHints: const [AutofillHints.creditCardSecurityCode],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'CVV',
                                  prefixIcon: Icon(Icons.password),
                                ),
                                validator: Validators.cvv,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Pago simulado: no se cobra ni se guarda tu tarjeta. '
                                  'Para probar usa 4242 4242 4242 4242.',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _procesando ? null : _pagar,
                          icon: _procesando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                                )
                              : const Icon(Icons.fingerprint),
                          label: Text(_procesando ? 'Procesando...' : 'Pagar ${formatMoney(total)}'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.items, required this.total});

  final List<CartItem> items;
  final num total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(i.isPack ? Icons.library_music : Icons.music_note, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(i.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(formatMoney(i.precio, currency: false)),
                ],
              ),
            ),
          const Divider(color: AppColors.border),
          Row(
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(formatMoney(total),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<num>(0, (s, i) => s + i.precio);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.check_circle, size: 88, color: AppColors.success),
                const SizedBox(height: 16),
                Text('¡Compra realizada!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Pagaste ${formatMoney(total)}. Tus beats ya están en tu cuenta.',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 24),
                _Resumen(items: items, total: total),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => context.go(Routes.store),
                  child: const Text('Seguir comprando'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => context.go(Routes.clientHome),
                  child: const Text('Ir al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
