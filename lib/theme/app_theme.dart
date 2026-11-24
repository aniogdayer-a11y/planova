import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app_colors.dart';

class AppTheme {
  static const palettes = {
    'cream': Color(0xFFF0EEDF),
    'sage': Color(0xFFE8F0E6),
    'lavender': Color(0xFFEEE8F5),
    'rose': Color(0xFFF7E8EA),
    'sky': Color(0xFFE5EFF7),
  };

  static ThemeData forPalette(String name) {
    final base = lightTheme;
    final background = palettes[name] ?? palettes['cream']!;
    final surface = Color.lerp(background, Colors.white, 0.65)!;
    final border = Color.lerp(background, AppColors.charcoal, 0.18)!;
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        surface: surface,
        primaryContainer: background,
        secondaryContainer: background,
      ),
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: background),
      cardTheme: base.cardTheme.copyWith(color: surface),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: surface,
      ),
      dividerTheme: base.dividerTheme.copyWith(color: border),
      chipTheme: base.chipTheme.copyWith(selectedColor: background),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
        secondary: kIsWeb ? AppColors.taupe : const Color(0xFF795596),
        onSurface: AppColors.textPrimary,
        onPrimary: kIsWeb ? AppColors.cream : Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayMedium: const TextStyle(
          fontSize: 28,
          fontFamily: 'DM Serif Display',
          height: 1.2,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 16,
          fontFamily: 'Manrope',
          height: 1.5,
          color: AppColors.textSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: kIsWeb ? AppColors.cream : Colors.white,
          minimumSize: const Size(48, 50),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kIsWeb ? 6 : 16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kIsWeb ? 8 : 18),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 24),
    );
  }
}
