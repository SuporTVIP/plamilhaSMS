import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import '../models/alert.dart';
import 'cache_service.dart'; // 🚀 Adicione esta linha no topo

/// Serviço responsável por monitorar e buscar novos alertas de milhas no servidor.
///
/// Este serviço utiliza o padrão "Polling", que consiste em perguntar ao servidor
/// periodicamente se há novidades.

class AlertService {

  final CacheService _cache = CacheService();
  DateTime? _lastSyncTime;

  // Rótulo para a UI (ex: "Atualizado há 2 min")
  String get lastSyncLabel {
    if (_lastSyncTime == null) return 'Não sincronizado';
    final diff = DateTime.now().difference(_lastSyncTime!);
    if (diff.inMinutes < 1) return 'Agora mesmo';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    return 'Há ${diff.inHours}h';
  }

  Timer? _timer;
  bool _isPolling = false;
  bool _isFetching = false;

  final Set<String> _knownIds = {}; // Para evitar duplicatas

  static const int _maxIdsInMemory = 2000; // Limite para evitar consumo excessivo de memória

  static final AlertService _instancia = AlertService._interno();
  factory AlertService() => _instancia;
  AlertService._interno();

  static const String _keyLastSync = "LAST_ALERT_SYNC_V2";
  final DiscoveryService _discovery = DiscoveryService();
  
  /// StreamController para gerenciar a transmissão de dados para a interface.
  ///
  /// Analogia: Funciona como um EventEmitter no Node.js, um Observable (RxJS) no JavaScript,
  /// ou um IObservable no C#. Ele "transmite" os novos alertas para quem estiver "ouvindo".
  final _alertController = StreamController<List<Alert>>.broadcast();

  /// Exposição da Stream para que a UI possa se inscrever e receber atualizações em tempo real.
  Stream<List<Alert>> get alertStream => _alertController.stream;

  /// 🚀 MÉTODO PARA FORÇAR SINCRONIZAÇÃO (VIA PUSH)
Future<void> forceSync() async {
  print("🔔 Sincronização forçada via Push iniciada...");
  
  // 1. Pega a URL do servidor (GAS) que está no Discovery
  final config = await _discovery.getConfig();
  if (config != null && config.gasUrl.isNotEmpty) {
    // 2. Chama a função que você encontrou!
    await _checkNewAlerts(config.gasUrl);
  } else {
    print("⚠️ Falha ao forçar sync: URL do GAS não encontrada.");
  }
}

