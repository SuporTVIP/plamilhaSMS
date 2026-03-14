import 'dart:html' as html;
import 'dart:js' as js;
import 'package:shared_preferences/shared_preferences.dart';

/// Versão Web — usa sendBeacon para garantir o logout ao fechar a aba.
///
/// Por que sendBeacon e não http.post?
/// O navegador cancela Futures async no beforeUnload antes delas resolverem.
/// sendBeacon é a única API garantida de completar mesmo durante o fechamento.
void registerWebCloseListener() {
  html.window.onBeforeUnload.listen((_) async {
    try {
      // Lê a URL do GAS e o token do storage local (operações síncronas no cache)
      final prefs = await SharedPreferences.getInstance();
      final String gasUrl  = prefs.getString('GAS_URL')   ?? '';
      final String token   = prefs.getString('USER_TOKEN') ?? '';
      final String device  = prefs.getString('DEVICE_ID')  ?? '';

      if (gasUrl.isEmpty || token.isEmpty) return;

      // Monta a URL de logout com query params (sendBeacon não suporta body em GET,
      // mas o GAS aceita GET action=LOGOUT)
      final uri = Uri.parse(gasUrl).replace(queryParameters: {
        'action': 'LOGOUT',
        'token':  token,
        'device': device,
      });

      // sendBeacon: fire-and-forget garantido pelo navegador no unload
      // Retorna bool (true = enfileirado com sucesso), não um Future
      final bool enviado = js.context.callMethod(
        'eval',
        ['navigator.sendBeacon("${uri.toString()}")'],
      ) as bool? ?? false;

      if (!enviado) {
        // Fallback: se sendBeacon falhar (ex: tamanho > 64KB), tenta XHR síncrono
        // XHR síncrono é depreciado mas ainda funciona no beforeUnload
        js.context.callMethod('eval', [
          'var x = new XMLHttpRequest();'
          'x.open("GET","${uri.toString()}",false);'
          'x.send();'
        ]);
      }
    } catch (e) {
      // Silencia — não podemos logar no console durante o unload
    }
  });
}
