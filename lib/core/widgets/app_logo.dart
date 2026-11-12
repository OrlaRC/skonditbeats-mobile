import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo "BS" de SkonditBeats (el mismo bs1.png de la web), con el brillo
/// amarillo que tiene en la página (drop-shadow).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.width = 180, this.glow = true});

  static const asset = 'assets/images/logo.png';

  final double width;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(asset, width: width, semanticLabel: 'Logo SkonditBeats');
    if (!glow) return logo;

    // El PNG es blanco con fondo transparente: una copia teñida de amarillo
    // y difuminada detrás del original simula el drop-shadow de la web.
    return Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.decal),
            child: Image.asset(asset, width: width, color: AppColors.primary.withValues(alpha: 0.55)),
          ),
        ),
        logo,
      ],
    );
  }
}
