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

class DiscoveryConfig {
  final String gasUrl;
  final String status;
  final int pollingIntervalSeconds;
  final EconomyMode economyMode;
  final String whatsappGroupUrl;

  DiscoveryConfig({
    required this.gasUrl,
    required this.status,
    this.pollingIntervalSeconds = 90,
    required this.economyMode,
    required this.whatsappGroupUrl,
  });

  factory DiscoveryConfig.fromJson(Map<String, dynamic> json) {
    return DiscoveryConfig(
      gasUrl: json['gas_url'],
      status: json['status'],
      pollingIntervalSeconds: json['polling_interval_seconds'] ?? 1800,
      economyMode: EconomyMode.fromJson(json['economy_mode']),
      whatsappGroupUrl: json['whatsapp_group_url'] ?? 'https://chat.whatsapp.com/DMyfA6rb7jmJsvCJUVU5vk', 
    );
  }

  bool get isActive => status == 'active';

  int get currentPollingInterval {
    if (economyMode.isEconomyTime(DateTime.now())) {
      return pollingIntervalSeconds * economyMode.multiplier;
    }
    return pollingIntervalSeconds;
  }
}

class DiscoveryService {
  // 🚀 SINGLETON: Garante que só existe 1 serviço rodando e economiza RAM
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  static const String _discoveryUrl = "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";
  static const String _keyCache = "DISCOVERY_CACHE_V2";

  // 🚀 COFRE NA MEMÓRIA: Guarda a resposta para acesso instantâneo
  DiscoveryConfig? _cachedConfig;

  Future<DiscoveryConfig?> getConfig() async {
    // Se já baixou hoje, retorna na hora sem gastar internet!
    if (_cachedConfig != null) return _cachedConfig;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    try {
      final String urlWithNoCache = "$_discoveryUrl?v=${DateTime.now().millisecondsSinceEpoch}";
      final response = await http.get(Uri.parse(urlWithNoCache)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await prefs.setString(_keyCache, response.body);
        _cachedConfig = DiscoveryConfig.fromJson(jsonDecode(response.body));
        return _cachedConfig;
      }
    } catch (e) {
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