import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import 'core/theme.dart';
import 'login_screen.dart';
import 'models/alert.dart';
import 'services/alert_service.dart';
import 'services/auth_service.dart';
import 'services/filter_service.dart';
import 'utils/web_window_manager.dart';

// Instância global de Notificações (Analogia: Um serviço de sistema como o Notification Center)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

/// O "Motor Invisível" que executa tarefas em segundo plano (Apenas para Android nativo).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("🤖 [BACKGROUND] O celular acordou o aplicativo em segundo plano! Tarefa: $task");
    return Future.value(true);
  });
}

/// Handler global de mensagens Firebase em segundo plano.
///
/// Disparado pelo sistema operacional quando uma notificação de dados chega com o app fechado.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("📩 Notificação Silenciosa Recebida: ${message.data}");
  
  if (message.data['action'] == 'SYNC_ALERTS') {
    final AlertService service = AlertService();
    service.startMonitoring(); 
  }
}

/// Ponto de entrada do aplicativo (Analogia: Equivale ao `main()` em C# ou Java).
void main() async {
  // Garante que os canais de comunicação com o sistema nativo estejam prontos.
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialização do Firebase de acordo com o ambiente (Web exige chaves explícitas).
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyAZjnPjOVnbnyzm0pwcUti4aZrWA6F4Fmk",
        authDomain: 'plamilhasvipaddondevsadm.firebaseapp.com',
        projectId: 'plamilhasvipaddondevsadm',
        storageBucket: 'plamilhasvipaddondevsadm.firebasestorage.app',
        messagingSenderId: '1070254866174',
        appId: '1:1070254866174:web:0b8a46e3ff211f685cafaf',
        measurementId: 'G-Z2SHWPV2EZ',
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // Define o handler para notificações push recebidas em segundo plano.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Inicialização do Plugin de Notificações Locais para exibição de banners.
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

  // v20+ utiliza parâmetros nomeados para inicialização.
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  // Configura o motor de tarefas em background apenas em dispositivos nativos (Android/iOS).
  if (!kIsWeb) {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
    Workmanager().registerPeriodicTask(
      "RADAR_VIP_TASK_01", 
      "verificarAlertasFundo", 
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  runApp(const MilhasAlertApp());
}

// ==========================================
// APP ROOT
// ==========================================

/// Widget raiz da aplicação, centraliza o tema e o roteamento inicial.
class MilhasAlertApp extends StatelessWidget {
  const MilhasAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlamilhaSVIP',
      theme: ThemeData.dark().copyWith(
        primaryColor: AppTheme.accent,
        scaffoldBackgroundColor: AppTheme.bg,
      ),
      home: const SplashRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// ROTEADOR INICIAL (Splash)
// ==========================================

/// Decide se o usuário deve ver a tela de Login ou o Dashboard principal.
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  /// Verifica no armazenamento local se o usuário já possui um token válido.
  Future<void> _checkLoginStatus() async {
    final bool firstUse = await AuthService().isFirstUse();
    
    // Pequeno atraso para garantir que a Splash Screen seja visível.
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      if (firstUse) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigator()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    );
  }
}

// ==========================================
// CONTROLADOR DE NAVEGAÇÃO (Tabs)
// ==========================================

/// Gerencia a barra de navegação inferior e alterna entre as 3 telas principais.
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> with WidgetsBindingObserver {
  // Controle do índice da aba selecionada.
  int _currentIndex = 1; // Inicia na aba de Licença.

  // Instância única do serviço de monitoramento.
  final AlertService _alertService = AlertService();

  // Definição das telas do aplicativo.
  final List<Widget> _screens = [
    const AlertsScreen(),
    const LicenseScreen(),
    const SmsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Adiciona o observer para escutar mudanças no estado do app (resumed/paused).
    WidgetsBinding.instance.addObserver(this);
    
    // Configura listeners para plataformas Web e inicia polling de dados.
    registerWebCloseListener();
    _alertService.startMonitoring();

    // Escuta novas mensagens via Push (FCM) enquanto o app está aberto.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['action'] == 'SYNC_ALERTS') {
        _alertService.forceSync();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack impede que as abas sejam recarregadas ao alternar, mantendo o scroll.
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.muted,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.flight_takeoff), label: "Alertas"),
          BottomNavigationBarItem(icon: Icon(Icons.badge), label: "Licença"),
          BottomNavigationBarItem(icon: Icon(Icons.sms), label: "SMS"),
        ],
      ),
    );
  }
}

