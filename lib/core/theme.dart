import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Define a identidade visual do aplicativo (Branding e Design System).
///
/// Analogia: Funciona como um arquivo CSS global no Web ou um arquivo de recursos XAML no WPF/W32.
/// Centralizamos todas as cores e fontes aqui para facilitar mudanças globais.
class AppTheme {
  // Paleta de cores extraída do design original.

  /// Cor de fundo principal (quase preto).
  static const Color bg = Color(0xFF060A12);

  /// Cor de superfície para painéis e modais.
  static const Color surface = Color(0xFF0D1320);

  /// Cor para cartões e elementos de destaque secundário.
  static const Color card = Color(0xFF111A2B);

  /// Cor para bordas e divisores.
  static const Color border = Color(0xFF1C2940);

  /// Cor de destaque principal (Azul).
  static const Color accent = Color(0xFF3B82F6);

  /// Cor para estados de sucesso e confirmação.
  static const Color green = Color(0xFF10B981);

  /// Cor para estados de erro, perigo e alertas críticos.
  static const Color red = Color(0xFFEF4444);

  /// Cor principal para textos.
  static const Color text = Color(0xFFE5E9F0);

  /// Cor para textos secundários ou desabilitados.
  static const Color muted = Color(0xFF6B8099);

  /// Cor para alertas de atenção e avisos intermediários.
  static const Color yellow = Color(0xFFF59E0B);

  /// Retorna as configurações de tema Escuro (Dark Mode) do aplicativo.
  ///
  /// Utiliza Material 3 e a fonte 'IBM Plex Mono' para uma estética técnica.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
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
          fontSize: 18,
        ),
      ),
    );
  }
}
