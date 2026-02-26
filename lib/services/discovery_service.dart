import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configurações para o Modo de Economia (Redução de tráfego em horários de baixo uso).
class EconomyMode {
  /// Se o modo de economia está ativo globalmente.
  final bool enabled;

  /// Horário de início no formato "HH:mm".
  final String startTime;

  /// Horário de término no formato "HH:mm".
  final String endTime;

  /// Multiplicador do intervalo de busca (ex: 4x mais lento).
  final int multiplier;

  /// Construtor padrão para o modo de economia.
  EconomyMode({
    required this.enabled,
    required this.startTime,
    required this.endTime,
    required this.multiplier,
  });

  /// Cria uma instância de [EconomyMode] a partir de dados JSON.
  factory EconomyMode.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return EconomyMode(
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

  /// Verifica se o horário atual está dentro da janela definida para economia de tráfego.
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
      print("⚠️ Erro ao calcular horário de economia: $e");
      return false;
    }
  }

  /// Converte string "HH:mm" em total de minutos desde o início do dia.
  int _toMinutes(String time) {
    final List<String> parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

/// Representa o objeto de configuração obtido remotamente via serviço de Discovery.
class DiscoveryConfig {
  /// URL do servidor principal (Google Apps Script).
  final String gasUrl;

  /// Status do sistema (ex: 'active', 'maintenance').
  final String status;

  /// Intervalo base de polling em segundos.
  final int pollingIntervalSeconds;

  /// Configurações de economia de dados para horários alternativos.
  final EconomyMode economyMode;

  /// Construtor para configuração de descoberta.
  DiscoveryConfig({
    required this.gasUrl,
    required this.status,
    this.pollingIntervalSeconds = 90,
    required this.economyMode,
  });

  /// Cria uma instância de [DiscoveryConfig] a partir de dados JSON.
  factory DiscoveryConfig.fromJson(Map<String, dynamic> json) {
    return DiscoveryConfig(
      gasUrl: json['gas_url'],
      status: json['status'],
      pollingIntervalSeconds: json['polling_interval_seconds'] ?? 90,
      economyMode: EconomyMode.fromJson(json['economy_mode']),
    );
  }

  /// Indica se o sistema está operante e aceitando conexões.
  bool get isActive => status == 'active';

  /// Retorna o intervalo de espera atualizado, considerando o modo de economia.
  int get currentPollingInterval {
    if (economyMode.isEconomyTime(DateTime.now())) {
      return pollingIntervalSeconds * economyMode.multiplier;
    }
    return pollingIntervalSeconds;
  }
}

/// Serviço de Discovery para localização dinâmica do servidor principal.
///
/// Analogia: Funciona como um Remote Config do Firebase ou DNS dinâmico,
/// permitindo atualizar endpoints sem novos deploys.
class DiscoveryService {
  // Configurações
  static const String _discoveryUrl = "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";
  static const String _keyCache = "DISCOVERY_CACHE_V2";

  /// Obtém a configuração atual através da rede, com fallback para o cache local.
  Future<DiscoveryConfig?> getConfig() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    try {
      // Força a atualização do cache do provedor (GitHub Gist) via timestamp
      final String urlWithNoCache = "$_discoveryUrl?v=${DateTime.now().millisecondsSinceEpoch}";
      final response = await http.get(Uri.parse(urlWithNoCache)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await prefs.setString(_keyCache, response.body);
        return DiscoveryConfig.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print("⚠️ Erro ao acessar o Discovery na rede. Tentando cache local...");
    }

    // Fallback: Tenta carregar a última configuração válida salva localmente
    final String? cachedJson = prefs.getString(_keyCache);
    if (cachedJson != null) {
      return DiscoveryConfig.fromJson(jsonDecode(cachedJson));
    }
    
    return null;
  }
}
