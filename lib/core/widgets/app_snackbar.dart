import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SnackType { success, error, info }

void showAppSnack(BuildContext context, String message, {SnackType type = SnackType.info}) {
  final (color, icon) = switch (type) {
    SnackType.success => (AppColors.success, Icons.check_circle_outline),
    SnackType.error => (AppColors.error, Icons.error_outline),
    SnackType.info => (AppColors.primary, Icons.info_outline),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceHigh,
        content: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
}
