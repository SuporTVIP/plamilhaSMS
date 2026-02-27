import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';
import 'cache_service.dart';
import 'discovery_service.dart';

class AlertService {
  static final AlertService _instancia = AlertService._interno();
  factory AlertService() => _instancia;
  AlertService._interno();

  // 🚀 Variável de Controle: Silencia o apito na primeira carga (abertura)
  bool _isFirstFetch = true;

  static const String _keyLastSync = "LAST_ALERT_SYNC_V2";
  static const int _maxIdsInMemory = 2000;

  final CacheService _cache = CacheService();
  final DiscoveryService _discovery = DiscoveryService();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _notificationsInitialized = false;
  DateTime? _lastSyncTime;
  Timer? _timer;
  bool _isPolling = false;
  bool _isFetching = false;

  final Set<String> _knownIds = {};
  final StreamController<List<Alert>> _alertController = StreamController<List<Alert>>.broadcast();

  Stream<List<Alert>> get alertStream => _alertController.stream;

  String get lastSyncLabel {
    if (_lastSyncTime == null) return 'Não sincronizado';
    final diff = DateTime.now().difference(_lastSyncTime!);
    if (diff.inMinutes < 1) return 'Agora mesmo';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    return 'Há ${diff.inHours}h';
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _localNotifications.initialize(settings: initSettings);
    _notificationsInitialized = true;
  }

  void startMonitoring() async {
    if (_isPolling) return;
    await _initNotifications();
    await _cache.init();

    final cachedAlerts = _cache.loadAlerts();
    if (cachedAlerts.isNotEmpty) {
      // 🚀 FILTRO DIÁRIO (CACHE): Só carrega o que for de hoje (00:00 até agora)
      final hoje = DateTime.now();
      final inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);

      final alertasDeHoje = cachedAlerts.where((a) => a.data.isAfter(inicioDoDia)).toList();

      if(alertasDeHoje.isNotEmpty) {
        print("📂 Carregando ${alertasDeHoje.length} alertas de HOJE do cache.");
        _knownIds.addAll(alertasDeHoje.map((a) => a.id));
        _alertController.add(alertasDeHoje);
      }
    }

    _isPolling = true;
    _scheduleNextPoll();
  }

  void stopMonitoring() {
    _timer?.cancel();
    _isPolling = false;
    print("🛑 Motor de Polling Parado");
  }

  Future<void> forceSync() async {
    print("🔔 Sincronização forçada iniciada...");
    final config = await _discovery.getConfig();
    if (config != null && config.gasUrl.isNotEmpty) {
      await _checkNewAlerts(config.gasUrl);
    } else {
      print("⚠️ Falha ao forçar sync: URL não encontrada.");
    }
  }

  Future<void> _scheduleNextPoll() async {
    if (!_isPolling) return;

    final config = await _discovery.getConfig();
    if (config == null || !config.isActive) {
      print("⏸️ Sistema em manutenção. Nova tentativa em 60s.");
      _timer = Timer(const Duration(seconds: 60), _scheduleNextPoll);
      return;
    }

    final int intervalo = config.currentPollingInterval;

    await _checkNewAlerts(config.gasUrl);

    print("⏳ Próxima checagem em $intervalo segundos.");
    _timer = Timer(Duration(seconds: intervalo), _scheduleNextPoll);
  }

Future<void> _checkNewAlerts(String gasUrl) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String lastSyncStr = prefs.getString(_keyLastSync) ?? 
          DateTime.now().subtract(const Duration(hours: 12)).toIso8601String();

      final uriBase = Uri.parse(gasUrl);
      final uriFinal = uriBase.replace(queryParameters: {
        'action': 'SYNC_ALERTS',
        'since': lastSyncStr,
      });

      final response = await http.get(uriFinal).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final body = jsonDecode(response.body);

        if (body['status'] == 'success') {
          final List<dynamic> rawData = body['data'];

          if (rawData.isNotEmpty) {
            final List<Alert> alertsFromServer = rawData.map((j) => Alert.fromJson(j)).toList();

            // 🚀 FILTRO DIÁRIO (FETCH): Limita as emissões ao dia atual (00:00 em diante)
            final hoje = DateTime.now();
            final inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);

            final List<Alert> newAlerts = alertsFromServer
                .where((a) => !_knownIds.contains(a.id) && a.data.isAfter(inicioDoDia))
                .toList();

            if (newAlerts.isNotEmpty) {
              _knownIds.addAll(newAlerts.map((a) => a.id));
              _alertController.add(newAlerts);
              _lastSyncTime = DateTime.now();

              final existingInCache = _cache.loadAlerts();
              _cache.saveAlerts([...newAlerts, ...existingInCache]);

              // 🚀 LÓGICA DE NOTIFICAÇÃO DE POLLING
             if (_isFirstFetch) {
                _isFirstFetch = false;
              }
              print("🤫 Polling encontrou ${newAlerts.length} alertas e salvou em silêncio.");

              _limparCacheSeNecessario();
            }

            if (body['serverTime'] != null) {
              await prefs.setString(_keyLastSync, body['serverTime']);
            }
          }
        }
      }
    } catch (e) {
      print("⚠️ Erro na sincronização: $e");
    } finally {
      _isFetching = false;
    }
  }

  // 🚀 PORTEIRO: Processa os filtros e agrupa as notificações
  Future<void> _processarFiltrosENotificar(List<Alert> ineditos, SharedPreferences prefs) async {
    bool querLatam = prefs.getBool('filtro_latam') ?? true;
    bool querSmiles = prefs.getBool('filtro_smiles') ?? true;
    bool querAzul = prefs.getBool('filtro_azul') ?? true;

    List<Alert> aprovados = ineditos.where((alerta) {
      final prog = alerta.programa.toUpperCase();
      if (prog.contains('LATAM')) return querLatam;
      if (prog.contains('SMILES')) return querSmiles;
      if (prog.contains('AZUL')) return querAzul;
      return true; // Outros programas passam por padrão
    }).toList();

    if (aprovados.isNotEmpty) {
      if (aprovados.length == 1) {
        _tocarNotificacaoLocal(
          titulo: "✈️ Oportunidade: ${aprovados.first.programa}",
          corpo: aprovados.first.trecho,
        );
      } else {
        _tocarNotificacaoLocal(
          titulo: "🚨 Radar VIP Atualizado",
          corpo: "Encontramos ${aprovados.length} novas passagens dentro dos seus filtros!",
        );
      }
    }
  }

  // 🚀 NOVO: CONFIGURAÇÃO DO SOM E POP-UP NA TELA
  Future<void> _tocarNotificacaoLocal({required String titulo, required String corpo}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'alertas_vip_channel', 
      'Alertas de Milhas VIP',
      channelDescription: 'Avisa sobre novas passagens dentro do seu filtro',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true, // 🔊 Toca o som padrão do celular
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    // 🚀 Adicionamos o rótulo "notificationDetails:"
    await _localNotifications.show(
      id: DateTime.now().millisecond, 
      title: titulo,
      body: corpo,
      notificationDetails: platformDetails,
    );
  }

  void _limparCacheSeNecessario() {
    if (_knownIds.length > _maxIdsInMemory) {
      final List<String> currentList = _knownIds.toList();
      _knownIds.clear();
      _knownIds.addAll(currentList.skip(currentList.length - 1000));
    }
  }
}