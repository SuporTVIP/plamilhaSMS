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
  erroRede,
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
  static const String _keyFcmTokenMobile = "FCM_TOKEN_MOBILE";
  static const String _keyFcmTokenWeb = "FCM_TOKEN_WEB";

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

  /// Realiza uma verificação de autorização com o servidor.
  Future<AuthStatus> validarAcessoDiario() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? email = prefs.getString(_keyEmail);
    final String? token = prefs.getString(_keyToken);

    // 1. Se não tem login na memória, já barra na hora
    if (email == null || token == null) {
      return AuthStatus.bloqueado;
    }

    // 2. Bate no servidor (GAS) para ver se o token e o device ainda valem HOJE
    // Nota: O 'autenticarNoServidor' já vai atualizar a data de vencimento no SharedPreferences se der sucesso!
    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: false,
    );

    if (resultado["sucesso"] == true) {
      return AuthStatus.autorizado;
    }
    // 3. MODO OFFLINE (Avião, Subsolo, etc)
    else if (resultado["mensagem"] == "Servidor offline ou bloqueio de rede." ||
        resultado["mensagem"] == "Falha de rede ao descobrir servidor.") {
      // Se for apenas falta de internet, não vamos expulsar o usuário por maldade.
      // Permitimos que ele use o app com base na última licença válida salva.
      _debugLog("🌐 [AUTH] Sem internet. Confiando no passe livre temporário.");
      return AuthStatus.autorizado;
    }
    // 4. O Servidor respondeu explicitamente que a licença VENCEU ou FOI BANIDA
    else {
      _debugLog("⛔ [AUTH] Servidor negou o acesso: ${resultado["mensagem"]}");
      return AuthStatus.bloqueado;
    }
  }

  /// Autentica o usuário junto ao servidor principal (GAS).
  ///
  /// Realiza o envio do e-mail, token, ID do dispositivo e token FCM para notificações.
  /// Trata redirecionamentos 302 em ambientes nativos.
  Future<Map<String, dynamic>> autenticarNoServidor(
    String email,
    String token, {
    bool incluirTokensPush = true,
  }) async {
    final DiscoveryConfig? config = await _discovery.getConfig();
    final String? serverUrl = config?.gasUrl;

    if (serverUrl == null) {
      return {
        "sucesso": false,
        "mensagem": "Falha de rede ao descobrir servidor.",
      };
    }

    final String deviceId = await getDeviceId();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String fcmTokenWeb = incluirTokensPush
        ? prefs.getString(_keyFcmTokenWeb) ?? ""
        : "";
    final String fcmToken = incluirTokensPush ? await _obterFcmToken() : "";

    final Map<String, dynamic> payload = {
      "action": "CHECK_DEVICE",
      "email": email,
      "deviceId": deviceId,
      "token": token,
    };

    if (incluirTokensPush) {
      payload["fcmToken"] = fcmToken;
      payload["fcmTokenWeb"] = fcmTokenWeb;
    }

    try {
      final String bodyData = jsonEncode(payload);
      http.Response response;

      if (kIsWeb) {
        // No Navegador, o CORS nativo gerencia redirecionamentos
        response = await http
            .post(Uri.parse(serverUrl), body: bodyData)
            .timeout(const Duration(seconds: 33));
      } else {
        // No Android/iOS, precisamos seguir o redirecionamento 302 manualmente
        final http.Request request = http.Request('POST', Uri.parse(serverUrl))
          ..followRedirects = false
          ..body = bodyData;

        final http.StreamedResponse streamedResponse = await request
            .send()
            .timeout(const Duration(seconds: 33));
        response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 302 || response.statusCode == 303) {
          final String? redirectUrl = response.headers['location'];
          if (redirectUrl != null) {
            response = await http
                .get(Uri.parse(redirectUrl))
                .timeout(const Duration(seconds: 33));
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
          _debugLog("⚠️ Resposta inesperada: ${response.body}");
          return {
            "sucesso": false,
            "mensagem": "Erro de protocolo do servidor.",
          };
        }
      }
      return {
        "sucesso": false,
        "mensagem": "Erro HTTP (${response.statusCode})",
      };
    } catch (e) {
      _debugLog("❌ Erro Auth: $e");
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
    final String fcmTokenWeb = prefs.getString(_keyFcmTokenWeb) ?? "";

    if (email == null || token == null || fcmTokenWeb.isEmpty) {
      _debugLog(
        "⚠️ [AUTH-WEB] Sincronização de push ignorada por falta de sessão/token web.",
      );
      return false;
    }

    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: true,
    );

    final bool sucesso = resultado["sucesso"] == true;
    _debugLog(
      sucesso
          ? "✅ [AUTH-WEB] Token push web sincronizado com a sessão autorizada."
          : "⛔ [AUTH-WEB] Falha ao sincronizar token push web: ${resultado["mensagem"]}",
    );
    return sucesso;
  }

  Future<bool> sincronizarTokenPushAutorizadoAtual() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(_keyEmail);
    final String? token = prefs.getString(_keyToken);

    if (email == null || token == null) {
      _debugLog("[AUTH-PUSH] Sincronizacao ignorada por falta de sessao ativa.");
      return false;
    }

    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: true,
    );

    final bool sucesso = resultado["sucesso"] == true;
    _debugLog(
      sucesso
          ? "[AUTH-PUSH] Token push sincronizado com sucesso."
          : "[AUTH-PUSH] Falha ao sincronizar token push: ${resultado["mensagem"]}",
    );
    return sucesso;
  }

  Future<bool> sincronizarTokenPushAutorizado() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(_keyEmail);
    final String? token = prefs.getString(_keyToken);

    if (email == null || token == null) {
      _debugLog(
        "⚠️ [AUTH-PUSH] Sincronização ignorada por falta de sessão ativa.",
      );
      return false;
    }

    final String tokenLocal = kIsWeb
        ? prefs.getString(_keyFcmTokenWeb) ?? ""
        : prefs.getString(_keyFcmTokenMobile) ?? "";

    if (tokenLocal.isEmpty) {
      _debugLog(
        "⚠️ [AUTH-PUSH] Sincronização ignorada porque o token local está vazio.",
      );
      return false;
    }

    final Map<String, dynamic> resultado = await autenticarNoServidor(
      email,
      token,
      incluirTokensPush: true,
    );

    final bool sucesso = resultado["sucesso"] == true;
    _debugLog(
      sucesso
          ? "✅ [AUTH-PUSH] Token push sincronizado com a sessão autorizada."
          : "⛔ [AUTH-PUSH] Falha ao sincronizar token push: ${resultado["mensagem"]}",
    );
    return sucesso;
  }

  /// Remove o acesso do dispositivo localmente, limpa o cache e tenta notificar o servidor.
  Future<bool> logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = await getDeviceId();

    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      final String? serverUrl = config?.gasUrl;

      if (serverUrl != null) {
        final String bodyData = jsonEncode({
          "action": "REMOVE_DEVICE",
          "deviceId": deviceId,
        });

        if (kIsWeb) {
          await http
              .post(Uri.parse(serverUrl), body: bodyData)
              .timeout(const Duration(seconds: 10));
        } else {
          final http.Request request =
              http.Request('POST', Uri.parse(serverUrl))
                ..followRedirects = false
                ..body = bodyData;

          await request.send().timeout(const Duration(seconds: 10));
        }
      }
    } catch (e) {
      _debugLog("⚠️ Erro ao remover aparelho do servidor: $e");
    }

    // 🧹 Limpeza total de credenciais
    await prefs.remove(_keyToken);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuario);
    await prefs.remove(_keyVencimento);
    await prefs.remove(_keyIdPlanilha);
    await prefs.remove(_keyLastCheck);

    // 🚀 A MÁGICA AQUI: Destruindo o cache de voos para não deixar rastros!
    await prefs.remove('ALERTS_CACHE_V2');
    await prefs.remove('CACHE_DATE_V2');

    _debugLog(
      "🗑️ [AUTH] Cache de alertas e credenciais destruídos com sucesso.",
    );

    return true;
  }

  /// Notifica o servidor sobre o encerramento da sessão sem aguardar resposta.
  Future<void> logoutSilencioso() async {
    final String deviceId = await getDeviceId();
    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      final String? serverUrl = config?.gasUrl;

      if (serverUrl != null) {
        final String bodyData = jsonEncode({
          "action": "REMOVE_DEVICE",
          "deviceId": deviceId,
        });

        if (kIsWeb) {
          http.post(Uri.parse(serverUrl), body: bodyData);
        } else {
          final http.Request request =
              http.Request('POST', Uri.parse(serverUrl))
                ..followRedirects = false
                ..body = bodyData;
          request.send();
        }
        _debugLog("🌐 Sessão encerrada de forma silenciosa.");
      }
    } catch (e) {
      _debugLog("⚠️ Falha ao deslogar silenciosamente: $e");
    }
  }

  /// Captura o token de notificações push (FCM).
  Future<String> _obterFcmToken() async {
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final String? fcmToken = await messaging.getToken();
      _debugLog("🔑 FCM Token Capturado: $fcmToken");
      return fcmToken ?? "";
    } catch (e) {
      _debugLog("❌ Erro ao capturar FCM Token: $e");
      return "";
    }
  }

  void _debugLog(String message) {
    // ignore: avoid_print
    print(message);
  }
}
