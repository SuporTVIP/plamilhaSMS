import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';
import 'cache_service.dart';
import 'discovery_service.dart';

/// Serviço de alertas — Arquitetura 100% Push.
///
/// COMO FUNCIONA:
/// 1. O Google Apps Script envia um FCM Data Message com o Alert COMPLETO (≈1.8KB < limite de 4KB).
/// 2. O _firebaseMessagingBackgroundHandler (main.dart) recebe o push, valida filtros,
///    salva o Alert em SharedPreferences['ALERTS_CACHE_V2'] e dispara a notificação.
/// 3. Quando o app abre (resumed ou foreground), ele chama carregarDoCache() que lê
///    o SharedPreferences e emite os alertas pela alertStream — sem nenhuma chamada HTTP.
/// 4. Na primeira instalação (cache vazio), forceSync() faz UMA única chamada HTTP para
///    popular o histórico inicial. Depois disso, nunca mais precisa da internet para alertas.
class AlertService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final AlertService _instancia = AlertService._interno();

  /// Fábrica que retorna a instância única do serviço.
  factory AlertService() => _instancia;

  AlertService._interno();

  // ── Constantes ────────────────────────────────────────────────────────────
  static const String _keyCacheV2     = 'ALERTS_CACHE_V2';
  static const String _keySyncInicial = 'SYNC_INICIAL_FEITA';
  static const String _keyLastSync    = 'LAST_ALERT_SYNC_V2';

  // ── Dependências ──────────────────────────────────────────────────────────
  final CacheService _cache           = CacheService();
  final DiscoveryService _discovery   = DiscoveryService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // ── Estado interno ────────────────────────────────────────────────────────
  bool _notificationsInitialized = false;
  bool _monitoringStarted        = false;
  DateTime? _lastSyncTime;
  bool _isFetching               = false; // guarda apenas o forceSync inicial


  // ── Fila de Destaques Dourados ────────────────────────────────────────────
  // Cada notificação tocada pelo usuário coloca seu trecho nesta fila.
  // Suporta N notificações pendentes (ex: usuário acumulou 20 alertas):
  // cada clique enfileira seu trecho, e o app os consome na ordem de chegada.
  //
  // Por que fila e não variável simples?
  //   Se o usuário acumulou 20 notificações e começa a clicar uma por uma
  //   sem abrir o app, cada clique chama setPendingHighlight(). Com uma
  //   variável simples, o clique 2 sobrescreveria o clique 1 antes de ser
  //   consumido. Com a fila, todos ficam guardados em ordem.
  final List<String> _pendingHighlightQueue = [];

  /// Enfileira um trecho para ser destacado em dourado.
  ///
  /// Chamado pelo onDidReceiveNotificationResponse e pelo cold-start check.
  void setPendingHighlight(String trecho) {
    final String trechoNormalizado = trecho.trim().toUpperCase();
    // Evita duplicatas consecutivas (ex: dois cliques rápidos na mesma notificação)
    if (_pendingHighlightQueue.isNotEmpty &&
        _pendingHighlightQueue.last == trechoNormalizado) return;
    _pendingHighlightQueue.add(trechoNormalizado);
    _debugLog("✨ [SERVICE] Dourado enfileirado: $trechoNormalizado "
        "(${_pendingHighlightQueue.length} na fila)");
  }

  /// Retira e retorna o próximo trecho da fila (FIFO).
  ///
  /// Retorna null se a fila estiver vazia.
  String? consumePendingHighlight() {
    if (_pendingHighlightQueue.isEmpty) return null;
    final String valor = _pendingHighlightQueue.removeAt(0);
    _debugLog("✨ [SERVICE] Dourado consumido: $valor "
        "(${_pendingHighlightQueue.length} restantes na fila)");
    return valor;
  }

  /// Quantos destaques ainda estão na fila.
  int get pendingHighlightCount => _pendingHighlightQueue.length;

  // ── Streams públicas ──────────────────────────────────────────────────────

  /// Stream de alertas: emite listas de novos alertas para a UI desenhar.
  final StreamController<List<Alert>> _alertController =
      StreamController<List<Alert>>.broadcast();

  /// Getter para a stream de alertas.
  Stream<List<Alert>> get alertStream => _alertController.stream;

  /// Stream de toque em notificação: emite o trecho clicado para acender o Dourado.
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  /// Getter para a stream de toques em notificação.
  Stream<String> get tapStream => _tapController.stream;

  /// Registra um toque em uma notificação.
  void registrarToqueNotificacao(String payload) => _tapController.add(payload);

  // ── Label da AppBar ───────────────────────────────────────────────────────

  /// Retorna um rótulo indicando o tempo desde a última sincronização.
  String get lastSyncLabel {
    if (_lastSyncTime == null) return 'Aguardando push...';
    final Duration diff = DateTime.now().difference(_lastSyncTime!);
    if (diff.inMinutes < 1)  return 'Agora mesmo';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    return 'Há ${diff.inHours}h';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INICIALIZAÇÃO
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);
    await _localNotifications.initialize(settings: initSettings);
    _notificationsInitialized = true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PONTO DE ENTRADA PÚBLICO — chamado pelo MainNavigator
  // ══════════════════════════════════════════════════════════════════════════

  /// Inicia o monitoramento de alertas.
  ///
  /// Na arquitetura 100% Push, "monitorar" significa apenas ler o cache local
  /// que o background push handler preenche. Não há polling, não há timers.
  void startMonitoring() async {
    if (_monitoringStarted) return;
    _monitoringStarted = true;

    await _initNotifications();
    await _cache.init();

    // Carrega o cache local (preenchido pelos pushes FCM anteriores)
    await carregarDoCache();
  }

  /// Para o monitoramento de alertas.
  void stopMonitoring() {
    _monitoringStarted = false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CARGA DO CACHE LOCAL — O CORAÇÃO DA NOVA ARQUITETURA
  // ══════════════════════════════════════════════════════════════════════════

  /// Carrega alertas do SharedPreferences['ALERTS_CACHE_V2'].
  ///
  /// Este cache é preenchido pelo FCM Handler (main.dart)
  /// cada vez que um push com dados completos chega.
  ///
  /// ⚠️ EXCEÇÃO WEB: No web não existe background push handler.
  /// O ALERTS_CACHE_V2 nunca é atualizado automaticamente, então
  /// no web sempre executamos forceSync para buscar dados frescos.
  Future<void> carregarDoCache() async {
    _debugLog("⚡ [SERVICE] Lendo passagens direto do Cache Local (Zero Internet)...");

    // ── WEB: sem handler de background, sempre busca via HTTP ──────────────
    if (kIsWeb) {
      _debugLog("🌐 [SERVICE] Web: sincronizando com o servidor...");
      await forceSync(silencioso: true);
      return;
    }

    // ── MOBILE: lê do cache preenchido pelos pushes FCM ─────────────────────
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final List<String> cacheRaw = prefs.getStringList(_keyCacheV2) ?? [];

    if (cacheRaw.isEmpty) {
      // Cache vazio = primeira instalação. Faz UMA sync HTTP e nunca mais.
      final bool jaTeveSyncInicial = prefs.getBool(_keySyncInicial) ?? false;
      if (!jaTeveSyncInicial) {
        _debugLog("🌐 [SERVICE] Primeira instalação. Fazendo download inicial único...");
        await forceSync(silencioso: true); // HTTP estritamente silencioso
        await prefs.setBool(_keySyncInicial, true);
      }
      return;
    }

    // Desserializa os alertas do cache
    final List<Alert> alertasDoCache = cacheRaw.map((String raw) {
      try {
        return Alert.fromJson(jsonDecode(raw));
      } catch (_) {
        return null;
      }
    }).whereType<Alert>().toList();

    if (alertasDoCache.isNotEmpty) {
      _lastSyncTime = DateTime.now();
      _alertController.add(alertasDoCache);
      _debugLog("✅ [SERVICE] ${alertasDoCache.length} alertas emitidos do cache local.");
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYNC FORÇADO VIA HTTP — Apenas para primeira instalação
  // ══════════════════════════════════════════════════════════════════════════

  /// Busca alertas via HTTP no Google Apps Script.
  ///
  /// Só é usado 1 vez na vida (ou se o usuário forçar via algum botão futuro).
  Future<void> forceSync({bool silencioso = true}) async {
    if (_isFetching) return;
    _isFetching = true;
    _debugLog("🌐 [SERVICE] forceSync() HTTP iniciado...");

    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      if (config == null || config.gasUrl.isEmpty) return;

      final String lastSyncStr =
          DateTime.now().subtract(const Duration(hours: 48)).toIso8601String();
      final Uri uri = Uri.parse(config.gasUrl).replace(
          queryParameters: {'action': 'SYNC_ALERTS', 'since': lastSyncStr});

      final http.Response response =
          await http.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200 ||
          !response.body.trim().startsWith('{')) return;

      final dynamic body = jsonDecode(response.body);
      if (body['status'] != 'success') return;

      final List<dynamic> rawData = body['data'] ?? [];
      if (rawData.isEmpty) return;

      final DateTime hoje        = DateTime.now();
      final DateTime inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);

      final List<Alert> alertsFromServer = rawData
          .map((dynamic j) => Alert.fromJson(j))
          .where((Alert a) => a.data.isAfter(inicioDoDia))
          .toList();

      if (alertsFromServer.isEmpty) return;

      // Salva no ALERTS_CACHE_V2 para unificar com os alertas de push
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cacheAtual =
          prefs.getStringList(_keyCacheV2) ?? [];
      final Set<String> idsNoCache = cacheAtual.map((String raw) {
        try { return jsonDecode(raw)['id'] as String; } catch (_) { return ''; }
      }).toSet();

      final List<Alert> novos = alertsFromServer
          .where((Alert a) => !idsNoCache.contains(a.id))
          .toList();

      if (novos.isNotEmpty) {
        final novosSerializados = novos.map((a) => jsonEncode(a.toJson())).toList();
        final combinado = [...novosSerializados, ...cacheAtual];

        // Dedup por trecho+dataIda: remove duplicatas do mesmo voo na mesma data.
        // Mantém voos com mesmo trecho mas datas diferentes (são emissões distintas).
        final Set<String> chavesVistas = {};
        final List<String> cacheAtualizado = combinado.where((raw) {
          try {
            final m = jsonDecode(raw);
            final trecho  = (m['trecho']  as String? ?? '').toUpperCase().trim();
            final dataIda = (m['dataIda'] as String? ?? '').trim();
            // Se não tem trecho, mantém (não conseguimos deduplicar)
            if (trecho.isEmpty) return true;
            final chave = '\$trecho|\$dataIda';
            return chavesVistas.add(chave);
          } catch (_) { return true; }
        }).take(100).toList();

        await prefs.setStringList(_keyCacheV2, cacheAtualizado);
        _debugLog("💾 [SERVICE] forceSync: +${novos.length} novos "
            "(cache: ${cacheAtualizado.length} entradas).");
      }

      // Emite para a UI silenciosamente (Sem apitar!)
      _lastSyncTime = DateTime.now();
      _alertController.add(alertsFromServer);

      if (body['serverTime'] != null) {
        final SharedPreferences p = await SharedPreferences.getInstance();
        await p.setString(_keyLastSync, body['serverTime']);
      }
    } catch (e) {
      _debugLog("⚠️ [SERVICE] Erro no forceSync: $e");
    } finally {
      _isFetching = false;
    }
  }

  void _debugLog(String message) {
    // ignore: avoid_print
    print(message);
  }
}