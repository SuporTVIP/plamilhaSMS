import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; // Som de caixa registradora
import 'config_service.dart';

class AlertService {
  static const String _keyLastSync = "LAST_ALERT_SYNC_V1";
  final ConfigService _config = ConfigService();
  final AudioPlayer _audio = AudioPlayer();

  // Stream para avisar a UI que tem alerta novo (Reactive Pattern)
  final _alertController = StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get alertStream => _alertController.stream;

  Timer? _timer;

  // Inicia o "Coração" do Monitoramento
  void startMonitoring({Duration interval = const Duration(seconds: 45)}) {
    _timer?.cancel();
    _checkNewAlerts(); // Checa imediatamente ao abrir
    _timer = Timer.periodic(interval, (_) => _checkNewAlerts());
    print("📡 Monitoramento de Alertas Iniciado (${interval.inSeconds}s)");
  }

  void stopMonitoring() {
    _timer?.cancel();
  }

  Future<void> _checkNewAlerts() async {
    String? url = await _config.getCachedUrl();
    if (url == null) return;

    final prefs = await SharedPreferences.getInstance();
    String lastSync = prefs.getString(_keyLastSync) ?? DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

    try {
      // PULL: "Me dê tudo novo desde 'lastSync'"
      final response = await http.get(Uri.parse("$url?action=SYNC_ALERTS&since=$lastSync"));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success') {
          List<dynamic> rawList = body['data'];
          
          if (rawList.isNotEmpty) {
            print("🔔 ${rawList.length} Novos Alertas Encontrados!");
            
            // 1. Salva o novo checkpoint (Timestamp do servidor)
            String serverTime = body['serverTime'];
            await prefs.setString(_keyLastSync, serverTime);

            // 2. Filtros Locais (Smiles/Latam) seriam aplicados aqui antes de notificar
            // ... logica de filtro ...

            // 3. Toca o Som (Se configurado)
            _tocarSomAlerta();

            // 4. Avisa a UI
            _alertController.add(List<Map<String, dynamic>>.from(rawList));
          }
        }
      }
    } catch (e) {
      print("⚠️ Erro ao buscar alertas: $e");
    }
  }

  void _tocarSomAlerta() async {
    // Verifica preferência do usuário antes de tocar
    final prefs = await SharedPreferences.getInstance();
    bool somAtivo = prefs.getBool('SOM_ATIVO') ?? true;
    
    if (somAtivo) {
      // Certifique-se de ter o arquivo 'assets/sounds/cash.mp3'
      await _audio.play(AssetSource('sounds/cash.mp3'));
    }
  }
}