import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';

/// Lista de requisitos de la contraseña que se marcan mientras el usuario escribe.
class PasswordRules extends StatelessWidget {
  const PasswordRules({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final rules = Validators.passwordRules(password);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rules.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    r.value ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: r.value ? AppColors.success : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    r.key,
                    style: TextStyle(
                      fontSize: 13,
                      color: r.value ? AppColors.success : AppColors.textMuted,
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
