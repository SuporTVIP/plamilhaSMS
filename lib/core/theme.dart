import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Define a identidade visual do aplicativo (Branding e Design System).
///
/// Analogia: Funciona como um arquivo CSS global no Web ou um arquivo de recursos XAML no WPF/W32.
/// Centralizamos todas as cores e fontes aqui para facilitar mudanças globais.
class AppTheme {
  // Paleta de cores extraída do design original.
  // Usamos hexadecimal 0xFF seguido do código da cor (ex: 3B82F6).
  static const Color bg = Color(0xFF060A12);
  static const Color surface = Color(0xFF0D1320);
  static const Color card = Color(0xFF111A2B);
  static const Color border = Color(0xFF1C2940);
  static const Color accent = Color(0xFF3B82F6);
  static const Color green = Color(0xFF10B981);
  static const Color red = Color(0xFFEF4444);
  static const Color text = Color(0xFFE5E9F0);
  static const Color muted = Color(0xFF6B8099);
  static const Color yellow = Color(0xFFF59E0B);

  /// Retorna as configurações de tema Escuro (Dark Mode).
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true, // Habilita o design system mais moderno do Google (Material 3)
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      
      // Tipografia: Usamos a fonte 'IBM Plex Mono' para dar um ar técnico/terminal.
      // Analogia: Similar a definir a font-family no body do CSS.
      textTheme: GoogleFonts.ibmPlexMonoTextTheme().apply(
        bodyColor: text,
        displayColor: text,
      ),

      // Configuração global para as Barras de Título (AppBars)
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: text, 
          fontWeight: FontWeight.bold, 
          fontSize: 18
        ),
      ),
    );
  }
}
