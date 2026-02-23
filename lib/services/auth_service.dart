import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Define os possíveis estados de autorização do usuário.
enum AuthStatus { autorizado, bloqueado, erroRede }

/// Serviço responsável pelo gerenciamento de identidade, login e licenciamento.
///
/// Este serviço lida com a persistência de dados sensíveis e a comunicação
/// de segurança com o servidor/planilha.
class AuthService {
  // Chaves para o SharedPreferences (Analogia: Nomes das chaves no localStorage do JS)
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE";
  
  // Chaves da sessão ativa
  static const String _keyToken = "USER_TOKEN";
  static const String _keyEmail = "USER_EMAIL";
  static const String _keyUsuario = "USER_NAME";
  static const String _keyVencimento = "USER_VENCIMENTO";
  static const String _keyIdPlanilha = "USER_ID_PLANILHA";
  
  // Chaves de "Histórico" (Para preencher os campos automaticamente no próximo login)
  static const String _keyLastEmail = "LAST_LOGGED_EMAIL";
  static const String _keyLastToken = "LAST_LOGGED_TOKEN";
  
  final DiscoveryService _discovery = DiscoveryService();

  /// Recupera ou gera um Identificador Único para o aparelho.
  ///
  /// Analogia: Funciona como um "Fingerprint" do navegador ou um ID de hardware em C#.
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyDeviceId);
    
    if (id == null) {
      // 🚀 ASSINATURA DE PLATAFORMA: Identifica se o acesso vem da Web ou do App nativo.
      String prefixo = kIsWeb ? "WEB_" : "APP_";
      id = "$prefixo${const Uuid().v4()}"; 
      
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  /// Verifica se é a primeira vez que o usuário abre o app (ou se está deslogado).
  Future<bool> isFirstUse() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) == null;
  }

  /// Salva as informações do usuário no armazenamento local.
  ///
  /// Analogia: Similar a gravar um dicionário Python em um arquivo `.json`
  /// ou usar o `localStorage.setItem()` no JavaScript.
  Future<void> salvarLoginLocal(String email, String token, String usuario, String vencimento, String idPlanilha) async {
    final prefs = await SharedPreferences.getInstance();
    // Salva sessão ativa
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsuario, usuario);
    await prefs.setString(_keyVencimento, vencimento);
    await prefs.setString(_keyIdPlanilha, idPlanilha);
    
    // Salva no histórico para facilitar o próximo login do usuário
    await prefs.setString(_keyLastEmail, email);
    await prefs.setString(_keyLastToken, token);
    
    await prefs.remove(_keyLastCheck); 
  }

  /// Recupera os dados do usuário logado.
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

  /// Recupera o histórico de e-mail e token para a tela de login.
  Future<Map<String, String>> getLastLoginData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyLastEmail) ?? "",
      "token": prefs.getString(_keyLastToken) ?? "",
    };
  }

  /// Valida se o acesso ainda está autorizado para o dia de hoje.
  Future<AuthStatus> validarAcessoDiario() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0]; 
    String? ultimaChecagem = prefs.getString(_keyLastCheck);

    if (ultimaChecagem == hoje) return AuthStatus.autorizado;
    await prefs.setString(_keyLastCheck, hoje);
    return AuthStatus.autorizado;
  }

  /// Tenta autenticar o usuário enviando o e-mail, token e ID do dispositivo para o servidor.
  ///
  /// Analogia: Realiza um `POST` para a API, similar ao que fazemos com `axios.post()` no JS
  /// ou `requests.post()` no Python.
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
          // Atualiza os dados locais com a resposta de sucesso do servidor
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

  /// Encerra a sessão no servidor sem limpar os dados locais do usuário.
  /// Utilizado principalmente na Web ao fechar a aba.
  Future<void> logoutSilencioso() async {
    String deviceId = await getDeviceId();
    try {
      String? url = await _discovery.getConfig().then((c) => c?.gasUrl);
      if (url != null) {
        // Envia a requisição de remoção sem esperar resposta (fire and forget)
        http.post(
          Uri.parse(url),
          body: jsonEncode({"action": "REMOVE_DEVICE", "deviceId": deviceId}),
        );
        print("🌐 Sessão Web encerrada na planilha.");
      }
    } catch (e) {
      print("Erro no logout silencioso: $e");
    }
  }

  /// Realiza o logout completo, avisando o servidor e limpando a sessão local.
  Future<bool> logout() async {
    final prefs = await SharedPreferences.getInstance();
    String deviceId = await getDeviceId();

    // 1. Tenta avisar a planilha para liberar o "Slot" de conexão deste aparelho
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

    // 2. Limpa os dados da sessão localmente (Analogia: `localStorage.clear()`)
    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuario);
    await prefs.remove(_keyVencimento);
    await prefs.remove(_keyIdPlanilha);
    await prefs.remove(_keyLastCheck); 

    return true;
  }
}
