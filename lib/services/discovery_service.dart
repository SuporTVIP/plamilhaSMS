import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  // Retorna o tempo real baseando-se na hora atual
  int get currentPollingInterval {
    if (economyMode.isEconomyTime(DateTime.now())) {
      return pollingIntervalSeconds * economyMode.multiplier;
    }
    return pollingIntervalSeconds;
  }
}

class DiscoveryService {
  static const String _discoveryUrl = "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";
  static const String _keyCache = "DISCOVERY_CACHE_V2";

  Future<DiscoveryConfig?> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      final response = await http.get(Uri.parse(_discoveryUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await prefs.setString(_keyCache, response.body); // Atualiza o cache local
        return DiscoveryConfig.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print("⚠️ Erro ao acessar Gist. Tentando cache local...");
    }

    // Fallback: Se estiver sem internet, usa o que estava salvo
    final cached = prefs.getString(_keyCache);
    if (cached != null) return DiscoveryConfig.fromJson(jsonDecode(cached));
    
    return null; // Sistema crítico offline
  }
}