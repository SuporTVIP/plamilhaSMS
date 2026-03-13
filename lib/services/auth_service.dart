import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';

/// Define o status da tentativa de autenticação do dispositivo.
enum AuthStatus {
  /// O dispositivo possui uma licença válida e ativa.
  autorizado,
  /// A licença está vencida ou o dispositivo foi bloqueado.
  bloqueado,
  /// Não foi possível verificar o status devido a falhas de rede.
  erroRede
}

/// Serviço responsável por gerenciar a autenticação, licenças e identificação do dispositivo.
class AuthService {
  // Constantes de Chaves de Armazenamento Local
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE";
  static const String _keyToken = "USER_TOKEN";
  static const String _keyEmail = "USER_EMAIL";
  static const String _keyUsuario = "USER_NAME";
  static const String _keyVencimento = "USER_VENCIMENTO";
  static const String _keyIdPlanilha = "USER_ID_PLANILHA";
  static const String _keyLastEmail = "LAST_LOGGED_EMAIL";
  static const String _keyLastToken = "LAST_LOGGED_TOKEN";

  // Dependências
  final DiscoveryService _discovery = DiscoveryService();

  /// Obtém o ID único do dispositivo, gerando um novo se necessário.
  ///
  /// O prefixo 'WEB_' ou 'APP_' é utilizado para distinguir o ambiente de execução.
  Future<String> getDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? currentId = prefs.getString(_keyDeviceId);

    if (currentId == null) {
      final String prefix = kIsWeb ? "WEB_" : "APP_";
      currentId = "$prefix${const Uuid().v4()}";
      await prefs.setString(_keyDeviceId, currentId);
    }

