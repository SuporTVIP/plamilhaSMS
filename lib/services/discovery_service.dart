import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configurações para o Modo de Economia (Redução de tráfego em horários de baixo uso).
class EconomyMode {
  final bool enabled;
  final String startTime;
  final String endTime;
  final int multiplier;

  EconomyMode({required this.enabled, required this.startTime, required this.endTime, required this.multiplier});

  factory EconomyMode.fromJson(Map<String, dynamic>? json) {
    if (json == null) return EconomyMode(enabled: false, startTime: "22:30", endTime: "06:00", multiplier: 1);
    return EconomyMode(
      enabled: json['enabled'] ?? false,
      startTime: json['start_time'] ?? "22:30",
      endTime: json['end_time'] ?? "06:00",
      multiplier: json['multiplier'] ?? 4,
    );
  }

  /// Verifica se o horário atual está dentro da janela de economia.
  bool isEconomyTime(DateTime now) {
    if (!enabled) return false;
    try {
      final startMins = int.parse(startTime.split(':')[0]) * 60 + int.parse(startTime.split(':')[1]);
      final endMins = int.parse(endTime.split(':')[0]) * 60 + int.parse(endTime.split(':')[1]);
      final currentMins = now.hour * 60 + now.minute;

      if (startMins > endMins) {
        return currentMins >= startMins || currentMins <= endMins;
      } else {
        return currentMins >= startMins && currentMins <= endMins;
      }
    } catch (e) { return false; }
  }
}

/// Representa o objeto de configuração obtido remotamente.
class DiscoveryConfig {
  final String gasUrl;
  final String status;
  final int pollingIntervalSeconds;
  final EconomyMode economyMode;

  DiscoveryConfig({required this.gasUrl, required this.status, this.pollingIntervalSeconds = 90, required this.economyMode});

  factory DiscoveryConfig.fromJson(Map<String, dynamic> json) {
    return DiscoveryConfig(
      gasUrl: json['gas_url'],
      status: json['status'],
      pollingIntervalSeconds: json['polling_interval_seconds'] ?? 90,
      economyMode: EconomyMode.fromJson(json['economy_mode']),
    );
  }

  bool get isActive => status == 'active';

  /// Retorna o tempo real de espera baseado na hora atual e no modo de economia.
  int get currentPollingInterval {
    if (economyMode.isEconomyTime(DateTime.now())) {
      return pollingIntervalSeconds * economyMode.multiplier;
    }
    return pollingIntervalSeconds;
  }
}

/// Serviço de "Discovery" que descobre onde o servidor principal está hospedado.
///
/// Analogia: Funciona como um "Remote Config" do Firebase ou uma busca dinâmica de DNS.
/// Ele permite mudar a URL do servidor ou o intervalo de busca sem precisar atualizar o App na loja.
class DiscoveryService {
  // URL do Gist que contém as configurações em formato JSON.
  static const String _discoveryUrl = "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";
  static const String _keyCache = "DISCOVERY_CACHE_V2";

  /// Obtém a configuração atual, tentando primeiro a internet e depois o cache local.
  Future<DiscoveryConfig?> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      // Adicionamos um parâmetro de tempo (?v=...) na URL para forçar o GitHub a
      // ignorar o cache do navegador e entregar a versão mais nova.
      final urlSemCache = "$_discoveryUrl?v=${DateTime.now().millisecondsSinceEpoch}";
      final response = await http.get(Uri.parse(urlSemCache)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Atualiza o cache local (Analogia: SharedPreferences = localStorage do JS)
        await prefs.setString(_keyCache, response.body);
        return DiscoveryConfig.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print("⚠️ Erro ao acessar Gist. Tentando cache local...");
    }

    // Fallback: Se estiver sem internet, usa o que foi salvo na última vez que funcionou.
    final cached = prefs.getString(_keyCache);
    if (cached != null) return DiscoveryConfig.fromJson(jsonDecode(cached));
    
    return null; // Sistema crítico offline (sem cache e sem rede)
  }
}
