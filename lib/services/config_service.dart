import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _keyGasUrl = "GAS_URL_V2";
  
  // 🔗 URL DO GIST 
  static const String discoveryUrl = "https://gist.githubusercontent.com/SuporTVIP/ffb616b4d3b24af5071c10c9be2e6895/raw/sms_discovery.json";

  Future<String?> getCachedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGasUrl);
  }

  Future<String?> atualizarDiscovery() async {
    try {
      final response = await http.get(Uri.parse(discoveryUrl));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String novaUrl = data['gas_url'];
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyGasUrl, novaUrl);
        return novaUrl;
      }
    } catch (e) {
      print("Erro Discovery: $e");
    }
    return null;
  }
}