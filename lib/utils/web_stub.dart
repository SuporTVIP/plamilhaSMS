import 'dart:async';

/// 🛡️ O "Dublê" do navegador para o Android.
/// Ele imita toda a estrutura do navegador para o compilador mobile não reclamar.
class WindowStub {
  // Simula html.window.onMessage
  Stream<dynamic> get onMessage => const Stream.empty();
  
  // 🚀 Simula html.window.navigator
  NavigatorStub get navigator => NavigatorStub();
}

class NavigatorStub {
  // 🚀 Simula html.window.navigator.serviceWorker
  ServiceWorkerContainerStub get serviceWorker => ServiceWorkerContainerStub();
}

class ServiceWorkerContainerStub {
  // 🚀 Simula html.window.navigator.serviceWorker.onMessage
  Stream<dynamic> get onMessage => const Stream.empty();
}

// 🚀 Fornece a instância global 'window' para o código html.window no Android [cite: 5]
WindowStub get window => WindowStub();