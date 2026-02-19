import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';

enum AuthStatus { autorizado, bloqueado, erroRede }

class AuthService {
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE";
  static const String _keyToken = "USER_TOKEN";
  static const String _keyEmail = "USER_EMAIL";
  
  final DiscoveryService _discovery = DiscoveryService();

  // 1. Gera ou recupera o ID do aparelho
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  // 2. Verifica se é o Primeiro Uso (se não tem token salvo)
  Future<bool> isFirstUse() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) == null;
  }

  // 3. Salva os dados digitados na tela de Login Neon
  Future<void> salvarLoginLocal(String email, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyToken, token);
    // Limpa o cache de verificação diária para forçar validação no backend
    await prefs.remove(_keyLastCheck); 
  }

  // 4. Recupera os dados para mostrar no Dashboard
  Future<Map<String, String>> getDadosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyEmail) ?? "N/A",
      "token": prefs.getString(_keyToken) ?? "N/A",
    };
  }

  // 5. Validação Diária (Futuramente validará o Token com a Planilha)
  Future<AuthStatus> validarAcessoDiario() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0]; 
    String? ultimaChecagem = prefs.getString(_keyLastCheck);

    if (ultimaChecagem == hoje) return AuthStatus.autorizado;

    // MVP: Por enquanto, se tem token, deixa passar. 
    // No próximo passo, vamos integrar isso com a requisição do GAS.
    await prefs.setString(_keyLastCheck, hoje);
    return AuthStatus.autorizado;
  }

  // 6. Função de Sair (Logout)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Apaga apenas o login, mantém o DeviceID para a futura requisição de "liberar vaga"
    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyLastCheck); 
  }
}