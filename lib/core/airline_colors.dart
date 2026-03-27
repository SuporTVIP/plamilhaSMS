import 'package:flutter/material.dart';
import '../core/theme.dart'; // Ajuste o caminho do seu AppTheme se precisar

class AirlineColors {
  /// Retorna a Cor Principal (Usada nas bordas, ícones e nas NOTIFICAÇÕES)
  static Color getPrincipal(String programa) {
    final String prog = programa.toUpperCase();
    if (prog.contains("AZUL")) return const Color(0xFF38BDF8);
    if (prog.contains("LATAM")) return const Color(0xFFF43F5E);
    if (prog.contains("SMILES")) return const Color(0xFFF59E0B);
    if (prog.contains("TAP")) return const Color(0xFF2DD4BF);
    if (prog.contains("IBERIA") || prog.contains("IBÉRIA")) return const Color(0xFFD30000);
    if (prog.contains("AADVANTAGE")) return const Color(0xFF0078D2);
    if (prog.contains("GOL")) return const Color(0xFFFF5C00);
    if (prog.contains("QATAR")) return const Color(0xFF860232);
    
    return const Color.fromARGB(255, 192, 190, 190); // Default
  }

  /// Retorna a Cor de Fundo (Usada apenas nos Cards da UI)
  static Color getFundo(String programa) {
    final String prog = programa.toUpperCase();
    if (prog.contains("AZUL")) return const Color(0xFF0C1927);
    if (prog.contains("LATAM")) return const Color(0xFF230D14);
    if (prog.contains("SMILES")) return const Color(0xFF22160A);
    if (prog.contains("TAP")) return const Color(0xFF0A1F1C);
    if (prog.contains("IBERIA") || prog.contains("IBÉRIA")) return const Color(0xFF1A0505);
    if (prog.contains("AADVANTAGE")) return const Color(0xFF0B172A);
    if (prog.contains("GOL")) return const Color(0xFF140800);
    if (prog.contains("QATAR")) return const Color(0xFF140108);
    
    return AppTheme.black; // Default
  }
}