import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
//import 'discovery_service.dart';

/// Define o status da tentativa de autenticação do dispositivo.
enum AuthStatus { autorizado, bloqueado, erroRede }

/// Serviço responsável por gerenciar a autenticação conectado ao WordPress!
class AuthService {
  // 🚀 A URL BASE DO SEU NOVO CÉREBRO (WordPress)
  static const String _wpBaseUrl =
      "https://pramilhas.suportvip.com/wp-json/pramilhas/v1";

  // Constantes de Chaves de Armazenamento Local
  static const String _keyDeviceId = "DEVICE_ID_V2";
  static const String _keyLastCheck = "LAST_LICENSE_CHECK_DATE";
  static const String _keyToken =
      "USER_TOKEN"; // Agora guarda a SENHA do WordPress
  static const String _keyEmail = "USER_EMAIL";
  static const String _keyUsuario = "USER_NAME";
  static const String _keyVencimento = "USER_VENCIMENTO";
  static const String _keyIdPlanilha = "USER_ID_PLANILHA";
  static const String _keyLastEmail = "LAST_LOGGED_EMAIL";
  static const String _keyLastToken = "LAST_LOGGED_TOKEN";
  //static const String _keyFcmTokenMobile = "FCM_TOKEN_MOBILE";
  static const String _keyFcmTokenWeb = "FCM_TOKEN_WEB";

  //final DiscoveryService _discovery = DiscoveryService();

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

