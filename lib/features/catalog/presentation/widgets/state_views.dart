import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Estados de carga, error y vacío reutilizables. Todos son desplazables
/// para que el "jalar para actualizar" funcione también en estos estados.

class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(6)),
        );
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(160, 14), const SizedBox(height: 8), bar(100, 12), const SizedBox(height: 8), bar(60, 12)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _Centered(
        icon: Icons.cloud_off_outlined,
        iconColor: AppColors.error,
        title: 'Algo salió mal',
        message: message,
        action: FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      _Centered(icon: icon, title: title, message: message, action: action);
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, required this.message, this.action, this.iconColor});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 56, color: iconColor ?? AppColors.textMuted),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                if (action != null) ...[const SizedBox(height: 20), SizedBox(width: 200, child: action)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Último renglón de una lista paginada: indicador de carga, error con
/// reintento o la cuenta de resultados al llegar al final.
class PieDeLista extends StatelessWidget {
  const PieDeLista({
    super.key,
    required this.cargando,
    required this.hayMas,
    required this.total,
    required this.onReintentar,
    this.error,
  });

  final bool cargando;
  final bool hayMas;
  final int total;
  final String? error;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
            TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (cargando || hayMas) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text('$total resultado${total == 1 ? '' : 's'}',
          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
    );
  }
}