  /// Inicia o "Motor de Tracção" (Polling).
void startMonitoring() async {
    if (_isPolling) return;
    
    // 🚀 SWR: Carrega cache instantaneamente antes da rede
    await _cache.init();
    final cached = _cache.loadAlerts();
    if (cached.isNotEmpty) {
      _knownIds.addAll(cached.map((a) => a.id));
      _alertController.add(cached); // Já exibe na tela!
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

  /// Agenda a próxima verificação baseada no intervalo definido pelo servidor.
  ///
  /// Este método é assíncrono (`Future`), o que significa que ele não trava a interface
  /// enquanto espera a resposta da rede.
  ///
  /// Analogia: `Future` é exatamente como uma `Promise` em JavaScript ou uma `Task` em C#.
  Future<void> _scheduleNextPoll() async {
    if (!_isPolling) return;

    // 1. Descobre de quanto em quanto tempo deve rodar (Configuração Dinâmica)
    final config = await _discovery.getConfig();
    if (config == null || !config.isActive) {
      print("⏸️ Sistema em manutenção ou sem rede. Tentando em 60s.");
      _timer = Timer(const Duration(seconds: 60), _scheduleNextPoll);
      return;
    }

    final int intervalo = config.currentPollingInterval;
    
    // 2. Executa a checagem na API
    await _checkNewAlerts(config.gasUrl);

    // 3. Agenda a próxima rodada (Recursividade Controlada por Timer)
    print("⏳ Próxima checagem em $intervalo segundos.");
    _timer = Timer(Duration(seconds: intervalo), _scheduleNextPoll);
  }

  /// Limpa o cache de IDs antigos para evitar consumo excessivo de memória.
  void _limparCacheSeNecessario() {
    if (_knownIds.length > _maxIdsInMemory) {
      print("🧹 Limpando IDs antigos do Set para economizar RAM");
      // Remove os IDs mais antigos (os primeiros inseridos)
      List<String> listaTemporaria = _knownIds.toList();
      _knownIds.clear();
      // Mantém apenas os 1000 IDs mais recentes
      _knownIds.addAll(listaTemporaria.skip(listaTemporaria.length - 1000));
    }
  }

  /// Realiza a chamada HTTP para buscar novos alertas desde a última sincronização.
  ///
  /// Analogia: O uso do `http.get` é similar ao `fetch()` ou `axios.get()` no JavaScript,
  /// ou à biblioteca `requests` no Python.
  Future<void> _checkNewAlerts(String gasUrl) async {
    // 🚀 SE JÁ ESTIVER BUSCANDO, IGNORA O NOVO PEDIDO DO PUSH
    if (_isFetching) {
      print("⏳ Já estamos buscando dados no servidor. Ignorando pedido duplo...");
      return;
    }

    _isFetching = true;
  
    final prefs = await SharedPreferences.getInstance();

    // Recupera o último sync (ou ontem, se for a primeira vez)
      String lastSyncStr = prefs.getString(_keyLastSync) ?? 
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
        
      // 🚀 A MÁGICA: Puxa o relógio 12 horas para trás para criar uma "Rede de Segurança"
      // Isso garante que emissões antigas recém-inseridas sejam capturadas.
      DateTime dataSegura = DateTime.parse(lastSyncStr).subtract(const Duration(hours: 12));

    try {
      // 🚀 CONSTRUÇÃO SEGURA DE URL: Garante que caracteres especiais sejam codificados.
      final uriBase = Uri.parse(gasUrl);
      final uriSegura = uriBase.replace(queryParameters: {
        'action': 'SYNC_ALERTS',
        'since': dataSegura.toIso8601String(), // Envia a data com a margem
      });

      final response = await http.get(uriSegura).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        
        // 🚀 TRAVA DE SEGURANÇA: Só tenta ler se realmente for um JSON válido.
        if (response.body.trim().startsWith('{')) {
          final body = jsonDecode(response.body);
          
          if (body['status'] == 'success') {
            List<dynamic> rawList = body['data'];
            
            if (rawList.isNotEmpty) {
              // 1. Converte os dados brutos em objetos
              List<Alert> vindosDoServidor = rawList.map((j) => Alert.fromJson(j)).toList();

              // 🚀 ADICIONE ESTE PRINT PARA VER O QUE CHEGOU
              print("📡 O servidor enviou ${vindosDoServidor.length} alertas (Margem de 12h).");

              // 2. 🚀 A MÁGICA: Filtra apenas os IDs que o app ainda NÃO conhece 
              List<Alert> novosAlertas = vindosDoServidor
                  .where((alerta) => !_knownIds.contains(alerta.id))
                  .toList();

              // 3. Se houver algo realmente novo, processa 
              if (novosAlertas.isNotEmpty) {
                print("🔔 ${novosAlertas.length} alertas INÉDITOS encontrados!");
                
                // Adiciona os IDs novos ao nosso Set de memória 
                _knownIds.addAll(novosAlertas.map((a) => a.id));

                // Notifica a tela apenas com o que é novo
                _alertController.add(novosAlertas);
                _lastSyncTime = DateTime.now(); // Atualiza o marcador de tempo [cite: 85]

                // 🚀 Persiste a lista atualizada no cache local
                final todos = _cache.loadAlerts();
                _cache.saveAlerts([...novosAlertas, ...todos]);
                

                // Mantém o Set saudável (limpeza de janela temporal) 
                _limparCacheSeNecessario();
              }else{
                print("🛡️ Escudo ativado! Todos os alertas já estavam na tela. Nada foi duplicado.");
              }

              // Atualiza o timestamp (continua igual ao seu)
              if (body['serverTime'] != null) {
                await prefs.setString(_keyLastSync, body['serverTime']);
              }
            }
          }
        } else {
          print("⚠️ Servidor não retornou JSON. Resposta: ${response.body}");
        }
      }
    } catch (e) {
      print("⚠️ Falha na rede ao buscar alertas: $e");
    }
    finally {
      _isFetching = false;
    }
  }
}
