import 'package:flutter/material.dart';

/// Centralized theme. Dark-first, Discord-inspired.
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF5865F2); // blurple
  static const bg = Color(0xFF17181C);
  static const surface = Color(0xFF1E1F24);
  static const surfaceAlt = Color(0xFF26272E);
  static const textPrimary = Color(0xFFE8E9ED);
  static const textSecondary = Color(0xFF9A9CA5);
  static const success = Color(0xFF3BA55D);
  static const danger = Color(0xFFED4245);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bg,
        selectedIconTheme: const IconThemeData(color: textPrimary),
        unselectedIconTheme: const IconThemeData(color: textSecondary),
        selectedLabelTextStyle: const TextStyle(color: textPrimary),
        unselectedLabelTextStyle: const TextStyle(color: textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: surfaceAlt),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: seed),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceAlt,
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
