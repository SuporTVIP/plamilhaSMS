import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuração central do sistema, lida do Gist.
///
/// Campos vivos:
///   gas_url, status, whatsapp_group_balcao_url,
///   maintenance_mode, min_version, cache_ttl_hours,
///   announcement, push_enabled, sms_blacklist,
///   whatsapp_group_vip_url
///
/// Campos removidos (legado do Workmanager):
///   polling_interval_seconds, economy_mode, _comment, _notes
class DiscoveryConfig {
  /// URL do Google Apps Script — usada por todos os serviços Dart e pelo Kotlin.
  final String gasUrl;

  /// 'active' = sistema ativo. Qualquer outro valor desativa o AeroportoService.
  final String status;

  /// URL do grupo de WhatsApp do balcão.
  final String whatsappGroupUrl;

  /// URL do grupo de WhatsApp VIP (diferente do balcão).
  final String whatsappGroupVipUrl;

  /// Modo de manutenção: exibe banner no feed sem precisar de update do APK.
  final bool maintenanceMode;

  /// Versão mínima aceita. Se menor, o app deve avisar sobre atualização.
  final String minVersion;

  /// Quantas horas o cache de alertas dura. Padrão: 24.
  final int cacheTtlHours;

  /// Banner exibido no topo do feed. Vazio = sem banner.
  final String announcement;

  /// Killswitch de push. false = SW web não exibe notificações.
  final bool pushEnabled;

  /// Palavras que o SmsReceiver.kt usa para bloquear spam.
  /// Atualizado pelo Gist sem precisar de update do APK.
  final List<String> smsBlacklist;

  /// URL de atualização do app, usada no diálogo de versão mínima.
  final String updateUrl;

  //URL do checkout para renovação de licença, usada no diálogo de versão mínima.
  final String urlRenovacaoLicenca;

  final String urlSuporte;

  const DiscoveryConfig({
    required this.gasUrl,
    required this.status,
    required this.whatsappGroupUrl,
    this.whatsappGroupVipUrl = '',
    this.maintenanceMode = false,
    this.minVersion = '0.1.0',
    this.cacheTtlHours = 24,
    this.announcement = '',
    this.pushEnabled = true,
    this.smsBlacklist = const [],
    this.updateUrl = '',
    this.urlRenovacaoLicenca = '',
    this.urlSuporte = "",
  });

  factory DiscoveryConfig.fromJson(Map<String, dynamic> json) {
    return DiscoveryConfig(
      gasUrl: json['gas_url'] ?? '',
      status: json['status'] ?? 'active',
      whatsappGroupUrl:
          json['whatsapp_group_balcao_url'] ??
          'https://chat.whatsapp.com/G5kPwwdBvagEzBKCSo0TEX',
      whatsappGroupVipUrl: json['whatsapp_group_vip_url'] ?? '',
      maintenanceMode: json['maintenance_mode'] ?? false,
      minVersion: json['min_version'] ?? '0.1.0',
      cacheTtlHours: json['cache_ttl_hours'] ?? 24,
      announcement: json['announcement'] ?? '',
      pushEnabled: json['push_enabled'] ?? true,
      smsBlacklist: List<String>.from(json['sms_blacklist'] ?? []),
      updateUrl: json['update_url'] ?? '',
      urlRenovacaoLicenca: json['url_renovacao_licenca'] ?? '',
      urlSuporte: json['url_Suporte'] ?? '',
    );
  }

  bool get isActive => status == 'active';
}

/// Serviço responsável por obter configurações dinâmicas do Gist.
class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  static const String _discoveryUrl =
      "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";

  static const String _keyCache = "DISCOVERY_CACHE_V2";

  /// Chaves gravadas no SharedPreferences para o Kotlin ler.
  /// O Kotlin acessa como "flutter.<chave>" no SharedPreferences nativo.
  static const String keyGasUrl = "DISCOVERY_GAS_URL";
  static const String keySmsBlacklist = "DISCOVERY_SMS_BLACKLIST";

  DiscoveryConfig? _cachedConfig;

  Future<DiscoveryConfig?> getConfig() async {
    if (_cachedConfig != null) return _cachedConfig;

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      final String url =
          "$_discoveryUrl?v=${DateTime.now().millisecondsSinceEpoch}";
      final http.Response response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await prefs.setString(_keyCache, response.body);
        final Map<String, dynamic> json = jsonDecode(response.body);
        _cachedConfig = DiscoveryConfig.fromJson(json);

        // Grava as chaves que o Kotlin precisa para não precisar chamar o Gist
        await prefs.setString(keyGasUrl, _cachedConfig!.gasUrl);
        await prefs.setString(
          keySmsBlacklist,
          jsonEncode(_cachedConfig!.smsBlacklist),
        );

        return _cachedConfig;
      }
    } catch (e) {
      print("⚠️ [DISCOVERY] Rede indisponível. Usando cache local...");
    }

    final String? cachedJson = prefs.getString(_keyCache);
    if (cachedJson != null) {
      _cachedConfig = DiscoveryConfig.fromJson(jsonDecode(cachedJson));
      return _cachedConfig;
    }

    return null;
  }

  void invalidateCache() => _cachedConfig = null;
}
