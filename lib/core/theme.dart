import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Paleta extraída do seu HTML
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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      
      // Tipografia IBM Plex Mono
      textTheme: GoogleFonts.ibmPlexMonoTextTheme().apply(
        bodyColor: text,
        displayColor: text,
      ),

      // FIX PARA FLUTTER 3.41:
      // Removemos a definição conflituosa de 'cardTheme' aqui.
      // Definiremos o estilo visual diretamente nos widgets ou
      // deixaremos o padrão Material 3 que já é próximo do desejado.
      
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