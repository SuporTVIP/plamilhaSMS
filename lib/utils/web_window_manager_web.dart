import 'dart:html' as html;
import '../services/auth_service.dart';

void registerWebCloseListener() {
  html.window.onBeforeUnload.listen((event) async {
    AuthService().logoutSilencioso(); 
  });
}