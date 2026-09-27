import 'package:flutter/material.dart';

/// Colour tokens lifted from docs/anumati-prototype.html (`:root`).
class AC {
  static const ground = Color(0xFFF3EADB);
  static const surface = Color(0xFFFBF6EC);
  static const raised = Color(0xFFFFFDF8);
  static const sunk = Color(0xFFEADFCB);
  static const ink = Color(0xFF2A2118);
  static const ink2 = Color(0xFF5C4F40);
  static const ink3 = Color(0xFF7D6E5C);
  static const line = Color(0xFFDDCDB3);
  static const line2 = Color(0xFFE9DCC6);
  static const terra = Color(0xFFB4532A);
  static const terraInk = Color(0xFFFFF7EF);
  static const terraSoft = Color(0xFFF4DCCB);
  static const leaf = Color(0xFF3E6B3A);
  static const leafInk = Color(0xFFF4F8EF);
  static const leafSoft = Color(0xFFDDE8D3);
  static const turmeric = Color(0xFF9A6A10);
  static const turmericSoft = Color(0xFFF6E3B8);
  static const danger = Color(0xFF9E2F24);
  static const dangerSoft = Color(0xFFF4D6CF);
}

ThemeData anumatiTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AC.terra,
      primary: AC.terra,
      onPrimary: AC.terraInk,
      secondary: AC.leaf,
      onSecondary: AC.leafInk,
      surface: AC.ground,
      onSurface: AC.ink,
      error: AC.danger,
    ),
    scaffoldBackgroundColor: AC.ground,
    fontFamily: null,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: AC.leaf, foregroundColor: AC.leafInk, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AC.raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AC.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AC.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AC.terra, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AC.terra,
        foregroundColor: AC.terraInk,
        disabledBackgroundColor: AC.line,
        disabledForegroundColor: AC.ink3,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AC.terra,
        side: const BorderSide(color: AC.terra, width: 1.5),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(AC.raised),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AC.leaf : AC.line),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AC.terra : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AC.terra : AC.ink3),
    ),
  );
}
