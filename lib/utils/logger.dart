import 'package:flutter/foundation.dart';

/// Utilitário centralizado para logging do sistema.
class AppLogger {
  /// Controla se as mensagens de log devem ser exibidas no terminal.
  ///
  /// 🚀 A CHAVE MESTRA: Mude para 'false' para silenciar o app todo no terminal.
  static const bool isDebug = true;

  /// Registra uma mensagem informativa no log.
  static void log(String message) {
    if (isDebug && kDebugMode) {
      // ignore: avoid_print
      print("🚀 [LOG]: $message");
    }
  }

  /// Registra uma mensagem de erro no log.
  static void error(String message, [dynamic error]) {
    if (isDebug) {
      // ignore: avoid_print
      print("❌ [ERRO]: $message ${error ?? ''}");
    }
  }
}
