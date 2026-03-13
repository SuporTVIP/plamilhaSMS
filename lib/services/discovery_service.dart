import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Define o modo de economia do sistema baseado no horário.
class EconomyMode {
  /// Se o modo de economia está ativado.
  final bool enabled;

  /// Horário de início do modo de economia (ex: "22:30").
  final String startTime;

  /// Horário de término do modo de economia (ex: "06:00").
  final String endTime;

  /// Multiplicador para o intervalo de polling durante o modo de economia.
  final int multiplier;

  /// Construtor padrão para [EconomyMode].
  const EconomyMode({
    required this.enabled,
    required this.startTime,
    required this.endTime,
    required this.multiplier,
  });

  /// Cria uma instância de [EconomyMode] a partir de um JSON.
  factory EconomyMode.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const EconomyMode(
        enabled: false,
        startTime: "22:30",
        endTime: "06:00",
        multiplier: 1,
      );
    }
    return EconomyMode(
      enabled: json['enabled'] ?? false,
      startTime: json['start_time'] ?? "22:30",
      endTime: json['end_time'] ?? "06:00",
      multiplier: json['multiplier'] ?? 4,
    );
  }

  /// Verifica se o horário atual está dentro do período de economia.
  bool isEconomyTime(DateTime now) {
    if (!enabled) return false;
    try {
      final int startMins = _toMinutes(startTime);
      final int endMins = _toMinutes(endTime);
      final int currentMins = now.hour * 60 + now.minute;

      if (startMins > endMins) {
        return currentMins >= startMins || currentMins <= endMins;
      } else {
        return currentMins >= startMins && currentMins <= endMins;
      }
    } catch (e) {
      return false;
    }
  }

  int _toMinutes(String time) {
    final List<String> parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

/// Configuração de descoberta obtida do servidor.
class DiscoveryConfig {
  /// URL do Google Apps Script.
  final String gasUrl;

  /// Status do sistema (ex: 'active').
  final String status;

  /// Intervalo padrão de polling em segundos.
  final int pollingIntervalSeconds;

  /// Configurações do modo de economia.
  final EconomyMode economyMode;

  /// URL do grupo de WhatsApp para o balcão.
  final String whatsappGroupUrl;

  /// Construtor padrão para [DiscoveryConfig].
  const DiscoveryConfig({
    required this.gasUrl,
    required this.status,
    this.pollingIntervalSeconds = 90,
    required this.economyMode,
    required this.whatsappGroupUrl,
  });

  /// Cria uma instância de [DiscoveryConfig] a partir de um JSON.
  factory DiscoveryConfig.fromJson(Map<String, dynamic> json) {
    return DiscoveryConfig(
      gasUrl: json['gas_url'],
      status: json['status'],
      pollingIntervalSeconds: json['polling_interval_seconds'] ?? 1800,
      economyMode: EconomyMode.fromJson(json['economy_mode']),
      whatsappGroupUrl: json['whatsapp_group_balcao_url'] ?? 'https://chat.whatsapp.com/G5kPwwdBvagEzBKCSo0TEX', 
    );
  }

  /// Verifica se o sistema está ativo.
  bool get isActive => status == 'active';

  /// Retorna o intervalo de polling atual, considerando o modo de economia.
  int get currentPollingInterval {
    if (economyMode.isEconomyTime(DateTime.now())) {
      return pollingIntervalSeconds * economyMode.multiplier;
    }
    return pollingIntervalSeconds;
  }
}

/// Serviço responsável por obter configurações dinâmicas do servidor.
class DiscoveryService {
  // 🚀 SINGLETON: Garante que só existe 1 serviço rodando e economiza RAM
  static final DiscoveryService _instance = DiscoveryService._internal();

  /// Fábrica que retorna a instância única do serviço.
  factory DiscoveryService() => _instance;

  DiscoveryService._internal();

  static const String _discoveryUrl = "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";
  static const String _keyCache = "DISCOVERY_CACHE_V2";

  // 🚀 COFRE NA MEMÓRIA: Guarda a resposta para acesso instantâneo
  DiscoveryConfig? _cachedConfig;

  /// Obtém a configuração de descoberta, priorizando o cache em memória e depois o local.
  Future<DiscoveryConfig?> getConfig() async {
    // Se já baixou hoje, retorna na hora sem gastar internet!
    if (_cachedConfig != null) return _cachedConfig;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    try {
      final String urlWithNoCache = "$_discoveryUrl?v=${DateTime.now().millisecondsSinceEpoch}";
      final http.Response response = await http.get(Uri.parse(urlWithNoCache)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await prefs.setString(_keyCache, response.body);
        _cachedConfig = DiscoveryConfig.fromJson(jsonDecode(response.body));
        return _cachedConfig;
      }
    } catch (e) {
      // ignore: avoid_print
      print("⚠️ Erro ao acessar o Discovery na rede. Tentando cache local...");
    }

    final String? cachedJson = prefs.getString(_keyCache);
    if (cachedJson != null) {
      _cachedConfig = DiscoveryConfig.fromJson(jsonDecode(cachedJson));
      return _cachedConfig;
    }
    
    return null;
  }
}
