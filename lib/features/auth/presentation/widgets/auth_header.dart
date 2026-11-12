import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_logo.dart';

/// Logo + título + subtítulo que comparten las pantallas de acceso.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppLogo(width: 170),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text.rich(
            const TextSpan(children: [
              TextSpan(text: 'Skondit'),
              TextSpan(text: 'Beats', style: TextStyle(color: AppColors.primary)),
            ]),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 24),
        Text(title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
