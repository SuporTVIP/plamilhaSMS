import 'package:flutter/foundation.dart';

class AppLogger {
  // 🚀 A CHAVE MESTRA: Mude para 'false' para silenciar o app todo no terminal
  static const bool isDebug = false;

  static void log(String message) {
    if (isDebug && kDebugMode) {
      print("🚀 [LOG]: $message");
    }
  }

  static void error(String message, [dynamic error]) {
    if (isDebug) {
      print("❌ [ERRO]: $message ${error ?? ''}");
    }
  }
}