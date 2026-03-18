// ignore_for_file: camel_case_types

/// Este arquivo é um substituto (stub) para o dart:html.
/// Ele permite que o código mobile compile sem erro, fingindo que 
/// as funcionalidades de janela do navegador existem.
class window {
  static _Window get windowInstance => _Window();
  
  // Simula o html.window.onMessage
  static Stream<dynamic> get onMessage => const Stream.empty();
}

class _Window {
  // Caso você precise de mais métodos do window no futuro, adicione aqui
  Stream<dynamic> get onMessage => const Stream.empty();
}