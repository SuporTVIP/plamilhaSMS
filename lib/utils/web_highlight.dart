// PONTE DE IMPORT CONDICIONAL
//
// main.dart importa ESTE arquivo — nunca dart:html diretamente.
// O compilador escolhe automaticamente qual implementação usar:
//   • Na web   → web_highlight_web.dart  (tem dart:html, usa postMessage e Uri.base)
//   • No mobile → web_highlight_stub.dart (no-op, sem dart:html)
//
// Analogia: É o mesmo padrão que o seu web_window_manager.dart já usa.

export 'web_highlight_stub.dart'
    if (dart.library.html) 'web_highlight_web.dart';
