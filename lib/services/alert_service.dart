import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';
import 'cache_service.dart';
import 'discovery_service.dart';
import 'filter_service.dart';

class AlertService {
  static final AlertService _instancia = AlertService._interno();
  factory AlertService() => _instancia;
  AlertService._interno();

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
  
  // 🚀 O NOVO RASTREADOR DE CLIQUES EM NOTIFICAÇÕES
  final StreamController<String> _tapController = StreamController<String>.broadcast();
  Stream<String> get tapStream => _tapController.stream;
  void registrarToqueNotificacao(String payload) => _tapController.add(payload);

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
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
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
      final hoje = DateTime.now();
      final inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);
      final alertasDeHoje = cachedAlerts.where((a) => a.data.isAfter(inicioDoDia)).toList();

      if(alertasDeHoje.isNotEmpty) {
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
  }

  // 🚀 AGORA ELE ACEITA O COMANDO "SILENCIOSO" PARA NÃO DAR DUPLO APITO
  Future<void> forceSync({bool silencioso = false}) async {
    print("🔔 Sincronização forçada iniciada (Silencioso: $silencioso)...");
    final config = await _discovery.getConfig();
    if (config != null && config.gasUrl.isNotEmpty) {
      await _checkNewAlerts(config.gasUrl, silencioso: silencioso);
    }
  }

  Future<void> _scheduleNextPoll() async {
    if (!_isPolling) return;
    final config = await _discovery.getConfig();
    if (config == null || !config.isActive) {
      _timer = Timer(const Duration(seconds: 60), _scheduleNextPoll);
      return;
    }
    await _checkNewAlerts(config.gasUrl, silencioso: false);
    _timer = Timer(Duration(seconds: config.currentPollingInterval), _scheduleNextPoll);
  }

  Future<void> _checkNewAlerts(String gasUrl, {bool silencioso = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String lastSyncStr = DateTime.now().subtract(const Duration(hours: 12)).toIso8601String(); 

      final uriBase = Uri.parse(gasUrl);
      final uriFinal = uriBase.replace(queryParameters: {'action': 'SYNC_ALERTS', 'since': lastSyncStr});

      final response = await http.get(uriFinal).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final body = jsonDecode(response.body);

        if (body['status'] == 'success') {
          final List<dynamic> rawData = body['data'];

          if (rawData.isNotEmpty) {
            final List<Alert> alertsFromServer = rawData.map((j) => Alert.fromJson(j)).toList();
            final hoje = DateTime.now();
            final inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);

            final List<Alert> newAlerts = alertsFromServer.where((a) {
              bool isNew = !_knownIds.contains(a.id);
              bool isToday = a.data.isAfter(inicioDoDia);
              return isNew && isToday;
            }).toList();

            if (newAlerts.isNotEmpty) {
              _knownIds.addAll(newAlerts.map((a) => a.id));
              _alertController.add(newAlerts); 
              _lastSyncTime = DateTime.now();

              final existingInCache = _cache.loadAlerts();
              _cache.saveAlerts([...newAlerts, ...existingInCache]);
              _limparCacheSeNecessario();

              // 🚀 SE O APP ACABOU DE ABRIR (SILENCIOSO), ELE ATUALIZA O FEED MAS NÃO APITA!
              if (_isFirstFetch || silencioso) {
                _isFirstFetch = false;
              } else {
                _processarFiltrosENotificar(newAlerts, prefs);
              }
            }
            if (body['serverTime'] != null) await prefs.setString(_keyLastSync, body['serverTime']);
          }
        }
      }
    } catch (e) {
      print("⚠️ Erro na sincronização: $e");
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _processarFiltrosENotificar(List<Alert> ineditos, SharedPreferences prefs) async {
    await prefs.reload();
    final filtros = await UserFilters.load();

    List<Alert> aprovados = ineditos.where((alerta) => filtros.alertaPassaNoFiltro(alerta)).toList();

    if (aprovados.isNotEmpty) {
      if (aprovados.length == 1) {
        _tocarNotificacaoLocal(
          titulo: "✈️ Oportunidade: ${aprovados.first.programa}",
          corpo: aprovados.first.trecho,
          payload: aprovados.first.trecho, // 🚀 ENVIA O TRECHO COMO RASTREADOR
        );
      } else {
        _tocarNotificacaoLocal(
          titulo: "🚨 Radar VIP Atualizado",
          corpo: "Encontramos ${aprovados.length} novas passagens dentro dos seus filtros!",
          payload: "MULTIPLOS",
        );
      }
    }
  }

  Future<void> _tocarNotificacaoLocal({required String titulo, required String corpo, String? payload}) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emissao_vip_v3', 
      'Emissões FãMilhasVIP',
      importance: Importance.max,
      priority: Priority.high,
      sound: const RawResourceAndroidNotificationSound('alerta'), 
      playSound: true, 
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
     id: DateTime.now().millisecond, // 🚀 Colocamos a etiqueta 'id:'
      title: titulo,                  // 🚀 Etiqueta 'title:'
      body: corpo,                    // 🚀 Etiqueta 'body:'
      notificationDetails: platformDetails, // 🚀 Etiqueta 'notificationDetails:'
      payload: payload, // Esse aqui já estava com etiqueta!
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