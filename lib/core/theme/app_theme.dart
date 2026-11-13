import 'package:flutter/material.dart';

abstract class AppTheme {
  AppTheme._();

  static const Color brand = Color(0xFF0B6E4F);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: brand);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
