import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'login_screen.dart'; 
import 'models/alert.dart';
import 'services/alert_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/filter_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'utils/web_window_manager.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🚀 DETECTOR DE WEB
import 'package:flutter/services.dart'; // 🚀 IMPORTA O METHOD CHANNEL
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Instância global de Notificações (Analogia: Um serviço de sistema como o Notification Center)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// 🚀 O MOTOR INVISÍVEL (Roda com o app fechado)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("🤖 [BACKGROUND] O celular acordou o aplicativo em segundo plano! Tarefa: $task");
    
    // Na próxima etapa, colocaremos a chamada da sua Planilha aqui dentro!
    
    return Future.value(true);
  });
}

// 🚀 Handler de mensagens em segundo plano
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Inicialize o Firebase se necessário para esta instância isolada
  await Firebase.initializeApp();
  
  print("📩 Notificação Silenciosa Recebida: ${message.data}");
  
  // Se o payload indicar que há novos alertas, dispara a sincronização
  if (message.data['action'] == 'SYNC_ALERTS') {
    // Aqui você chama seu serviço de alerta já existente
    final AlertService service = AlertService();
    // Você pode adaptar o 'startMonitoring' para fazer apenas um fetch pontual
    service.startMonitoring(); 
  }
}

/// Ponto de entrada do aplicativo.
///
/// Analogia: Equivale ao `main()` em C# ou Java, ou ao início do script global no JS.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On web the default Firebase app must be created with explicit options
  // (see https://firebase.flutter.dev/docs/installation/web).
  // Replace the placeholder values below with your project's configuration
  // or generate a `firebase_options.dart` using `flutterfire configure`.
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

  // Registro do handler de background
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 🚀 INICIALIZAÇÃO DAS NOTIFICAÇÕES
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  // v20+ uses named parameters for initialize
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  // 🚀 BLINDAGEM MULTIPLATAFORMA: Só liga o motor de fundo se NÃO for Web
  if (!kIsWeb) {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, 
    );

    Workmanager().registerPeriodicTask(
      "RADAR_VIP_TASK_01", 
      "verificarAlertasFundo", 
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected, 
      ),
    );
  }

  runApp(const MilhasAlertApp());
}

// ==========================================
// APP ROOT
// ==========================================
/// O "Raiz" do aplicativo, onde definimos o tema e a tela inicial.
///
/// Analogia: Widgets são como Componentes no React ou Elementos no HTML.
class MilhasAlertApp extends StatelessWidget {
  const MilhasAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Milhas Alert',
      // Aplicamos o tema customizado que definimos em core/theme.dart
      theme: ThemeData.dark().copyWith(
        primaryColor: AppTheme.accent,
        scaffoldBackgroundColor: AppTheme.bg,
      ),
      home: const SplashRouter(), // Define qual tela abre primeiro
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// ROTEADOR INICIAL
// ==========================================
/// Tela de transição (Splash) que decide se o usuário vai para o Login ou para o App.
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  /// Ciclo de Vida: Chamado assim que o Widget é inserido na árvore.
  ///
  /// Analogia: Similar ao `useEffect(() => ..., [])` no React ou `OnInit` no Angular/C#.
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _checkLogin() async {
    bool firstUse = await AuthService().isFirstUse();
    
    // Pequeno delay para a tela não "piscar" rapidamente.
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      if (firstUse) {
        // Redireciona para login (Analogia: Router.push no JS)
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigator()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    );
  }
}