// ==========================================
// TELA 1: ALERTAS (Feed)
// ==========================================

/// Exibe o feed de oportunidades de emissão em tempo real.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with WidgetsBindingObserver {
  // Dependências de Lógica e Som
  final AlertService _alertService = AlertService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Estado dos Dados Filtrados
  final List<Alert> _listaAlertasTodos = [];
  List<Alert> _listaAlertasFiltrados = [];
  UserFilters _filtros = UserFilters();

  // Estado de Visualização
  bool _isCarregando = true;
  bool _isSoundEnabled = true; 

  @override
  void initState() {
    super.initState();
    _loadSoundPreference();
    _carregarFiltrosEIniciar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertService.stopMonitoring();
    super.dispose();
  }

  /// Gatilho para atualizar dados assim que o usuário desbloqueia o celular e volta ao app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("📱 App voltou para o primeiro plano! Sincronizando...");
      _alertService.forceSync();
    }
  }

  /// Busca as preferências de filtragem salvas e ativa o monitoramento.
  Future<void> _carregarFiltrosEIniciar() async {
    _filtros = await UserFilters.load();
    _iniciarMotorDeRecebimento();
  }

  /// Recupera se o som de alerta deve ser emitido.
  Future<void> _loadSoundPreference() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _isSoundEnabled = prefs.getBool('SOUND_ENABLED') ?? true);
    }
  }

  /// Alterna o estado do áudio de notificações.
  Future<void> _toggleSound() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isSoundEnabled = !_isSoundEnabled;
      prefs.setBool('SOUND_ENABLED', _isSoundEnabled);
    });

    if (mounted) {
      _mostrarSnackFeedback(_isSoundEnabled ? "🔊 Sons ATIVADOS" : "🔇 Sons MUTADOS");
    }
  }

  /// Inicia o "motor de tração" ouvindo o fluxo contínuo de alertas do serviço.
  void _iniciarMotorDeRecebimento() {
    _alertService.startMonitoring();

    _alertService.alertStream.listen((novosAlertas) {
      if (mounted) {
        // Proteção contra duplicação: apenas IDs que ainda não estão no widget.
        final List<Alert> alertasIneditos = novosAlertas.where((novo) {
          return !_listaAlertasTodos.any((existente) => existente.id == novo.id);
        }).toList();

        if (alertasIneditos.isEmpty) return;

        // Filtra os inéditos de acordo com as preferências geográficas do usuário.
        final List<Alert> novosQuePassaram = alertasIneditos.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();

        setState(() {
          _listaAlertasTodos.insertAll(0, alertasIneditos);
          _aplicarFiltrosNaTela(); 
          _isCarregando = false;
        });

        // Se houver alertas que passaram no filtro, dispara o som e o push local.
        if (novosQuePassaram.isNotEmpty) {
          _dispararFeedbackDeNovoAlerta(novosQuePassaram.first);
        }
      }
    });

    // Timeout para ocultar o spinner se não houver resposta (ex: sem rede).
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isCarregando) setState(() => _isCarregando = false);
    });
  }

  /// Executa o feedback sonoro e gera a notificação visual.
  Future<void> _dispararFeedbackDeNovoAlerta(Alert alerta) async {
    try {
      if (_isSoundEnabled) {
        await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
      }
      await _mostrarPushLocal(alerta);
    } catch (e) {
      print("Erro ao processar feedback: $e");
    }
  }

  /// Exibe o banner de notificação local no topo da tela do celular.
  Future<void> _mostrarPushLocal(Alert alerta) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emissao_vip_v2',
      'Emissões FãMilhas',
      channelDescription: 'Radar de novas oportunidades',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      sound: const RawResourceAndroidNotificationSound('alerta'), 
      playSound: _isSoundEnabled,
    );
    
    await flutterLocalNotificationsPlugin.show(
      id: alerta.id.hashCode,
      title: '✈️ ${alerta.programa} - Oportunidade!',
      body: alerta.trecho != "N/A" ? alerta.trecho : alerta.mensagem,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  /// Sincroniza a visualização com os filtros atuais.
  void _aplicarFiltrosNaTela() {
    setState(() {
      _listaAlertasFiltrados = _listaAlertasTodos.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();
    });
  }

  /// Abre o modal de configuração de filtros.
  void _abrirPainelFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FilterBottomSheet(
        filtrosAtuais: _filtros,
        onFiltrosSalvos: (novosFiltros) {
          _filtros = novosFiltros;
          _aplicarFiltrosNaTela();
        },
      ),
    );
  }

  /// Exibe uma pequena notificação de feedback no rodapé.
  void _mostrarSnackFeedback(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _isSoundEnabled ? AppTheme.green : AppTheme.red,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitleWithSyncLabel(),
        centerTitle: true,
        actions: [
          _buildVolumeToggleButton(),
          _buildFilterButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: _isCarregando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _listaAlertasFiltrados.isEmpty
              ? _buildEmptyState()
              : _buildFeedList(),
    );
  }

  /// Constrói o título com o rótulo de "Sincronizado há X min".
  Widget _buildTitleWithSyncLabel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, color: AppTheme.accent, size: 22),
            SizedBox(width: 8),
            Text("FEED DE EMISSÕES", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text("VIP", style: TextStyle(fontWeight: FontWeight.w300, color: AppTheme.accent, fontSize: 18)),
          ],
        ),
        Text(AlertService().lastSyncLabel, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
      ],
    );
  }

  /// Botão que alterna o estado do áudio.
  Widget _buildVolumeToggleButton() {
    return IconButton(
      icon: Icon(
        _isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        color: _isSoundEnabled ? AppTheme.accent : AppTheme.muted,
      ),
      onPressed: _toggleSound,
    );
  }

  /// Botão que destaca se existem filtros ativos.
  Widget _buildFilterButton() {
    final bool hasActiveFilters = _filtros.origens.isNotEmpty || _filtros.destinos.isNotEmpty || !_filtros.azulAtivo || !_filtros.latamAtivo || !_filtros.smilesAtivo;
    return IconButton(
      icon: Icon(Icons.tune, color: hasActiveFilters ? AppTheme.green : AppTheme.accent),
      onPressed: _abrirPainelFiltros,
    );
  }

  /// Estado visual para feed vazio.
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flight, size: 64, color: AppTheme.border),
          SizedBox(height: 16),
          Text("Nenhuma emissão encontrada.", style: TextStyle(color: AppTheme.muted)),
          Text("Aguarde novas capturas ou revise seus filtros.", style: TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      ),
    );
  }

  /// Construtor da lista de alertas.
  Widget _buildFeedList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _listaAlertasFiltrados.length,
      itemBuilder: (context, index) => AlertCard(alerta: _listaAlertasFiltrados[index]),
    );
  }
}

