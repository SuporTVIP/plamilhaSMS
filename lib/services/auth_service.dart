import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';


enum AuthStatus { autorizado, bloqueado, erroRede }

class AuthService {
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE";
  static const String _keyToken = "USER_TOKEN";
  static const String _keyEmail = "USER_EMAIL";
  static const String _keyUsuario = "USER_NAME";
  static const String _keyVencimento = "USER_VENCIMENTO";
  static const String _keyIdPlanilha = "USER_ID_PLANILHA";
  static const String _keyLastEmail = "LAST_LOGGED_EMAIL";
  static const String _keyLastToken = "LAST_LOGGED_TOKEN";
  
  final DiscoveryService _discovery = DiscoveryService();

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyDeviceId);
    if (id == null) {
      String prefixo = kIsWeb ? "WEB_" : "APP_";
      id = "$prefixo${const Uuid().v4()}"; 
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  Future<bool> isFirstUse() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) == null;
  }

  Future<void> salvarLoginLocal(String email, String token, String usuario, String vencimento, String idPlanilha) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsuario, usuario);
    await prefs.setString(_keyVencimento, vencimento);
    await prefs.setString(_keyIdPlanilha, idPlanilha);
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

 Future<String> _obterFcmToken() async {
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    // Solicita permissão (necessário para iOS e Android 13+)
    await messaging.requestPermission();
    
    String? token = await messaging.getToken();
    print("🔑 FCM Token Capturado: $token");
    return token ?? "";
  } catch (e) {
    print("❌ Erro ao capturar FCM Token: $e");
    return "";
  }
}

Future<Map<String, dynamic>> autenticarNoServidor(String email, String token) async {
    String? url = await _discovery.getConfig().then((c) => c?.gasUrl);
    if (url == null) return {"sucesso": false, "mensagem": "Falha de rede."};

    String deviceId = await getDeviceId();
    // obtain FCM token so server can send push notifications to this device
    String fcmToken = await _obterFcmToken(); // 🚀 Pega o token antes de enviar

    final Map<String, dynamic> payload = {
    "action": "CHECK_DEVICE",
    "email": email,
    "deviceId": deviceId,
    "fcmToken": fcmToken,
    "token": token,
    };

    String bodyData = jsonEncode(payload);

    try {
      http.Response response;

      if (kIsWeb) {
        // 🚀 NO NAVEGADOR: O Chrome lida com o 302 sozinho (CORS nativo)
        response = await http.post(Uri.parse(url), body: bodyData).timeout(const Duration(seconds: 15));
      } else {
        // 🚀 NO CELULAR: O Android precisa pegar na mão e seguir o 302
        final request = http.Request('POST', Uri.parse(url))
          ..followRedirects = false 
          ..body = bodyData;

        final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
        response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 302 || response.statusCode == 303) {
          final redirectUrl = response.headers['location'];
          if (redirectUrl != null) {
            response = await http.get(Uri.parse(redirectUrl)).timeout(const Duration(seconds: 15));
          }
        }
      }

      if (response.statusCode == 200) {
        // Trava para garantir que não vamos tentar ler o texto de "Sistema Operante" como JSON
        if (response.body.trim().startsWith('{')) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'success') {
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
        } else {
          print("⚠️ Resposta inesperada do servidor: ${response.body}");
          return {"sucesso": false, "mensagem": "Erro de comunicação com o servidor."};
        }
      }
      return {"sucesso": false, "mensagem": "Erro (${response.statusCode})"};
    } catch (e) {
      print("Erro Auth: $e");
      return {"sucesso": false, "mensagem": "Servidor offline ou bloqueio de rede."};
    }
  }

  Future<void> logoutSilencioso() async {
    String deviceId = await getDeviceId();
    try {
      String? url = await _discovery.getConfig().then((c) => c?.gasUrl);
      if (url != null) {
        String bodyData = jsonEncode({"action": "REMOVE_DEVICE", "deviceId": deviceId});
        
        if (kIsWeb) {
          http.post(Uri.parse(url), body: bodyData); // Fire and forget no navegador
        } else {
          final request = http.Request('POST', Uri.parse(url))
            ..followRedirects = false
            ..body = bodyData;
          request.send(); // Fire and forget no nativo
        }
        print("🌐 Sessão encerrada na planilha.");
      }
    } catch (e) {}
  }

  Future<bool> logout() async {
    final prefs = await SharedPreferences.getInstance();
    String deviceId = await getDeviceId();

    try {
      String? url = await _discovery.getConfig().then((c) => c?.gasUrl);
      if (url != null) {
        String bodyData = jsonEncode({"action": "REMOVE_DEVICE", "deviceId": deviceId});
        
        if (kIsWeb) {
          await http.post(Uri.parse(url), body: bodyData).timeout(const Duration(seconds: 10));
        } else {
          final request = http.Request('POST', Uri.parse(url))
            ..followRedirects = false
            ..body = bodyData;
          await request.send().timeout(const Duration(seconds: 10));
        }
      }
    } catch (e) {
      print("⚠️ Erro ao remover aparelho. Deslogando localmente...");
    }

    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuario);
    await prefs.remove(_keyVencimento);
    await prefs.remove(_keyIdPlanilha);
    await prefs.remove(_keyLastCheck); 

    return true;
  }
}