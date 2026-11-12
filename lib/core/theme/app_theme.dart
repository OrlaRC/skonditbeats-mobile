import 'package:flutter/material.dart';

/// Colores de la marca (los mismos de la versión web: negro + amarillo).
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFFACC15);
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF141414);
  static const Color surfaceHigh = Color(0xFF1F1F1F);
  static const Color border = Color(0xFF2A2A2A);
  static const Color textMuted = Color(0xFFA3A3A3);
  static const Color error = Color(0xFFF87171);
  static const Color success = Color(0xFF4ADE80);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.black,
      surface: AppColors.background,
      onSurface: Colors.white,
      surfaceContainerHighest: AppColors.surfaceHigh,
      error: AppColors.error,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.black),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
