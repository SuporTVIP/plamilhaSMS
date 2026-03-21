// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'dart:convert';

/// Grava os filtros do usuário no IndexedDB para que o Service Worker
/// possa lê-los antes de exibir notificações.
///
/// Por que IndexedDB e não localStorage?
/// Service Workers NÃO têm acesso a localStorage — é bloqueado pela spec.
/// IndexedDB é o único storage síncrono/assíncrono acessível de ambos
/// (thread principal do Flutter Web e contexto isolado do SW).
void sincronizarFiltrosParaSW(Map<String, dynamic> filtros) {
  try {
    // Serializa os filtros para JSON antes de passar pro JS
    final String filtrosJson = jsonEncode(filtros).replaceAll("'", "\\'");

    // Executa JS inline para abrir o IndexedDB e salvar os filtros.
    // Usamos eval porque dart:js não expõe a API IndexedDB diretamente.
    js.context.callMethod('eval', ['''
      (function() {
        try {
          var req = indexedDB.open('PlamilhasDB', 1);
          req.onupgradeneeded = function(e) {
            var db = e.target.result;
            if (!db.objectStoreNames.contains('config')) {
              db.createObjectStore('config', { keyPath: 'key' });
            }
          };
          req.onsuccess = function(e) {
            var db = e.target.result;
            var tx = db.transaction('config', 'readwrite');
            tx.objectStore('config').put({ key: 'USER_FILTERS', value: $filtrosJson });
          };
        } catch(e) {
          console.warn('[PramilhasWeb] Erro ao salvar filtros no IndexedDB:', e);
        }
      })();
    ''']);

    print('✅ [WEB-FILTERS] Filtros sincronizados com o Service Worker via IndexedDB.');
  } catch (e) {
    print('⚠️ [WEB-FILTERS] Falha ao sincronizar filtros: $e');
  }
}