// ==========================================
// CONTROLADOR DE NAVEGAÇÃO (As 3 Abas)
// ==========================================
/// Gerencia a navegação por abas (Bottom Navigation Bar).
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 1; // Começa na aba central (Licença)

  final List<Widget> _screens = [
    const AlertsScreen(),
    const LicenseScreen(),
    const SmsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 🚀 Chama a função de adaptação web/nativa
    registerWebCloseListener(); 

    // Listener para notificações firebase quando o app estiver em primeiro plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🚀 PUSH RECEBIDO COM O APP ABERTO!");

      if (message.data['action'] == 'SYNC_ALERTS') {
       print("🚨 Nova passagem detectada via Push! Sincronizando agora...");
        // chamar sua função de download/atualização aqui
         baixarDadosGist();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: Mantém todas as telas na "pilha" mas exibe apenas uma.
      // Analogia: Abas no navegador que mantêm seu estado (como texto digitado) mesmo quando você troca de aba.
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.muted,
        currentIndex: _currentIndex,
        // setState: Redesenha a tela para mostrar a aba selecionada.
        // Analogia: Similar ao `useState` no React (atualiza o valor e re-renderiza).
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
// TELA 1: ALERTAS (Feed em Tempo Real)
// ==========================================
/// Exibe a lista de oportunidades de milhas.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final AlertService _alertService = AlertService();
  final List<Alert> _listaAlertasTodos = []; // Todos os dados recebidos
  List<Alert> _listaAlertasFiltrados = [];   // Apenas o que passa no filtro
  bool _isCarregando = true;
  
  UserFilters _filtros = UserFilters();

  final AudioPlayer _audioPlayer = AudioPlayer();

  // 🚀 1. VARIÁVEL DO SOM
  bool _isSoundEnabled = true; 

  @override
  void initState() {
    super.initState();
    _loadSoundPreference(); // 🚀 2. CARREGA PREFERÊNCIA AO ABRIR
    _carregarFiltros();
  }

  void _carregarFiltros() async {
    _filtros = await UserFilters.load();
    _iniciarMotorDeTracao();
  }

  // 🚀 3. FUNÇÕES DE LIGAR/DESLIGAR E SALVAR NA MEMÓRIA
  Future<void> _loadSoundPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isSoundEnabled = prefs.getBool('SOUND_ENABLED') ?? true;
      });
    }
  }

  Future<void> _toggleSound() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isSoundEnabled = !_isSoundEnabled;
      prefs.setBool('SOUND_ENABLED', _isSoundEnabled);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isSoundEnabled ? "🔊 Notificações sonoras ATIVADAS" : "🔇 Notificações sonoras MUTADAS",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: _isSoundEnabled ? AppTheme.green : AppTheme.red,
          duration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  /// Inicia a escuta da Stream de alertas.
  void _iniciarMotorDeTracao() {
    _alertService.startMonitoring();

    // Se inscreve na Stream (Analogia: .subscribe() no RxJS ou addEventListener no JS).
    _alertService.alertStream.listen((novosAlertas) async {
      if (mounted) {
        // Filtra os alertas em tempo real
        List<Alert> novosQuePassaram = novosAlertas.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();

        setState(() {
          _listaAlertasTodos.insertAll(0, novosAlertas);
          _aplicarFiltrosNaTela(); 
          _isCarregando = false;
        });

       // 🚀 Feedback Sonoro e Visual (Notificação)
        if (novosQuePassaram.isNotEmpty) {
          try {
            if (_isSoundEnabled) { // 🚀 SÓ TOCA SE ESTIVER LIGADO
              await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
            }
            _mostrarNotificacao(novosQuePassaram.first);
          } catch (e) {
            print("Erro ao tocar som: $e");
          }
        }
      }
    });

    // Timeout de segurança para remover o loading se não houver internet.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isCarregando) setState(() => _isCarregando = false);
    });
  }

  /// Gera uma notificação nativa no sistema operacional com SOM CUSTOMIZADO.
  Future<void> _mostrarNotificacao(Alert alerta) async {
    // Não é const porque dependemos de _isSoundEnabled em tempo de execução
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'emissao_vip_v2', // 🚀 MUDAMOS O ID PARA V2 (Força o Android a recriar o canal com o som novo)
      'Emissões FãMilhas',
      channelDescription: 'Avisos de novas passagens',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      // 🚀 A MÁGICA ACONTECE AQUI: Aponta para a pasta res/raw nativa do Android
      sound: const RawResourceAndroidNotificationSound('alerta'), 
      playSound: _isSoundEnabled, // 🚀 OBEDECE AO BOTÃO AQUI TAMBÉM
    );
    
    final NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      id: alerta.id.hashCode,
      title: '✈️ ${alerta.programa} - Nova Oportunidade!',
      body: alerta.trecho != "N/A" ? alerta.trecho : alerta.mensagem,
      notificationDetails: platformChannelSpecifics,
    );
  }

  /// Atualiza a lista exibida com base nos filtros configurados.
  void _aplicarFiltrosNaTela() {
    setState(() {
      _listaAlertasFiltrados = _listaAlertasTodos.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();
    });
  }

  /// Ciclo de Vida: Chamado quando o Widget é destruído.
  ///
  /// Analogia: Equivale ao retorno de uma função no `useEffect` do React (cleanup).
  @override
  void dispose() {
    _alertService.stopMonitoring();
    super.dispose();
  }

  /// Abre o painel inferior para configuração de filtros.
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

  @override
  Widget build(BuildContext context) {
    // Scaffold: A estrutura básica de layout da página (como o <body> no HTML).
    return Scaffold(
      appBar: AppBar(
        // Row: Organiza os elementos horizontalmente (Analogia: display: flex; flex-direction: row).
        title: const Row(
          mainAxisSize: MainAxisSize.min, // Comporta-se como 'width: fit-content'
          children: [
            Icon(Icons.radar, color: AppTheme.accent, size: 22),
            // SizedBox: Cria um espaço fixo entre os elementos (Analogia: margin-right).
            SizedBox(width: 8),
            Text(
              "FEED DE EMISSÕES",
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2, fontSize: 18),
            ),
            Text(
              "VIP",
              style: TextStyle(fontWeight: FontWeight.w300, color: AppTheme.accent, letterSpacing: 2, fontSize: 18),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          // 🚀 NOVO BOTÃO DE VOLUME
          IconButton(
            icon: Icon(
              _isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: _isSoundEnabled ? AppTheme.accent : AppTheme.muted,
            ),
            tooltip: "Ligar/Desligar Som",
            onPressed: _toggleSound,
          ),
          // BOTÃO DE FILTROS ORIGINAL
          IconButton(
            icon: Icon(Icons.tune, color: _filtros.origens.isNotEmpty || _filtros.destinos.isNotEmpty || !_filtros.azulAtivo || !_filtros.latamAtivo || !_filtros.smilesAtivo ? AppTheme.green : AppTheme.accent),
            tooltip: "Filtros",
            onPressed: _abrirPainelFiltros,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isCarregando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _listaAlertasFiltrados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flight, size: 64, color: AppTheme.border),
                      const SizedBox(height: 16),
                      const Text("Nenhuma emissão encontrada.", style: TextStyle(color: AppTheme.muted)),
                      const Text("Verifique seus filtros ou aguarde.", style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                    ],
                  ),
                )
              // ListView.builder: Cria uma lista rolável que carrega apenas o que está visível.
              // Analogia: Similar às Virtual Lists no React ou ao carregamento sob demanda no Web.
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _listaAlertasFiltrados.length,
                  // O itemBuilder é chamado apenas para os itens que aparecem na tela.
                  itemBuilder: (context, index) {
                    final alerta = _listaAlertasFiltrados[index];
                    return AlertCard(alerta: alerta);
                  },
                ),
    );
  }
}

