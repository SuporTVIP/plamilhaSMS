import 'dart:async';

/// 🛡️ O "Dublê" do navegador para o Android.
/// Ele finge que existe uma janela e um onMessage, mas não faz nada.
class WindowStub {
  // Simula o onMessage do navegador para não dar erro de compilação
  Stream<dynamic> get onMessage => const Stream.empty();
}

// 🚀 O PULO DO GATO: Criamos uma variável global chamada 'window'
// para que o código 'html.window.onMessage' funcione no Android.
WindowStub get window => WindowStub();