/// Ponte de import condicional para sincronização de filtros com o Service Worker.
///
/// Mesmo padrão dos outros utils do projeto.
/// Web   → web_filters_sync_web.dart  (escreve em IndexedDB via JS)
/// Mobile → web_filters_sync_stub.dart (no-op)
export 'web_filters_sync_stub.dart'
    if (dart.library.html) 'web_filters_sync_web.dart';