// ==========================================
// COMPONENTE: CARD DO ALERTA
// ==========================================
/// Exibe as informações de um único alerta em um card expansível.
class AlertCard extends StatefulWidget {
  final Alert alerta;
  const AlertCard({super.key, required this.alerta});

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool _isExpanded = false;

  /// Tenta abrir o link de emissão no navegador externo.
  void _abrirLink() async {
    if (widget.alerta.link == null || widget.alerta.link!.isEmpty) return;
    final Uri url = Uri.parse(widget.alerta.link!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Não foi possível abrir o link.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    Color corPrincipal = AppTheme.accent;
    Color corFundo = AppTheme.card;
    
    final prog = widget.alerta.programa.toUpperCase();
    // Lógica visual dinâmica baseada na companhia aérea.
    if (prog.contains("AZUL")) {
      corPrincipal = const Color(0xFF38BDF8);
      corFundo = const Color(0xFF0C1927);
    } else if (prog.contains("LATAM")) {
      corPrincipal = const Color(0xFFF43F5E);
      corFundo = const Color(0xFF230D14);
    } else if (prog.contains("SMILES")) {
      corPrincipal = const Color(0xFFF59E0B);
      corFundo = const Color(0xFF22160A);
    }

    String horaFormatada = "${widget.alerta.data.hour.toString().padLeft(2, '0')}:${widget.alerta.data.minute.toString().padLeft(2, '0')}";

    // AnimatedContainer: Um Container que anima suas propriedades automaticamente (como transitions no CSS).
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16), // Espaçamento externo
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(12), // Border-radius do CSS
        border: Border.all(color: _isExpanded ? corPrincipal.withOpacity(0.5) : AppTheme.border),
        boxShadow: _isExpanded ? [BoxShadow(color: corPrincipal.withOpacity(0.1), blurRadius: 10, spreadRadius: 1)] : [],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        // Column: Organiza os elementos verticalmente (Analogia: display: flex; flex-direction: column).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Alinhamento horizontal (Analogia: align-items: flex-start).
          children: [
            // 🔹 CABEÇALHO (Sempre Visível)
            // Padding: Adiciona preenchimento interno (Analogia: padding do CSS).
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: corPrincipal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.flight_takeoff, color: corPrincipal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.alerta.trecho != "N/A" ? widget.alerta.trecho : "Nova Oportunidade!",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(prog, style: TextStyle(color: corPrincipal, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const Text(" • ", style: TextStyle(color: AppTheme.muted)),
                            Text("${widget.alerta.milhas} milhas", style: const TextStyle(color: AppTheme.text, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(horaFormatada, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                      const SizedBox(height: 4),
                      Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.muted, size: 20),
                    ],
                  )
                ],
              ),
            ),

            // 🔹 DETALHES (Visível apenas se expandido)
            if (_isExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: AppTheme.border, height: 20),
                    
// Grid de Dados Extraídos (Metadados)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInfoColumn("IDA", widget.alerta.dataIda),
                        _buildInfoColumn("VOLTA", widget.alerta.dataVolta),
                        _buildInfoColumn("CUSTO (Milhas)", widget.alerta.valorFabricado),
                        // 🚀 TROCAMOS O NOME E A VARIÁVEL
                        _buildInfoColumn("BALCÃO", widget.alerta.valorBalcao, isHighlight: true), 
                      ],
                    ),
                    const SizedBox(height: 16),

                  Container(
                      height: 90, // Altura fixa e compacta
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3), 
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10), // Borda sutil
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(), // Efeito de mola ao rolar
                        // SelectableText permite que o cliente copie as datas!
                        child: SelectableText(
                          (widget.alerta.detalhes.isNotEmpty && widget.alerta.detalhes != "N/A")
                              ? widget.alerta.detalhes
                              : widget.alerta.mensagem, // Fallback para a mensagem antiga
                          style: const TextStyle(
                            color: AppTheme.text, 
                            fontSize: 11, 
                            height: 1.4 // Espaçamento entre linhas pra facilitar a leitura
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (widget.alerta.link != null && widget.alerta.link!.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: corPrincipal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.open_in_browser, size: 18),
                          label: const Text("EMITIR AGORA", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                          onPressed: _abrirLink,
                        ),
                      )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String titulo, String valor, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(color: AppTheme.muted, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(
          valor, 
          style: TextStyle(
            color: isHighlight ? AppTheme.green : Colors.white, 
            fontSize: 12, 
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal
          )
        ),
      ],
    );
  }
}

