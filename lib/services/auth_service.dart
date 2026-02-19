import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';

enum AuthStatus { autorizado, bloqueado, erroRede }

class AuthService {
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE";
  
  // Chaves da sessão ativa
  static const String _keyToken = "USER_TOKEN";
  static const String _keyEmail = "USER_EMAIL";
  static const String _keyUsuario = "USER_NAME";
  static const String _keyVencimento = "USER_VENCIMENTO";
  static const String _keyIdPlanilha = "USER_ID_PLANILHA";
  
  // Chaves de "Histórico" (Para manter os inputs preenchidos após deslogar)
  static const String _keyLastEmail = "LAST_LOGGED_EMAIL";
  static const String _keyLastToken = "LAST_LOGGED_TOKEN";
  
  final DiscoveryService _discovery = DiscoveryService();

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  Future<bool> isFirstUse() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) == null; // Se não tem token ativo, é "primeiro uso"
  }

  Future<void> salvarLoginLocal(String email, String token, String usuario, String vencimento, String idPlanilha) async {
    final prefs = await SharedPreferences.getInstance();
    // Salva sessão ativa
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsuario, usuario);
    await prefs.setString(_keyVencimento, vencimento);
    await prefs.setString(_keyIdPlanilha, idPlanilha);
    
    // Salva no histórico (memória do input)
    await prefs.setString(_keyLastEmail, email);
    await prefs.setString(_keyLastToken, token);
    
    await prefs.remove(_keyLastCheck); 
  }

  Future<Map<String, String>> getDadosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyEmail) ?? "N/A",
      "token": prefs.getString(_keyToken) ?? "N/A",
      "usuario": prefs.getString(_keyUsuario) ?? "N/A",
      "vencimento": prefs.getString(_keyVencimento) ?? "N/A",
      "idPlanilha": prefs.getString(_keyIdPlanilha) ?? "N/A",
    };
  }

  // 🚀 NOVO: Recupera o histórico para a tela de login
  Future<Map<String, String>> getLastLoginData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyLastEmail) ?? "",
      "token": prefs.getString(_keyLastToken) ?? "",
    };
  }

  Future<AuthStatus> validarAcessoDiario() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0]; 
    String? ultimaChecagem = prefs.getString(_keyLastCheck);

    if (ultimaChecagem == hoje) return AuthStatus.autorizado;
    await prefs.setString(_keyLastCheck, hoje);
    return AuthStatus.autorizado;
  }

  Future<Map<String, dynamic>> autenticarNoServidor(String email, String token) async {
    String? url = await _discovery.getConfig().then((c) => c?.gasUrl);
    if (url == null) return {"sucesso": false, "mensagem": "Falha de rede."};

    String deviceId = await getDeviceId();

    try {
      final response = await http.post(
        Uri.parse(url),
        body: jsonEncode({"action": "CHECK_DEVICE", "deviceId": deviceId, "token": token, "email": email}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          // Passando os novos dados retornados pela planilha
          await salvarLoginLocal(
            email, 
            token, 
            data['usuario'] ?? 'Desconhecido', 
            data['vencimento'] ?? 'N/A', 
            data['idPlanilha'] ?? 'N/A'
          );
          return {"sucesso": true, "mensagem": data['message']};
        } else {
          return {"sucesso": false, "mensagem": data['message']};
        }
      }
      return {"sucesso": false, "mensagem": "Erro (${response.statusCode})"};
    } catch (e) {
      return {"sucesso": false, "mensagem": "Servidor offline."};
    }
  }

Future<bool> logout() async {
    final prefs = await SharedPreferences.getInstance();
    String deviceId = await getDeviceId();

    // 1. Tenta avisar a planilha para liberar o Slot
    try {
      String? url = await _discovery.getConfig().then((c) => c?.gasUrl);
      if (url != null) {
        await http.post(
          Uri.parse(url),
          body: jsonEncode({"action": "REMOVE_DEVICE", "deviceId": deviceId}),
        ).timeout(const Duration(seconds: 10));
        print("🗑️ Aparelho removido da planilha com sucesso.");
      }
    } catch (e) {
      print("⚠️ Erro ao remover aparelho da planilha. Deslogando localmente...");
    }

    // 2. Limpa os dados da sessão localmente
    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuario);
    await prefs.remove(_keyVencimento);
    await prefs.remove(_keyIdPlanilha);
    await prefs.remove(_keyLastCheck); 

    return true;
  }
}