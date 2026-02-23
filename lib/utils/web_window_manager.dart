/// Este arquivo utiliza uma funcionalidade avançada do Dart chamada "Conditional Export".
///
/// Analogia: É como um `#if` no C++ ou C#, ou verificar o `process.platform` no Node.js.
/// Ele decide qual arquivo exportar baseado na plataforma onde o código está rodando.
export 'web_window_manager_stub.dart'
    if (dart.library.html) 'web_window_manager_web.dart';
