// IMPLEMENTAÇÃO WEB — usa dart:html que só existe na plataforma web.
// Importado via import condicional em web_highlight.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void iniciarReceptorWebHighlight(void Function(String trecho) onHighlight) {
  // ── Warm start: aba já estava aberta, SW mandou postMessage ──────────
  // O service worker chama client.postMessage({type: 'PLAMILHAS_HIGHLIGHT', trecho: '...'})
  // quando o usuário clica na notificação do sistema com a aba já aberta.
  html.window.onMessage.listen((html.MessageEvent event) {
    try {
      final data = event.data;
      if (data == null) return;

      // dart:html retorna JsObject — convertemos para Map via JS interop
      final type   = _jsGet(data, 'type')   as String?;
      final trecho = _jsGet(data, 'trecho') as String?;

      if (type == 'PLAMILHAS_HIGHLIGHT' && trecho != null && trecho.isNotEmpty) {
        print("✨ [WEB-SW] postMessage recebido: $trecho");
        onHighlight(trecho);
      }
    } catch (e) {
      print("⚠️ [WEB-SW] Erro ao processar postMessage: $e");
    }
  });

  // ── Cold start: app abriu via clique, trecho veio como query param ────
  // O service worker faz openWindow('/?highlight=TRECHO') quando nenhuma
  // aba estava aberta. Aqui lemos e removemos o param da URL.
  final uri    = Uri.base;
  final trecho = uri.queryParameters['highlight'] ?? '';
  if (trecho.isNotEmpty) {
    print("✨ [WEB-URL] Highlight via query param: $trecho");
    onHighlight(trecho);

    // Limpa o ?highlight= da barra de endereço sem recarregar a página
    final urlLimpa = uri.removeFragment().replace(queryParameters: {}).toString();
    html.window.history.replaceState(null, '', urlLimpa);
  }
}

// Helper: lê uma propriedade de um JsObject sem quebrar no Dart sound null-safety
dynamic _jsGet(dynamic obj, String key) {
  try {
    return (obj as dynamic)[key];
  } catch (_) {
    return null;
  }
}