// ==========================================
// COMPONENTE: CARD DO ALERTA
// ==========================================

/// Componente que exibe detalhes resumidos e expandidos de um alerta.
class AlertCard extends StatefulWidget {
  final Alert alerta;
  const AlertCard({super.key, required this.alerta});

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  // Controle de expansão do card.
  bool _isExpanded = false;

  /// Abre o navegador externo para a página de emissão.
  void _abrirLinkEmissao() async {
    final String? urlString = widget.alerta.link;
    if (urlString == null || urlString.isEmpty) return;

    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link temporariamente indisponível.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escolha dinâmica de cores baseada no programa de fidelidade.
    final String programa = widget.alerta.programa.toUpperCase();
    final Color highlightColor = _getBrandColor(programa);
    final Color bgColor = _getBrandBgColor(programa);
    final String timestamp = "${widget.alerta.data.hour.toString().padLeft(2, '0')}:${widget.alerta.data.minute.toString().padLeft(2, '0')}";

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isExpanded ? highlightColor.withOpacity(0.5) : AppTheme.border),
        boxShadow: _isExpanded ? [BoxShadow(color: highlightColor.withOpacity(0.1), blurRadius: 10)] : [],
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _buildSummaryRow(highlightColor, timestamp),
            if (_isExpanded) _buildDetailsPanel(highlightColor),
          ],
        ),
      ),
    );
  }

  /// Retorna a cor característica de cada companhia.
  Color _getBrandColor(String prog) {
    if (prog.contains("AZUL")) return const Color(0xFF38BDF8);
    if (prog.contains("LATAM")) return const Color(0xFFF43F5E);
    if (prog.contains("SMILES")) return const Color(0xFFF59E0B);
    return AppTheme.accent;
  }

  /// Retorna a cor de fundo secundária para cada companhia.
  Color _getBrandBgColor(String prog) {
    if (prog.contains("AZUL")) return const Color(0xFF0C1927);
    if (prog.contains("LATAM")) return const Color(0xFF230D14);
    if (prog.contains("SMILES")) return const Color(0xFF22160A);
    return AppTheme.card;
  }

  /// Cabeçalho fixo com o trecho e o programa.
  Widget _buildSummaryRow(Color brandColor, String time) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.flight_takeoff, color: brandColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.alerta.trecho != "N/A" ? widget.alerta.trecho : "Nova Oportunidade!", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text("${widget.alerta.programa} • ${widget.alerta.milhas} milhas", style: TextStyle(color: brandColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      ),
    );
  }

  /// Painel de detalhes que surge ao clicar no card.
  Widget _buildDetailsPanel(Color brandColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const Divider(color: AppTheme.border),
          _buildMetricsRow(),
          const SizedBox(height: 16),
          _buildTextContent(),
          const SizedBox(height: 16),
          if (widget.alerta.link != null) _buildActionButton(brandColor),
        ],
      ),
    );
  }

  /// Exibe os dados técnicos (Datas e Valor Balcão).
  Widget _buildMetricsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildMetricColumn("IDA", widget.alerta.dataIda),
        _buildMetricColumn("VOLTA", widget.alerta.dataVolta),
        _buildMetricColumn("BALCÃO", widget.alerta.valorBalcao, isGreen: true),
      ],
    );
  }

  /// Utilitário para as colunas de dados do card.
  Widget _buildMetricColumn(String label, String value, {bool isGreen = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 9)),
        Text(value, style: TextStyle(color: isGreen ? AppTheme.green : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  /// Bloco de texto com detalhes ou a mensagem bruta do alerta.
  Widget _buildTextContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: SelectableText(
        widget.alerta.detalhes.isNotEmpty ? widget.alerta.detalhes : widget.alerta.mensagem,
        style: const TextStyle(fontSize: 11, height: 1.4),
      ),
    );
  }

  /// Botão que leva para o site de emissão.
  Widget _buildActionButton(Color color) {
    return SizedBox(
      width: double.infinity,
      height: 45,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        icon: const Icon(Icons.open_in_browser, size: 18),
        label: const Text("EMITIR AGORA", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _abrirLinkEmissao,
      ),
    );
  }
}

