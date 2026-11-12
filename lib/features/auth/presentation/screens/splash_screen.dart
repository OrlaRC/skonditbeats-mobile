import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_logo.dart';

/// Se muestra mientras se lee la sesión guardada; el router redirige solo.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(width: 160),
            SizedBox(height: 40),
            CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