  Future<bool> isFirstUse() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) == null;
  }

  Future<void> salvarLoginLocal(
    String email,
    String token,
    String usuario,
    String vencimento,
    String idPlanilha,
  ) async {
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

  Future<Map<String, String>> getLastLoginData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return {
      "email": prefs.getString(_keyLastEmail) ?? "",
      "token": prefs.getString(_keyLastToken) ?? "",
    };
  }

  Future<AuthStatus> validarAcessoDiario() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(_keyEmail);
    final String? token = prefs.getString(
      _keyToken,
    ); // No WP, o token é a senha

    if (email == null || token == null) {
      return AuthStatus.bloqueado;
    }

    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: false,
      isBackground: true,
    );

    if (resultado["sucesso"] == true) {
      return AuthStatus.autorizado;
    } else if (resultado["mensagem"] ==
        "Servidor offline ou bloqueio de rede.") {
      _debugLog("🌐 [AUTH] Sem internet. Confiando no passe livre temporário.");
      return AuthStatus.autorizado;
    } else {
      _debugLog(
        "⛔ [AUTH] Servidor WP negou o acesso: ${resultado["mensagem"]}",
      );
      return AuthStatus.bloqueado;
    }
  }

  /// 🚀 NOVO MOTOR: Bate na API do WordPress em vez do GAS!
  Future<Map<String, dynamic>> autenticarNoServidor(
    String email,
    String senha, {
    bool incluirTokensPush = true,
    bool isBackground = false,
  }) async {
    final String deviceId = await getDeviceId();
    final String plataforma = kIsWeb ? "web" : "mobile";

    // Prepara os dados pro formato que o nosso Snippet PHP espera
    final Map<String, dynamic> payload = {
      "email": email,
      "senha": senha,
      "device_id": deviceId,
      "plataforma": plataforma,
      "is_background": isBackground,
    };

    // 🚀 CORREÇÃO CIRÚRGICA: Separa a lógica de Web e Mobile
    if (incluirTokensPush) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      if (kIsWeb) {
        // Na Web, o token é gerado pelo index.html/push_service e salvo no cache.
        payload["fcm_token_web"] = prefs.getString(_keyFcmTokenWeb) ?? "";
        payload["fcm_token_mobile"] = "";
      } else {
        // No celular, pede na hora pro SDK
        payload["fcm_token_web"] = "";
        payload["fcm_token_mobile"] = await _obterFcmToken();
      }
    }

    // 🕵️‍♂️ O RASTREADOR: Vai imprimir no console exatamente o que está indo pro WP!
    _debugLog("🚀 PAYLOAD ENVIADO PARA O WP: $payload");

    try {
      final String bodyData = jsonEncode(payload);

      final response = await http
          .post(
            Uri.parse("$_wpBaseUrl/login"),
            headers: {'Content-Type': 'application/json'},
            body: bodyData,
          )
          .timeout(const Duration(seconds: 15));

      try {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (response.statusCode == 200 && data['sucesso'] == true) {
          final dados = data['dados'];
          await salvarLoginLocal(
            dados['email'],
            senha,
            dados['usuario'] ?? 'Cliente VIP',
            dados['vencimento'] ?? 'Vitalício',
            dados['idPlanilha'] ?? 'N/A',
          );
          return {"sucesso": true, "mensagem": data['mensagem']};
        } else {
          return {
            "sucesso": false,
            "mensagem": data['mensagem'] ?? "Acesso negado.",
          };
        }
      } catch (e) {
        _debugLog("⚠️ Resposta inesperada do WordPress: ${response.body}");
        return {"sucesso": false, "mensagem": "Erro de protocolo do servidor."};
      }
    } catch (e) {
      _debugLog("❌ Erro Auth (Rede): $e");
      return {
        "sucesso": false,
        "mensagem": "Servidor offline ou bloqueio de rede.",
      };
    }
  }

  Future<bool> sincronizarTokenPushWebAutorizado() async {
    if (!kIsWeb) return true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(_keyEmail);
    final String? token = prefs.getString(_keyToken);

    if (email == null || token == null) return false;

    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: true,
      isBackground: true,
    );
    return resultado["sucesso"] == true;
  }

  Future<bool> sincronizarTokenPushAutorizadoAtual() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(_keyEmail);
    final String? token = prefs.getString(_keyToken);

    if (email == null || token == null) return false;

    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: true,
      isBackground: true,
    );
    return resultado["sucesso"] == true;
  }

  Future<bool> sincronizarTokenPushAutorizado() async {
    return sincronizarTokenPushAutorizadoAtual();
  }

  /// 🚀 NOVO LOGOUT: Bate na rota /logout do WordPress para liberar a vaga!
  Future<bool> logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = await getDeviceId();
    final String? email = prefs.getString(_keyEmail);

    if (email != null) {
      try {
        final String bodyData = jsonEncode({
          "email": email,
          "device_id": deviceId,
        });

        await http
            .post(
              Uri.parse("$_wpBaseUrl/logout"),
              headers: {'Content-Type': 'application/json'},
              body: bodyData,
            )
            .timeout(const Duration(seconds: 10));

        _debugLog("🚪 [WP] Vaga liberada no WordPress com sucesso!");
      } catch (e) {
        _debugLog("⚠️ Erro ao remover aparelho do WordPress: $e");
      }
    }

    // 🧹 Limpeza total de credenciais e cache local
    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuario);
    await prefs.remove(_keyVencimento);
    await prefs.remove(_keyIdPlanilha);
    await prefs.remove(_keyLastCheck);
    await prefs.remove('ALERTS_CACHE_V2');
    await prefs.remove('CACHE_DATE_V2');

    _debugLog(
      "🗑️ [AUTH] Cache de alertas e credenciais destruídos com sucesso.",
    );
    return true;
  }

  Future<void> logoutSilencioso() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = await getDeviceId();
    final String? email = prefs.getString(_keyEmail);

    if (email != null) {
      try {
        http.post(
          Uri.parse("$_wpBaseUrl/logout"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({"email": email, "device_id": deviceId}),
        );
        _debugLog("🌐 Sessão encerrada de forma silenciosa no WordPress.");
      } catch (e) {
        _debugLog("⚠️ Falha ao deslogar silenciosamente: $e");
      }
    }
  }

  Future<String> _obterFcmToken() async {
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final String? fcmToken = await messaging.getToken();
      return fcmToken ?? "";
    } catch (e) {
      return "";
    }
  }

  void _debugLog(String message) {
    // ignore: avoid_print
    print(message);
  }
}
