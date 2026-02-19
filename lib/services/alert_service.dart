import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import '../models/alert.dart';

class AlertService {
  static const String _keyLastSync = "LAST_ALERT_SYNC_V2";
  final DiscoveryService _discovery = DiscoveryService();
  
  // Stream para enviar os dados para a Interface Visual
  final _alertController = StreamController<List<Alert>>.broadcast();
  Stream<List<Alert>> get alertStream => _alertController.stream;

  Timer? _timer;
  bool _isPolling = false;

  void startMonitoring() async {
    if (_isPolling) return;
    _isPolling = true;
    print("🚀 Motor de Polling Iniciado");
    _scheduleNextPoll(); 
  }

  void stopMonitoring() {
    _timer?.cancel();
    _isPolling = false;
    print("🛑 Motor de Polling Parado");
  }

  Future<void> _scheduleNextPoll() async {
    if (!_isPolling) return;

    // 1. Descobre de quanto em quanto tempo deve rodar
    final config = await _discovery.getConfig();
    if (config == null || !config.isActive) {
      print("⏸️ Sistema em manutenção ou sem rede. Tentando em 60s.");
      _timer = Timer(const Duration(seconds: 60), _scheduleNextPoll);
      return;
    }

    final int intervalo = config.currentPollingInterval;
    
    // 2. Executa a checagem na API
    await _checkNewAlerts(config.gasUrl);

    // 3. Agenda a próxima rodada (recursividade adaptativa)
    print("⏳ Próxima checagem em $intervalo segundos.");
    _timer = Timer(Duration(seconds: intervalo), _scheduleNextPoll);
  }

  Future<void> _checkNewAlerts(String gasUrl) async {
    final prefs = await SharedPreferences.getInstance();
    String lastSync = prefs.getString(_keyLastSync) ?? 
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

    try {
      final response = await http.get(
        Uri.parse("$gasUrl?action=SYNC_ALERTS&since=$lastSync")
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success') {
          List<dynamic> rawList = body['data'];
          
          if (rawList.isNotEmpty) {
            // Converte o JSON bruto para nossa Classe segura
            List<Alert> novosAlertas = rawList.map((j) => Alert.fromJson(j)).toList();
            
            print("🔔 ${novosAlertas.length} Novos Alertas recebidos do Servidor!");
            
            // Avisa a UI
            _alertController.add(novosAlertas);
            
            // Atualiza o relógio para a próxima checagem
            if (body['serverTime'] != null) {
              await prefs.setString(_keyLastSync, body['serverTime']);
            }
          }
        }
      }
    } catch (e) {
      print("⚠️ Falha na rede ao buscar alertas: $e");
    }
  }
}