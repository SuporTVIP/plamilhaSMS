import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 🚀 NOVO: Importe o Carteiro
import '../models/alert.dart';
import 'cache_service.dart';
import 'discovery_service.dart';

/// Serviço Singleton responsável por monitorar e buscar novos alertas de milhas no servidor.
class AlertService {
  // Singleton Pattern
  static final AlertService _instancia = AlertService._interno();
  factory AlertService() => _instancia;
  AlertService._interno();

  // Constantes
  static const String _keyLastSync = "LAST_ALERT_SYNC_V2";
  static const int _maxIdsInMemory = 2000;

  // Dependências
  final CacheService _cache = CacheService();
  final DiscoveryService _discovery = DiscoveryService();
  
  // 🚀 NOVO: Instância do Carteiro Local
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  // Estado Interno
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

  // 🚀 NOVO: Inicializa as permissões do Carteiro
  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    
    // Configuração básica para o Android (usa o ícone padrão do app)
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(); // Para iOS
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

// 🚀 Agora com o nome exato que a biblioteca v17 exige
    await _localNotifications.initialize(
      settings: initSettings, 
    );
  }

  void startMonitoring() async {
    if (_isPolling) return;

    await _initNotifications(); // 🚀 NOVO: Liga o carteiro ao iniciar

    // SWR: Carrega cache instantaneamente antes da rede
    await _cache.init();
    final cachedAlerts = _cache.loadAlerts();
    if (cachedAlerts.isNotEmpty) {
      _knownIds.addAll(cachedAlerts.map((a) => a.id));
      _alertController.add(cachedAlerts);
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
    if (_isFetching) {
      print("⏳ Já existe uma busca em andamento. Ignorando...");
      return;
    }

    _isFetching = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String lastSyncStr = prefs.getString(_keyLastSync) ??
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

      final DateTime dataSegura = DateTime.parse(lastSyncStr).subtract(const Duration(hours: 12));

      final uriBase = Uri.parse(gasUrl);
      final uriFinal = uriBase.replace(queryParameters: {
        'action': 'SYNC_ALERTS',
        'since': dataSegura.toIso8601String(),
      });

      final response = await http.get(uriFinal).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final body = jsonDecode(response.body);

        if (body['status'] == 'success') {
          final List<dynamic> rawData = body['data'];

          if (rawData.isNotEmpty) {
            final List<Alert> alertsFromServer = rawData.map((j) => Alert.fromJson(j)).toList();

            final List<Alert> newAlerts = alertsFromServer
                .where((a) => !_knownIds.contains(a.id))
                .toList();

            if (newAlerts.isNotEmpty) {
              print("🔔 ${newAlerts.length} novos alertas encontrados!");

              _knownIds.addAll(newAlerts.map((a) => a.id));
              _alertController.add(newAlerts); // 🚀 Manda TUDO pra tela (histórico)
              _lastSyncTime = DateTime.now();

              final existingInCache = _cache.loadAlerts();
              _cache.saveAlerts([...newAlerts, ...existingInCache]); // 🚀 Salva TUDO no banco

              // 🚀 NOVO: O PORTEIRO AVALIA SE DEVE TOCAR O SOM
              await _processarFiltrosENotificar(newAlerts, prefs);

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

  // 🚀 NOVO: LÓGICA DO PORTEIRO DE FILTROS E NOTIFICAÇÃO LOCAL
  Future<void> _processarFiltrosENotificar(List<Alert> ineditos, SharedPreferences prefs) async {
    // 1. Lê os filtros da memória (assume TRUE se nunca configurou)
    bool querLatam = prefs.getBool('filtro_latam') ?? true;
    bool querSmiles = prefs.getBool('filtro_smiles') ?? true;
    bool querAzul = prefs.getBool('filtro_azul') ?? true;

    List<Alert> alertasQuePassaram = [];

    // 2. Filtra quem deve apitar
    for (var alerta in ineditos) {
      bool passou = false;
      final prog = alerta.programa.toUpperCase();

      if (prog.contains('LATAM') && querLatam) passou = true;
      if (prog.contains('SMILES') && querSmiles) passou = true;
      if (prog.contains('AZUL') && querAzul) passou = true;
      
      // Se não for nenhum dos 3 principais (ex: TAP), deixa passar por padrão
      if (!prog.contains('LATAM') && !prog.contains('SMILES') && !prog.contains('AZUL')) {
        passou = true; 
      }

      if (passou) alertasQuePassaram.add(alerta);
    }

    // 3. Dispara a notificação local apenas para os aprovados
    if (alertasQuePassaram.isNotEmpty) {
      if (alertasQuePassaram.length == 1) {
        _tocarNotificacaoLocal(
          titulo: "✈️ Nova Oportunidade ${alertasQuePassaram.first.programa}",
          corpo: alertasQuePassaram.first.trecho,
        );
      } else {
        _tocarNotificacaoLocal(
          titulo: "🚨 Radar VIP Atualizado",
          corpo: "Encontramos ${alertasQuePassaram.length} passagens que você pode ter perdido!",
        );
      }
    } else {
      print("🤫 ${ineditos.length} alertas baixados em silêncio (Bloqueados pelo Filtro do Usuário).");
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