import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert.dart';
import 'cache_service.dart';
import 'discovery_service.dart';

/// Serviço Singleton responsável por monitorar e buscar novos alertas de milhas no servidor.
///
/// Este serviço utiliza uma estratégia de polling combinada com carregamento de cache SWR
/// (Stale-While-Revalidate) para garantir performance e disponibilidade.
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

  // Estado Interno
  DateTime? _lastSyncTime;
  Timer? _timer;
  bool _isPolling = false;
  bool _isFetching = false;

  /// Conjunto de IDs conhecidos para deduplicação em $O(1)$.
  final Set<String> _knownIds = {};

  /// Controlador da transmissão de novos alertas para a interface.
  final StreamController<List<Alert>> _alertController = StreamController<List<Alert>>.broadcast();

  /// Stream para inscrição da interface em tempo real.
  Stream<List<Alert>> get alertStream => _alertController.stream;

  /// Retorna o rótulo legível da última sincronização (ex: "Atualizado há 2 min").
  String get lastSyncLabel {
    if (_lastSyncTime == null) return 'Não sincronizado';
    final diff = DateTime.now().difference(_lastSyncTime!);
    if (diff.inMinutes < 1) return 'Agora mesmo';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    return 'Há ${diff.inHours}h';
  }

  /// Inicia o monitoramento (Polling Engine) com carregamento instantâneo do cache (SWR).
  void startMonitoring() async {
    if (_isPolling) return;

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

  /// Para o monitoramento e limpa os recursos.
  void stopMonitoring() {
    _timer?.cancel();
    _isPolling = false;
    print("🛑 Motor de Polling Parado");
  }

  /// Força a sincronização imediata dos alertas (normalmente disparado via Push).
  Future<void> forceSync() async {
    print("🔔 Sincronização forçada iniciada...");

    final config = await _discovery.getConfig();
    if (config != null && config.gasUrl.isNotEmpty) {
      await _checkNewAlerts(config.gasUrl);
    } else {
      print("⚠️ Falha ao forçar sync: URL não encontrada.");
    }
  }

  /// Agenda a próxima verificação baseada no intervalo definido pelo servidor.
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

  /// Busca novos alertas via API HTTP.
  ///
  /// Mantém trava de segurança [_isFetching] para evitar disparos simultâneos.
  Future<void> _checkNewAlerts(String gasUrl) async {
    // Trava de segurança para evitar concorrência
    if (_isFetching) {
      print("⏳ Já existe uma busca em andamento. Ignorando...");
      return;
    }

    _isFetching = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String lastSyncStr = prefs.getString(_keyLastSync) ??
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

      // Margem de segurança de 12h para capturar registros retroativos
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

            // Filtro de deduplicação em memória O(1)
            final List<Alert> newAlerts = alertsFromServer
                .where((a) => !_knownIds.contains(a.id))
                .toList();

            if (newAlerts.isNotEmpty) {
              print("🔔 ${newAlerts.length} novos alertas encontrados!");

              _knownIds.addAll(newAlerts.map((a) => a.id));
              _alertController.add(newAlerts);
              _lastSyncTime = DateTime.now();

              // Persistência em cache (SWR)
              final existingInCache = _cache.loadAlerts();
              _cache.saveAlerts([...newAlerts, ...existingInCache]);

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
      // Garantia de liberação do recurso
      _isFetching = false;
    }
  }

  /// Garante que o conjunto de IDs não sobrecarregue a memória.
  void _limparCacheSeNecessario() {
    if (_knownIds.length > _maxIdsInMemory) {
      final List<String> currentList = _knownIds.toList();
      _knownIds.clear();
      // Preserva apenas os 1000 registros mais recentes
      _knownIds.addAll(currentList.skip(currentList.length - 1000));
    }
  }
}
