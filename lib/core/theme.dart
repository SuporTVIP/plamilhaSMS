import 'package:flutter/material.dart';

class AppTheme {
  // ===========================================================================
  // 1. CORES PRINCIPAIS (IDENTIDADE DA MARCA)
  // ===========================================================================

  /// Roxo Elétrico (#6A00FF) - Cor principal, botões, ícones ativos
  static const Color accent = Color(0xFF6A00FF);

  /// Roxo Brilhante (#8B2FF7) - Fim do gradiente, detalhes luminosos
  static const Color brightPurple = Color(0xFF8B2FF7);

  /// Lilás Pastel (#E8E0FF) - Bordas, trilhas e botões secundários
  static const Color lightPurple = Color(0xFFE8E0FF);

  /// Lilás Super Claro (#F3E8FF) - Fundo de ícones em repouso
  static const Color palePurple = Color(0xFFF3E8FF);

  // ===========================================================================
  // 2. CORES DE FUNDO (BACKGROUNDS - LIGHT MODE)
  // ===========================================================================

  /// Branco Gelo com toque Roxo (#F8F5FF) - Fundo geral do App (Body)
  static const Color bg = Color(0xFFF8F5FF);

  /// Branco Puro (#FFFFFF) - Fundo dos Cards, Painéis e Inputs
  static const Color card = Color(0xFFFFFFFF);
  static const Color surface = Color(
    0xFFFFFFFF,
  ); // Mesma coisa que card no Light Theme

  /// Lilás Pastel (#E8E0FF) - Usado para bordas e separadores limpos
  static const Color border = Color(0xFFE8E0FF);

  // ===========================================================================
  // 3. CORES DE TEXTO (TIPOGRAFIA)
  // ===========================================================================

  /// Preto Absoluto (#000000) - Títulos Fortes (H1, H2)
  static const Color black = Color(0xFF000000);

  /// Cinza Muito Escuro (#333333) - Texto principal (Body)
  static const Color text = Color(0xFF333333);

  /// Cinza Médio (#666666) - Subtítulos e explicações
  static const Color muted = Color(0xFF666666);

  // ===========================================================================
  // 4. CORES UTILITÁRIAS / SUPORTE
  // ===========================================================================

  /// Verde Esmeralda (#10B981) - Sucesso, Liberado, Ativo
  static const Color green = Color(0xFF10B981);
  static const Color esmerald = Color(0xFF10B981); // Alias

  /// Vermelho Suave (#EF4444) - Alertas, Erros, Bloqueado (Manteve padrão Flutter)
  static const Color red = Color(0xFFEF4444);

  /// Amarelo Ouro (#F59E0B) - Alertas Médios, Pendentes
  static const Color yellow = Color(0xFFF59E0B);
  static const Color golden = Color(0xFFF59E0B); // Alias
  static const Color amber = Color(0xFFF59E0B); // Alias

  // ===========================================================================
  // 5. GRADIENTE OFICIAL DA MARCA
  // ===========================================================================

  /// "background: linear-gradient(135deg, #6a00ff 0%, #8b2ff7 100%);"
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accent, brightPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
