import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'config_service.dart';

enum AuthStatus { autorizado, bloqueado, erroRede }

class AuthService {
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE"; // Formato YYYY-MM-DD
  
  final ConfigService _config = ConfigService();

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  /// Verifica a licença respeitando a regra de cache diário
  Future<AuthStatus> validarAcessoDiario() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0]; // Ex: "2026-02-18"
    String? ultimaChecagem = prefs.getString(_keyLastCheck);

    // REGRA DE CACHE: Se já checou hoje, libera direto (Economia de Recurso)
    if (ultimaChecagem == hoje) {
      print("🔐 Licença já validada hoje ($hoje). Acesso cacheado.");
      return AuthStatus.autorizado;
    }

    // Se mudou o dia (ou nunca checou), vai para a internet
    return await _consultarServidor(hoje, prefs);
  }

  /// Força a validação no servidor (ignorando o cache)
  Future<AuthStatus> forcarValidacao() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0];
    return await _consultarServidor(hoje, prefs);
  }

  Future<AuthStatus> _consultarServidor(String hoje, SharedPreferences prefs) async {
    print("🌍 Consultando Servidor de Licenças...");
    
    // 1. Pega URL
    String? url = await _config.getCachedUrl();
    if (url == null) {
      url = await _config.atualizarDiscovery();
      if (url == null) return AuthStatus.erroRede;
    }

    // 2. Pega ID
    String deviceId = await getDeviceId();

    try {
      final response = await http.post(
        Uri.parse(url),
        body: jsonEncode({ // Enviando como JSON para garantir robustez
          "action": "CHECK_DEVICE",
          "deviceId": deviceId
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        
        if (body['status'] == 'success') {
          // SUCESSO: Salva a data de hoje para não perguntar mais
          await prefs.setString(_keyLastCheck, hoje);
          print("✅ Dispositivo Aprovado no Slot ${body['slot']}");
          return AuthStatus.autorizado;
        } else {
          // BLOQUEADO: Limpa o cache para obrigar nova checagem futura
          await prefs.remove(_keyLastCheck);
          print("⛔ Bloqueado: ${body['message']}");
          return AuthStatus.bloqueado;
        }
      }
    } catch (e) {
      print("Erro Licença: $e");
    }
    return AuthStatus.erroRede;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceId);
    await prefs.remove(_keyLastCheck); // Limpa o cache da licença também
  }
}