// ==========================================
// TELA 3: SMS CONNECTOR (Android)
// ==========================================

/// Gerencia o redirecionamento de SMS para processamento de alertas (Mobile).
class SmsScreen extends StatefulWidget {
  const SmsScreen({super.key});

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  // Ponte de comunicação com código nativo (Kotlin/Swift).
  static const MethodChannel _nativeChannel = MethodChannel('com.suportvips.milhasalert/sms_control');

  // Estado local
  bool _isMonitoring = false;
  List<Map<String, String>> _smsHistory = [];
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
    _loadMessageHistory();
    // Verifica novas mensagens salvas pelo serviço nativo a cada 3 segundos.
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessageHistory());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Carrega se o monitoramento está ligado ou desligado.
  Future<void> _loadInitialState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() => _isMonitoring = prefs.getBool('IS_SMS_MONITORING') ?? false);
  }

  /// Busca o histórico de SMS capturados do armazenamento compartilhado.
  Future<void> _loadMessageHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String rawHistory = prefs.getString('SMS_HISTORY') ?? '[]';
    try {
      final List<dynamic> decoded = jsonDecode(rawHistory);
      if (mounted) {
        setState(() {
          _smsHistory = decoded.map((e) => {
            "remetente": e["remetente"].toString(),
            "mensagem": e["mensagem"].toString(),
            "hora": e["hora"].toString(),
          }).toList().reversed.toList();
        });
      }
    } catch(e) {
      print("Erro ao decodificar SMS: $e");
    }
  }

  /// Chama o método nativo para ligar ou pausar a escuta de SMS.
  Future<void> _toggleSmsService() async {
    try {
      final String action = _isMonitoring ? 'stopSmsService' : 'startSmsService';
      await _nativeChannel.invokeMethod(action);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('IS_SMS_MONITORING', !_isMonitoring);
      
      setState(() => _isMonitoring = !_isMonitoring);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Falha no serviço nativo: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebBlocker();

    return Scaffold(
      appBar: AppBar(title: _buildAppBarHeader()),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildStatusIndicator(),
            const SizedBox(height: 24),
            _buildControlBtn(),
            const SizedBox(height: 24),
            _buildHistoryLabel(),
            const SizedBox(height: 10),
            _buildMessageList(),
          ],
        ),
      ),
    );
  }

  /// Cabeçalho da aba SMS.
  Widget _buildAppBarHeader() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.sms, color: AppTheme.accent, size: 22),
        SizedBox(width: 8),
        Text("SMS ", style: TextStyle(fontWeight: FontWeight.w300, fontSize: 16)),
        Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, fontSize: 16)),
      ],
    );
  }

  /// Card que mostra o status atual (Ativo/Pausado).
  Widget _buildStatusIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isMonitoring ? AppTheme.green.withOpacity(0.3) : AppTheme.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            _isMonitoring ? Icons.satellite_alt : Icons.portable_wifi_off,
            size: 60,
            color: _isMonitoring ? AppTheme.green : AppTheme.muted
          ).animate(target: _isMonitoring ? 1 : 0).shimmer(duration: 2.seconds),
          const SizedBox(height: 20),
          Text(
            _isMonitoring ? "MONITORANDO MENSAGENS" : "SISTEMA PAUSADO",
            style: TextStyle(fontWeight: FontWeight.w900, color: _isMonitoring ? AppTheme.green : AppTheme.red, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  /// Botão de ligar/desligar redirecionamento.
  Widget _buildControlBtn() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isMonitoring ? AppTheme.card : AppTheme.accent,
          foregroundColor: _isMonitoring ? AppTheme.red : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(_isMonitoring ? Icons.stop_circle : Icons.play_circle_fill),
        label: Text(_isMonitoring ? "DESATIVAR RADAR" : "ATIVAR RADAR SMS", style: const TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _toggleSmsService,
      ),
    );
  }

  /// Título para a lista de histórico.
  Widget _buildHistoryLabel() {
    return const Row(
      children: [
        Icon(Icons.history, color: AppTheme.muted, size: 18),
        SizedBox(width: 8),
        Text("ÚLTIMOS SMS CAPTURADOS", style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Lista de mensagens exibidas em cards.
  Widget _buildMessageList() {
    return Expanded(
      child: _smsHistory.isEmpty
      ? const Center(child: Text("Aguardando novas mensagens...", style: TextStyle(color: AppTheme.muted, fontSize: 12)))
      : ListView.builder(
          itemCount: _smsHistory.length,
          itemBuilder: (ctx, idx) {
            final msg = _smsHistory[idx];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(msg["remetente"] ?? "", style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(msg["hora"] ?? "", style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(msg["mensagem"] ?? "", style: const TextStyle(fontSize: 11)),
                ],
              ),
            );
          },
        ),
    );
  }

  /// Aviso de incompatibilidade para versão Web.
  Widget _buildWebBlocker() {
    return Scaffold(
      appBar: AppBar(title: _buildAppBarHeader()),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phonelink_erase, size: 80, color: AppTheme.border),
              SizedBox(height: 20),
              Text("Disponível apenas em Celulares", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text(
                "O monitoramento de SMS exige permissões nativas de hardware.\nInstale o app para Android.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TELA 2: LICENÇA (Dashboard)
// ==========================================

/// Dashboard central que mostra dados do usuário e validade da assinatura.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  // Serviços
  final AuthService _auth = AuthService();

  // Estado dos Dados
  String _deviceId = "Carregando...";
  String _userToken = "...";
  String _userEmail = "...";
  String _userUsuario = "...";
  String _userVencimento = "...";
  String _userIdPlanilha = "...";
  String _statusConexao = "Consultando...";

  // Estado de UI
  bool _isBloqueado = false;
  bool _isSaindo = false;

  @override
  void initState() {
    super.initState();
    _inicializarDados();
  }

  /// Carrega todas as informações do usuário logado do cache local.
  Future<void> _inicializarDados() async {
    setState(() => _statusConexao = "Validando...");

    final String id = await _auth.getDeviceId();
    final Map<String, String> dados = await _auth.getDadosUsuario();
    final AuthStatus status = await _auth.validarAcessoDiario();

    if (mounted) {
      setState(() {
        _deviceId = id;
        _userToken = dados['token']!;
        _userEmail = dados['email']!;
        _userUsuario = dados['usuario']!;
        _userVencimento = dados['vencimento']!;
        _userIdPlanilha = dados['idPlanilha']!;
        _isBloqueado = (status != AuthStatus.autorizado);
        _statusConexao = (status == AuthStatus.autorizado) ? "SESSÃO ATIVA" : "⛔ BLOQUEADO";
      });
    }
  }

  /// Realiza o logout e limpa os dados do aparelho.
  Future<void> _executarLogoff() async {
    setState(() => _isSaindo = true);
    await _auth.logout();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashRouter()));
    }
  }

  /// Lógica de cores baseada no prazo de vencimento.
  Color _getCorStatusVencimento(String dataStr) {
    if (dataStr == "..." || dataStr == "N/A") return AppTheme.muted;
    try {
      final partes = dataStr.split('/');
      if (partes.length != 3) return AppTheme.muted;
      final validade = DateTime(int.parse(partes[2]), int.parse(partes[1]), int.parse(partes[0]));
      final hoje = DateTime.now();
      final diff = validade.difference(DateTime(hoje.year, hoje.month, hoje.day)).inDays;
      if (diff <= 3) return AppTheme.red;
      if (diff <= 7) return AppTheme.yellow;
      return AppTheme.green;
    } catch (_) { return AppTheme.muted; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge, color: AppTheme.accent, size: 22),
            SizedBox(width: 8),
            Text("SESSÃO ", style: TextStyle(fontWeight: FontWeight.w300, fontSize: 16)),
            Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _inicializarDados),
        ],
      ),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildAvatarCard(),
            const SizedBox(height: 20),
            _buildInfoGrid(),
            const SizedBox(height: 30),
            _buildLogoutBtn(),
          ],
        ),
      ),
    );
  }

  /// Card superior com o avatar e status neon.
  Widget _buildAvatarCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isBloqueado ? AppTheme.red.withOpacity(0.3) : AppTheme.green.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppTheme.surface,
            backgroundImage: NetworkImage('https://ui-avatars.com/api/?name=${Uri.encodeComponent(_userUsuario)}&background=0D1320&color=3B82F6&size=200&bold=true'),
          ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 20),
          Text(
            _statusConexao,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _isBloqueado ? AppTheme.red : Colors.white, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  /// Lista organizada de dados técnicos da licença.
  Widget _buildInfoGrid() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildDataRow("USUÁRIO", _userUsuario, valColor: Colors.white),
          const Divider(color: AppTheme.border, height: 30),
          _buildDataRow("CHAVE DE ACESSO", _userToken, valColor: AppTheme.accent, isMono: true),
          const Divider(color: AppTheme.border, height: 30),
          _buildDataRow("VÁLIDA ATÉ", _userVencimento, valColor: _getCorStatusVencimento(_userVencimento)),
          const Divider(color: AppTheme.border, height: 30),
          _buildDataRow("ID PLANILHA", _userIdPlanilha, isMono: true, sz: 10),
          const Divider(color: AppTheme.border, height: 30),
          _buildDataRow("ID DISPOSITIVO", _deviceId, isMono: true, sz: 10),
        ],
      ),
    );
  }

  /// Botão para desconectar o aparelho do servidor.
  Widget _buildLogoutBtn() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.red), foregroundColor: AppTheme.red),
        icon: _isSaindo ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.red, strokeWidth: 2)) : const Icon(Icons.power_settings_new),
        label: Text(_isSaindo ? "ENCERRANDO..." : "DESCONECTAR ESTE APARELHO"),
        onPressed: _isSaindo ? null : _executarLogoff,
      ),
    );
  }

  /// Helper para linhas de informação (Label: Valor).
  Widget _buildDataRow(String lbl, String val, {Color valColor = AppTheme.muted, bool isMono = false, double sz = 13}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lbl, style: const TextStyle(color: AppTheme.muted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        SelectableText(val, style: TextStyle(color: valColor, fontSize: sz, fontWeight: FontWeight.bold, fontFamily: isMono ? 'monospace' : null)),
      ],
    );
  }
}