// ==========================================
// TELA 3: SMS CONNECTOR (OTIMIZADA)
// ==========================================
class SmsScreen extends StatefulWidget {
  const SmsScreen({super.key});

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  static const platform = MethodChannel('com.suportvips.milhasalert/sms_control');
  bool _isMonitoring = false;
  List<Map<String, String>> _smsHistory = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _carregarEstadoBotao();
    _loadHistory();
    // 🚀 O "Radar" do Flutter: Olha a memória a cada 3 segundos pra ver se o Kotlin salvou algo novo
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadHistory());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel(); // Limpa o timer quando sai da aba
    super.dispose();
  }

  void _carregarEstadoBotao() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isMonitoring = prefs.getBool('IS_SMS_MONITORING') ?? false;
    });
  }

  void _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyStr = prefs.getString('SMS_HISTORY') ?? '[]';
    try {
      final List<dynamic> decoded = jsonDecode(historyStr);
      if (mounted) {
        setState(() {
          _smsHistory = decoded.map((e) => {
            "remetente": e["remetente"].toString(),
            "mensagem": e["mensagem"].toString(),
            "hora": e["hora"].toString(),
          }).toList().reversed.toList(); // Inverte para o mais novo ficar no topo
        });
      }
    } catch(e) {}
  }

  void _toggleMonitoring() async {
    try {
      final bool result = await platform.invokeMethod(_isMonitoring ? 'stopSmsService' : 'startSmsService');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('IS_SMS_MONITORING', !_isMonitoring);
      
      setState(() {
        _isMonitoring = !_isMonitoring;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 BLINDAGEM WEB: Se for navegador, mostra uma tela de aviso bonita e bloqueia o acesso nativo.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sms, color: AppTheme.accent, size: 22),
              SizedBox(width: 8),
              Text("SMS", style: TextStyle(fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 2, fontSize: 16)),
              Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: 2, fontSize: 16)),
            ],
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.phonelink_erase, size: 80, color: AppTheme.border),
                const SizedBox(height: 20),
                const Text("Função Exclusiva Mobile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                const Text(
                  "A interceptação de SMS ocorre localmente no aparelho para garantir a sua privacidade.\n\nInstale o aplicativo no seu celular Android para ativar o motor de captura.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 👇 SE CHEGOU AQUI, É PORQUE ESTÁ NO CELULAR ANDROID (Mostra a tela normal) 👇
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sms, color: AppTheme.accent, size: 22),
            SizedBox(width: 8),
            Text("SMS", style: TextStyle(fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 2, fontSize: 16)),
            Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: 2, fontSize: 16)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card com Animação
            // Container: Um box genérico que pode ter cor, borda, sombra e padding (Analogia: <div>).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              // BoxDecoration: Define a aparência do Container (Bordas, Cores, Sombras).
              decoration: BoxDecoration(
                color: AppTheme.card, 
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: !_isMonitoring ? AppTheme.red.withOpacity(0.3) : AppTheme.green.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: !_isMonitoring ? AppTheme.red.withOpacity(0.05) : AppTheme.green.withOpacity(0.05),
                    blurRadius: 20, spreadRadius: 5
                  )
                ]
              ),
              child: Column(
                children: [
                  Icon(
                    _isMonitoring ? Icons.satellite_alt : Icons.portable_wifi_off, 
                    size: 60, 
                    color: _isMonitoring ? AppTheme.green : AppTheme.muted
                  ).animate(target: _isMonitoring ? 1 : 0)
                   // Shimmer: Um efeito de "brilho" comum em esqueletos de carregamento (Skeletons).
                   .shimmer(duration: 2.seconds, color: Colors.white24),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          color: !_isMonitoring ? AppTheme.red : AppTheme.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isMonitoring ? "MONITORANDO MENSAGENS" : "SISTEMA PAUSADO", 
                        style: TextStyle(
                          fontSize: 14, 
                          fontWeight: FontWeight.w900, 
                          letterSpacing: 1.5,
                          color: !_isMonitoring ? AppTheme.red : AppTheme.green
                        )
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMonitoring ? AppTheme.card : AppTheme.accent,
                  foregroundColor: _isMonitoring ? AppTheme.red : Colors.white,
                  side: _isMonitoring ? const BorderSide(color: AppTheme.red) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: _isMonitoring ? 0 : 10,
                ),
                icon: Icon(_isMonitoring ? Icons.stop_circle : Icons.play_circle_fill, size: 24),
                label: Text(
                  _isMonitoring ? "DESLIGAR SMS" : "INICIAR REDIRECIONAMENTO SMS",
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 14),
                ),
                onPressed: _toggleMonitoring,
              ),
            ),
            const SizedBox(height: 24),

            const Row(
              children: [
                Icon(Icons.history, color: AppTheme.muted, size: 18),
                SizedBox(width: 8),
                Text("ÚLTIMOS SMS CAPTURADOS", style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),

            // Lista Real de SMS
            Expanded(
              child: _smsHistory.isEmpty 
              ? const Center(
                  child: Text("Nenhum SMS interceptado ainda.", style: TextStyle(color: AppTheme.muted, fontSize: 12))
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _smsHistory.length,
                  itemBuilder: (context, index) {
                    final sms = _smsHistory[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(sms["remetente"] ?? "", style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              Text(sms["hora"] ?? "", style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(sms["mensagem"] ?? "", style: const TextStyle(color: AppTheme.text, fontSize: 11)),
                        ],
                      ),
                    );
                  },
                ),
            ),
          ],
        ),
      ),
    );
  }
}
// ==========================================
// TELA 2: LICENÇA (Dashboard)
// ==========================================
/// Exibe informações sobre a licença do usuário e o status do sistema.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final AuthService _auth = AuthService();
  String _deviceId = "Carregando...";
  String _userToken = "...";
  String _userEmail = "...";
  String _userUsuario = "...";
  String _userVencimento = "...";
  String _userIdPlanilha = "...";
  String _statusConexao = "Verificando Servidor...";
  bool _isBloqueado = false;
  bool _isSaindo = false;

  @override
  void initState() {
    super.initState();
    _inicializarSistema();
  }

  /// Carrega os dados necessários para exibir na tela de licença.
  void _inicializarSistema() async {
    setState(() => _statusConexao = "Validando Licença...");
    String id = await _auth.getDeviceId();
    Map<String, String> dados = await _auth.getDadosUsuario();
    AuthStatus status = await _auth.validarAcessoDiario();

    setState(() {
      _deviceId = id;
      _userToken = dados['token']!;
      _userEmail = dados['email']!;
      _userUsuario = dados['usuario']!;
      _userVencimento = dados['vencimento']!;
      _userIdPlanilha = dados['idPlanilha']!;

      _isBloqueado = (status != AuthStatus.autorizado);
      _statusConexao = (status == AuthStatus.autorizado) ? "Serviço Ativo" : "⛔ BLOQUEADO";
    });
  }

  void _fazerLogoff() async {
    setState(() => _isSaindo = true);
    await _auth.logout();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashRouter()));
    }
  }

  /// Lógica de cores para indicar a proximidade do vencimento.
  Color _getCorVencimento(String dataVencimentoStr) {
    if (dataVencimentoStr == "..." || dataVencimentoStr == "N/A") return AppTheme.muted;

    try {
      List<String> partes = dataVencimentoStr.split('/');
      if (partes.length != 3) return AppTheme.muted;

      DateTime validade = DateTime(int.parse(partes[2]), int.parse(partes[1]), int.parse(partes[0]));
      DateTime hoje = DateTime.now();
      hoje = DateTime(hoje.year, hoje.month, hoje.day);
      
      int diasRestantes = validade.difference(hoje).inDays;

      if (diasRestantes <= 3) {
        return AppTheme.red; // Crítico
      } else if (diasRestantes <= 7) {
        return AppTheme.yellow; // Alerta
      } else {
        return AppTheme.green; // Saudável
      }
    } catch (e) {
      return AppTheme.muted;
    }
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
            Text("SESSÃO ", style: TextStyle(fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 2, fontSize: 16)),
            Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: 2, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppTheme.muted), onPressed: _inicializarSistema)
        ],
      ),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Card de Status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: BoxDecoration(
                color: AppTheme.card, 
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isBloqueado ? AppTheme.red.withOpacity(0.3) : AppTheme.green.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: _isBloqueado ? AppTheme.red.withOpacity(0.05) : AppTheme.green.withOpacity(0.05),
                    blurRadius: 20, spreadRadius: 5
                  )
                ]
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppTheme.surface,
                      backgroundImage: NetworkImage(
                        'https://ui-avatars.com/api/?name=${Uri.encodeComponent(_userUsuario)}&background=0D1320&color=3B82F6&size=200&bold=true'
                      ),
                    ).animate()
                     // Animação de entrada: Faz o avatar "crescer" suavemente.
                     .scale(duration: 500.ms, curve: Curves.easeOutBack),
                  ),
                  const SizedBox(height: 20),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          color: _isBloqueado ? AppTheme.red : AppTheme.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _statusConexao.toUpperCase(), 
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.w900, 
                          letterSpacing: 1.5,
                          color: _isBloqueado ? AppTheme.red : Colors.white
                        )
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Grid de Informações
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface, 
                border: Border.all(color: AppTheme.border), 
                borderRadius: BorderRadius.circular(16)
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow("USUÁRIO", _userUsuario, valueColor: Colors.white),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("LICENÇA", _userToken, valueColor: AppTheme.accent, isMono: true),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("VÁLIDA ATÉ", _userVencimento, valueColor: _getCorVencimento(_userVencimento)),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("E-MAIL VINCULADO", _userEmail),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("ID PLANILHA CLIENTE", _userIdPlanilha, isMono: true, size: 10),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("VINCULADO AO APARELHO", _deviceId, isMono: true, size: 10),
                ],
              ),
            ),
            const SizedBox(height: 30),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.red, width: 1.5),
                  foregroundColor: AppTheme.red,
                  backgroundColor: AppTheme.red.withOpacity(0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                icon: _isSaindo 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.red, strokeWidth: 2)) 
                  : const Icon(Icons.power_settings_new),
                label: Text(
                  _isSaindo ? "DESCONECTANDO..." : "DESCONECTAR APARELHO",
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                onPressed: _isSaindo ? null : _fazerLogoff,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, String value, {Color valueColor = AppTheme.muted, bool isMono = false, double size = 13}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SelectableText(
          value, 
          style: TextStyle(
            color: valueColor, 
            fontSize: size, 
            fontWeight: FontWeight.bold,
            fontFamily: isMono ? 'monospace' : null
          )
        ),
      ],
    );
  }
}

