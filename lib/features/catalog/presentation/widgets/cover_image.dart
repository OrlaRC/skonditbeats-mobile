import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Portada de un beat o paquete con placeholder si no hay imagen o falla la carga.
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, this.url, this.size, this.radius = 12, this.icon = Icons.music_note});

  final String? url;
  final double? size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.primary, size: (size ?? 80) * 0.4),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: size != null ? (size! * 3).round() : 600,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
            ),
    );
  }
}
