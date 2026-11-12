import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/beat.dart';
import '../../catalog/presentation/widgets/beat_detail_sheet.dart';
import '../../catalog/presentation/widgets/cover_image.dart';
import '../../notifications/avisos.dart';
import '../../player/player_controller.dart';
import 'home_placeholder.dart';

/// Inicio del cliente: novedades, paquete destacado y accesos rápidos.
class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final beats = ref.watch(novedadesProvider);
    final packs = ref.watch(packsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text('Hola, ${user?.nombre.split(' ').first ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Mis tickets',
            onPressed: () => context.push(Routes.myMessages),
            icon: Badge(
              isLabelVisible: ref.watch(noLeidosProvider).total > 0,
              label: Text('${ref.watch(noLeidosProvider).total}'),
              backgroundColor: AppColors.primary,
              textColor: Colors.black,
              child: const Icon(Icons.confirmation_number_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Mi perfil',
            onPressed: () => context.push(Routes.profile),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceHigh,
              foregroundImage: user?.fotoUrl != null ? NetworkImage(user!.fotoUrl!) : null,
              onForegroundImageError: user?.fotoUrl != null ? (_, _) {} : null,
              child: const Icon(Icons.person, size: 18, color: AppColors.primary),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => confirmarCerrarSesion(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(novedadesProvider);
          ref.invalidate(packsProvider);
          ref.invalidate(ownedBeatIdsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Hero(onTap: () => context.go(Routes.store)),
            _SectionTitle('Lo más nuevo', onMore: () => context.go(Routes.store)),
            SizedBox(
              height: 210,
              child: beats.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                error: (_, _) => const Center(
                  child: Text('No se pudieron cargar los beats', style: TextStyle(color: AppColors.textMuted)),
                ),
                data: (lista) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _BeatCard(beat: lista[i], queue: lista),
                ),
              ),
            ),
            if (packs.value case final list? when list.isNotEmpty) ...[
              _SectionTitle('Paquete destacado', onMore: () => context.go(Routes.packs)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onTap: () => context.go(Routes.packs),
                    leading: CoverImage(url: list.first.imagenUrl, size: 60, icon: Icons.library_music),
                    title: Text(list.first.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${list.first.beats.length} beats · ${formatMoney(list.first.precio)}'
                      '${list.first.ahorro > 0 ? '\nAhorras ${formatMoney(list.first.ahorro)}' : ''}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            ],
            const _SectionTitle('Más opciones'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.support_agent,
                      label: 'Contacto',
                      onTap: () => context.push(Routes.contact),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.person_outline,
                      label: 'Mi perfil',
                      onTap: () => context.push(Routes.profile),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFACC15), Color(0xFFEAB308)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Encuentra tu próximo beat',
                          style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text('Rap, Trap, Drill y más. Escúchalos antes de comprar.',
                          style: TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
                Icon(Icons.headphones, size: 52, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (onMore != null) TextButton(onPressed: onMore, child: const Text('Ver todo')),
        ],
      ),
    );
  }
}

class _BeatCard extends ConsumerWidget {
  const _BeatCard({required this.beat, required this.queue});

  final Beat beat;
  final List<Beat> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(playerProvider);
    final playing = now.isBeat(beat.id) && now.playing;

    return SizedBox(
      width: 140,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showBeatDetail(context, beat),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverImage(url: beat.imagenUrl, size: 140, radius: 14),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: IconButton.filled(
                    tooltip: playing ? 'Pausar' : 'Escuchar',
                    style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: () => ref.read(playerProvider.notifier).toggle(beat, queue: queue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(beat.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${beat.genero} · ${formatMoney(beat.precio, currency: false)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
