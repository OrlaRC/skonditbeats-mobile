import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../player/mini_player.dart';

/// Estructura del cliente: barra inferior (Inicio, Tienda, Paquetes, Carrito)
/// y el mini-reproductor arriba de ella. Cada pestaña conserva su estado.
class ClientShell extends ConsumerWidget {
  const ClientShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartProvider).length;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.primary,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (i) =>
                navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: Colors.black),
                label: 'Inicio',
              ),
              const NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront, color: Colors.black),
                label: 'Tienda',
              ),
              const NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music, color: Colors.black),
                label: 'Paquetes',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: cartCount > 0,
                  label: Text('$cartCount'),
                  backgroundColor: AppColors.primary,
                  textColor: Colors.black,
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: cartCount > 0,
                  label: Text('$cartCount'),
                  child: const Icon(Icons.shopping_cart, color: Colors.black),
                ),
                label: 'Carrito',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
