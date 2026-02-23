import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milhas_alert/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Constrói o aplicativo e dispara um frame.
    // Analogia: Similar a montar um componente no Jest/Testing Library.
    await tester.pumpWidget(const MilhasAlertApp());

    // Verifica se a tela inicial (SplashRouter) exibe o indicador de carregamento.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
