import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF12243E);
  static const teal = Color(0xFF0EA5A4);
  static const darkTeal = Color(0xFF076F70);
  static const background = Color(0xFFF4F7FB);
  static const text = Color(0xFF20314C);
  static const muted = Color(0xFF536480);
}

ThemeData katyuTheme({required bool useTeal}) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: useTeal ? AppColors.teal : AppColors.navy,
  ),
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.navy,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  ),
);
