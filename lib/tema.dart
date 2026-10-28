import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cores que mudam com o tema (claro/escuro). Use `context.cTexto`, etc.
extension CoresApp on BuildContext {
  bool get _escuro => Theme.of(this).brightness == Brightness.dark;

  /// Fundo de cartões, barras e diálogos (branco no tema claro).
  Color get cSuperficie => _escuro ? const Color(0xFF1E293B) : Colors.white;

  /// Fundo suave de secções e campos (cinza muito claro no tema claro).
  Color get cFundoSuave => _escuro ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

  /// Linhas, contornos e separadores.
  Color get cBorda => _escuro ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  /// Texto principal.
  Color get cTexto => _escuro ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);

  /// Texto secundário.
  Color get cTexto2 => _escuro ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
}

ThemeData temaClaro() {
  final base = ThemeData(brightness: Brightness.light);
  return ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFF0F1E36),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF1E293B)),
    ),
  );
}

ThemeData temaEscuro() {
  final base = ThemeData(brightness: Brightness.dark);
  const superficie = Color(0xFF1E293B);
  return ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFF0F1E36),
    scaffoldBackgroundColor: const Color(0xFF0B1220),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0066FF),
      brightness: Brightness.dark,
    ).copyWith(surface: superficie),
    textTheme: GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: const Color(0xFFF1F5F9), displayColor: const Color(0xFFF1F5F9)),
    appBarTheme: const AppBarTheme(
      backgroundColor: superficie,
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFFF1F5F9)),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: superficie),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: superficie),
    popupMenuTheme: const PopupMenuThemeData(color: superficie),
    dividerColor: const Color(0xFF334155),
  );
}