// ==========================================
// COMPONENTE: PAINEL DE FILTROS
// ==========================================

/// Modal inferior para ajuste fino das notificações (Companhias e Aeroportos).
class FilterBottomSheet extends StatefulWidget {
  final UserFilters filtrosAtuais;
  final Function(UserFilters) onFiltrosSalvos;

  const FilterBottomSheet({Key? key, required this.filtrosAtuais, required this.onFiltrosSalvos}) : super(key: key);

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  // Estado local para permitir cancelamento sem aplicar.
  late UserFilters _tempFiltros;
  List<String> _todosAeroportos = [];
  bool _isLoadingAeros = true;

  @override
  void initState() {
    super.initState();
    _tempFiltros = UserFilters(
      latamAtivo: widget.filtrosAtuais.latamAtivo,
      smilesAtivo: widget.filtrosAtuais.smilesAtivo,
      azulAtivo: widget.filtrosAtuais.azulAtivo,
      origens: List.from(widget.filtrosAtuais.origens),
      destinos: List.from(widget.filtrosAtuais.destinos),
    );
    _carregarListaAeroportos();
  }

  /// Carrega os aeroportos suportados para o autocomplete.
  Future<void> _carregarListaAeroportos() async {
    final list = await AeroportoService().getAeroportos();
    if (mounted) setState(() { _todosAeroportos = list; _isLoadingAeros = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: 20, left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildHandle(),
            const SizedBox(height: 20),
            _buildModalTitle(),
            const SizedBox(height: 24),
            _buildSwitches(),
            const Divider(color: AppTheme.border, height: 30),
            if (_isLoadingAeros) const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            else ...[
              _buildLocationPicker("Origens", _tempFiltros.origens),
              const SizedBox(height: 20),
              _buildLocationPicker("Destinos", _tempFiltros.destinos),
            ],
            const SizedBox(height: 30),
            _buildSaveBtn(),
          ],
        ),
      ),
    );
  }

  /// Indicador visual para fechar o modal.
  Widget _buildHandle() {
    return Center(child: Container(width: 40, height: 4, decoration: const BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.all(Radius.circular(10)))));
  }

  /// Título do modal.
  Widget _buildModalTitle() {
    return const Row(
      children: [
        Icon(Icons.radar, color: AppTheme.green),
        SizedBox(width: 10),
        Text("FILTRAGEM AVANÇADA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
      ],
    );
  }

  /// Agrupamento de interruptores para companhias aéreas.
  Widget _buildSwitches() {
    return Column(
      children: [
        _buildSwitchItem("LATAM", const Color(0xFFF43F5E), _tempFiltros.latamAtivo, (v) => setState(() => _tempFiltros.latamAtivo = v)),
        _buildSwitchItem("Smiles", const Color(0xFFF59E0B), _tempFiltros.smilesAtivo, (v) => setState(() => _tempFiltros.smilesAtivo = v)),
        _buildSwitchItem("AZUL", const Color(0xFF38BDF8), _tempFiltros.azulAtivo, (v) => setState(() => _tempFiltros.azulAtivo = v)),
      ],
    );
  }

  /// Helper para o widget de switch.
  Widget _buildSwitchItem(String lbl, Color c, bool val, Function(bool) onChg) {
    return SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(lbl, style: const TextStyle(color: Colors.white, fontSize: 14)), activeColor: c, value: val, onChanged: onChg);
  }

  /// Botão para persistir as mudanças no cache e notificar o feed.
  Widget _buildSaveBtn() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green, foregroundColor: Colors.black),
        child: const Text("APLICAR FILTROS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        onPressed: () async {
          await _tempFiltros.save();
          widget.onFiltrosSalvos(_tempFiltros);
          if(context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  /// Interface de Autocomplete para seleção de cidades/aeroportos.
  Widget _buildLocationPicker(String label, List<String> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 8.0, children: list.map((item) => Chip(label: Text(item, style: const TextStyle(fontSize: 11)), onDeleted: () => setState(() => list.remove(item)))).toList()),
        const SizedBox(height: 10),
        Autocomplete<String>(
          optionsBuilder: (v) => v.text.isEmpty ? const Iterable<String>.empty() : _todosAeroportos.where((a) => a.toLowerCase().contains(v.text.toLowerCase()) && !list.contains(a)),
          onSelected: (s) => setState(() => list.add(s)),
          fieldViewBuilder: (ctx, ctrl, node, sub) => TextField(
            controller: ctrl,
            focusNode: node,
            decoration: InputDecoration(hintText: "Buscar $label...", fillColor: AppTheme.bg, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