// ==========================================
// COMPONENTE: PAINEL DE FILTROS
// ==========================================
/// Modal para configuração de filtros de aeroportos e companhias.
class FilterBottomSheet extends StatefulWidget {
  final UserFilters filtrosAtuais;
  final Function(UserFilters) onFiltrosSalvos;

  const FilterBottomSheet({Key? key, required this.filtrosAtuais, required this.onFiltrosSalvos}) : super(key: key);

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late UserFilters _tempFiltros;
  List<String> _todosAeroportos = [];
  bool _isLoadingAeros = true;

  @override
  void initState() {
    super.initState();
    // Clona os filtros para edição sem afetar a tela principal imediatamente.
    _tempFiltros = UserFilters(
      latamAtivo: widget.filtrosAtuais.latamAtivo,
      smilesAtivo: widget.filtrosAtuais.smilesAtivo,
      azulAtivo: widget.filtrosAtuais.azulAtivo,
      origens: List.from(widget.filtrosAtuais.origens),
      destinos: List.from(widget.filtrosAtuais.destinos),
    );
    _carregarAeroportos();
  }

  void _carregarAeroportos() async {
    final list = await AeroportoService().getAeroportos();
    if (mounted) {
      setState(() {
        _todosAeroportos = list;
        _isLoadingAeros = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20, left: 20, right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: const BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.all(Radius.circular(10))))),
            const SizedBox(height: 20),
            
            const Row(
              children: [
                Icon(Icons.radar, color: AppTheme.green),
                SizedBox(width: 10),
                Text("FILTRAGEM AVANÇADA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 24),

            // Switches para as companhias.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("LATAM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              activeColor: const Color(0xFFF43F5E),
              value: _tempFiltros.latamAtivo,
              onChanged: (val) => setState(() => _tempFiltros.latamAtivo = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Smiles", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              activeColor: const Color(0xFFF59E0B),
              value: _tempFiltros.smilesAtivo,
              onChanged: (val) => setState(() => _tempFiltros.smilesAtivo = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("AZUL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              activeColor: const Color(0xFF38BDF8),
              value: _tempFiltros.azulAtivo,
              onChanged: (val) => setState(() => _tempFiltros.azulAtivo = val),
            ),
            
            const Divider(color: AppTheme.border, height: 30),

            if (_isLoadingAeros) 
              const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            else ...[
              _buildAutocompleteChips("Origens", _tempFiltros.origens),
              const SizedBox(height: 20),
              _buildAutocompleteChips("Destinos", _tempFiltros.destinos),
            ],
            
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.green, 
                  foregroundColor: Colors.black, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 5,
                  shadowColor: AppTheme.green.withOpacity(0.5)
                ),
                child: const Text("APLICAR FILTROS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                onPressed: () async {
                  await _tempFiltros.save(); 
                  widget.onFiltrosSalvos(_tempFiltros); 
                  if(context.mounted) Navigator.pop(context); 
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  /// Constrói um campo de Autocomplete que gera Chips (Tags).
  Widget _buildAutocompleteChips(String titulo, List<String> listaSelecionados) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: const TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        
        // Exibição dos aeroportos selecionados como Chips.
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: listaSelecionados.map((item) {
            return Chip(
              label: Text(item, style: const TextStyle(fontSize: 12, color: Colors.white)),
              backgroundColor: AppTheme.card,
              deleteIcon: const Icon(Icons.close, size: 16, color: AppTheme.red),
              onDeleted: () {
                setState(() => listaSelecionados.remove(item));
              },
            );
          }).toList(),
        ),
        
        if (listaSelecionados.isNotEmpty) const SizedBox(height: 10),

        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
            return _todosAeroportos.where((aeroporto) => 
              aeroporto.toLowerCase().contains(textEditingValue.text.toLowerCase()) && 
              !listaSelecionados.contains(aeroporto)
            );
          },
          onSelected: (String selecao) {
            setState(() => listaSelecionados.add(selecao));
          },
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Adicionar $titulo...",
                hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: AppTheme.muted, size: 20),
                filled: true,
                fillColor: AppTheme.bg,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accent)),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty && !listaSelecionados.contains(value.toUpperCase())) {
                  setState(() {
                    listaSelecionados.add(value.toUpperCase());
                    textEditingController.clear();
                    focusNode.requestFocus();
                  });
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width - 40,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return ListTile(
                        title: Text(option, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        onTap: () {
                          onSelected(option);
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