    return currentId;
  }

  /// Verifica se é a primeira vez que o aplicativo é utilizado (ausência de token).
  Future<bool> isFirstUse() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) == null;
  }

  /// Persiste as informações do usuário logado localmente.
  Future<void> salvarLoginLocal(String email, String token, String usuario, String vencimento, String idPlanilha) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsuario, usuario);
    await prefs.setString(_keyVencimento, vencimento);
    await prefs.setString(_keyIdPlanilha, idPlanilha);
    await prefs.setString(_keyLastEmail, email);
    await prefs.setString(_keyLastToken, token);
    await prefs.remove(_keyLastCheck);
  }

  /// Retorna os dados do usuário autenticado salvos no dispositivo.
  Future<Map<String, String>> getDadosUsuario() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyEmail) ?? "N/A",
      "token": prefs.getString(_keyToken) ?? "N/A",
      "usuario": prefs.getString(_keyUsuario) ?? "N/A",
      "vencimento": prefs.getString(_keyVencimento) ?? "N/A",
      "idPlanilha": prefs.getString(_keyIdPlanilha) ?? "N/A",
    };
  }

  /// Retorna as últimas credenciais utilizadas para facilitar o login.
  Future<Map<String, String>> getLastLoginData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyLastEmail) ?? "",
      "token": prefs.getString(_keyLastToken) ?? "",
    };
  }

  /// Realiza uma verificação local rápida para autorização diária sem chamada de rede obrigatória.
  Future<AuthStatus> validarAcessoDiario() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String hoje = DateTime.now().toIso8601String().split('T')[0];
    final String? ultimaChecagem = prefs.getString(_keyLastCheck);

    if (ultimaChecagem == hoje) return AuthStatus.autorizado;
    await prefs.setString(_keyLastCheck, hoje);
    return AuthStatus.autorizado;
  }

  /// Autentica o usuário junto ao servidor principal (GAS).
  ///
  /// Realiza o envio do e-mail, token, ID do dispositivo e token FCM para notificações.
  /// Trata redirecionamentos 302 em ambientes nativos.
  Future<Map<String, dynamic>> autenticarNoServidor(String email, String token) async {
    final DiscoveryConfig? config = await _discovery.getConfig();
    final String? serverUrl = config?.gasUrl;
    
    if (serverUrl == null) {
      return {"sucesso": false, "mensagem": "Falha de rede ao descobrir servidor."};
    }

    final String deviceId = await getDeviceId();
    final String fcmToken = await _obterFcmToken();

    // 🚀 LENDO O TOKEN DA WEB (Que foi salvo no main.dart)
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String fcmTokenWeb = prefs.getString('FCM_TOKEN_WEB') ?? "";

    final Map<String, dynamic> payload = {
      "action": "CHECK_DEVICE",
      "email": email,
      "deviceId": deviceId,
      "fcmToken": fcmToken,
      "token": token,
      "fcmTokenWeb": fcmTokenWeb, // 🚀 Enviando o token web para o servidor
    };

    try {
      final String bodyData = jsonEncode(payload);
      http.Response response;

      if (kIsWeb) {
        // No Navegador, o CORS nativo gerencia redirecionamentos
        response = await http.post(Uri.parse(serverUrl), body: bodyData).timeout(const Duration(seconds: 15));
      } else {
        // No Android/iOS, precisamos seguir o redirecionamento 302 manualmente
        final request = http.Request('POST', Uri.parse(serverUrl))
          ..followRedirects = false
          ..body = bodyData;

        final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
        response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 302 || response.statusCode == 303) {
          final String? redirectUrl = response.headers['location'];
          if (redirectUrl != null) {
            response = await http.get(Uri.parse(redirectUrl)).timeout(const Duration(seconds: 15));
          }
        }
      }

      if (response.statusCode == 200) {
        if (response.body.trim().startsWith('{')) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          if (data['status'] == 'success') {
            await salvarLoginLocal(
              email,
              token,
              data['usuario'] ?? 'Desconhecido',
              data['vencimento'] ?? 'N/A',
              data['idPlanilha'] ?? 'N/A',
            );
            return {"sucesso": true, "mensagem": data['message']};
          } else {
            return {"sucesso": false, "mensagem": data['message']};
          }
        } else {
          print("⚠️ Resposta inesperada: ${response.body}");
          return {"sucesso": false, "mensagem": "Erro de protocolo do servidor."};
        }
      }
      return {"sucesso": false, "mensagem": "Erro HTTP (${response.statusCode})"};
    } catch (e) {
      print("❌ Erro Auth: $e");
      return {"sucesso": false, "mensagem": "Servidor offline ou bloqueio de rede."};
    }
  }

  /// Remove o acesso do dispositivo localmente e tenta notificar o servidor (fire-and-forget).
  Future<bool> logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = await getDeviceId();

    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      final String? serverUrl = config?.gasUrl;

      if (serverUrl != null) {
        final String bodyData = jsonEncode({"action": "REMOVE_DEVICE", "deviceId": deviceId});
        
        if (kIsWeb) {
          await http.post(Uri.parse(serverUrl), body: bodyData).timeout(const Duration(seconds: 10));
        } else {
          final request = http.Request('POST', Uri.parse(serverUrl))
            ..followRedirects = false
            ..body = bodyData;
          await request.send().timeout(const Duration(seconds: 10));
        }
      }
    } catch (e) {
      print("⚠️ Erro ao remover aparelho do servidor: $e");
    }

    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuario);
    await prefs.remove(_keyVencimento);
    await prefs.remove(_keyIdPlanilha);
    await prefs.remove(_keyLastCheck);

    return true;
  }

  /// Notifica o servidor sobre o encerramento da sessão sem aguardar resposta.
  Future<void> logoutSilencioso() async {
    final String deviceId = await getDeviceId();
    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      final String? serverUrl = config?.gasUrl;

      if (serverUrl != null) {
        final String bodyData = jsonEncode({"action": "REMOVE_DEVICE", "deviceId": deviceId});

        if (kIsWeb) {
          http.post(Uri.parse(serverUrl), body: bodyData);
        } else {
          final request = http.Request('POST', Uri.parse(serverUrl))
            ..followRedirects = false
            ..body = bodyData;
          request.send();
        }
        print("🌐 Sessão encerrada de forma silenciosa.");
      }
    } catch (e) {
      print("⚠️ Falha ao deslogar silenciosamente: $e");
    }
  }

  /// Captura o token de notificações push (FCM).
  Future<String> _obterFcmToken() async {
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final String? fcmToken = await messaging.getToken();
      print("🔑 FCM Token Capturado: $fcmToken");
      return fcmToken ?? "";
    } catch (e) {
      print("❌ Erro ao capturar FCM Token: $e");
      return "";
    }
  }
}
