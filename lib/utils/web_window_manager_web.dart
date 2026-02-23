import 'dart:html' as html;
import '../services/auth_service.dart';

/// Versão específica para Web do gerenciador de janelas.
///
/// Analogia: Similar a usar o `window.addEventListener('beforeunload', ...)` no JavaScript puro.
/// Ele detecta quando o usuário fecha a aba ou o navegador para encerrar a sessão.
void registerWebCloseListener() {
  // Escuta o evento de descarregamento da página (fechar aba/navegador)
  html.window.onBeforeUnload.listen((event) async {
    // Executa um logout sem aviso prévio para liberar o slot na planilha
    AuthService().logoutSilencioso(); 
  });
}
