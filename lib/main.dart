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
//import 'package:flutter_local_notifications/flutter_local_notifications.dart'; 
import 'dart:ui';
import 'widgets/consentimento_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'services/discovery_service.dart';
import 'package:http/http.dart' as http;

// Instância global de Notificações (Analogia: Um serviço de sistema como o Notification Center)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// 🚀 O MOTOR INVISÍVEL (Workmanager)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("🤖 [BACKGROUND] Workmanager acordou! Tarefa: $task");

    try {
      await Firebase.initializeApp();

      // 🚀 USA O CÉREBRO CENTRAL DE FILTROS
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final filtros = await UserFilters.load();

      final String lastSyncStr = DateTime.now().subtract(const Duration(hours: 12)).toIso8601String();
      final String? discoveryCache = prefs.getString('DISCOVERY_CACHE_V2');
      String? gasUrl;

      if (discoveryCache != null && discoveryCache.isNotEmpty) {
        try {
          final Map<String, dynamic> configJson = jsonDecode(discoveryCache);
          gasUrl = configJson['gas_url'];
        } catch (_) {}
      }

      if (gasUrl == null || gasUrl.isEmpty) return Future.value(true);

      final uri = Uri.parse(gasUrl).replace(queryParameters: {'action': 'SYNC_ALERTS', 'since': lastSyncStr});
      final response = await http.get(uri).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) return Future.value(true);
      final body = jsonDecode(response.body);
      if (body['status'] != 'success') return Future.value(true);

      final List<dynamic> rawData = body['data'] ?? [];
      final List<String> knownIds = List<String>.from(jsonDecode(prefs.getString('WM_KNOWN_IDS') ?? '[]'));
      final hoje = DateTime.now();
      final inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);

      final novasAprovadas = rawData.where((j) {
        try {
          final String id = j['id']?.toString() ?? '';
          final DateTime data = DateTime.parse(j['data'] ?? '');
          final String prog = (j['programa'] ?? '').toString();
          final String trecho = (j['trecho'] ?? '').toString();

          if (knownIds.contains(id)) return false;
          if (!data.isAfter(inicioDoDia)) return false;

          // 🚀 A MÁGICA ACONTECE AQUI: Deixa o Cérebro Central decidir
          return filtros.passaNoFiltroBasico(prog, trecho);
        } catch (_) {
          return false;
        }
      }).toList();

      if (novasAprovadas.isEmpty) return Future.value(true);

      final novosIds = novasAprovadas.map((j) => j['id'].toString()).toList();
      final idsAtualizados = [...knownIds, ...novosIds];
      final idsParaSalvar = idsAtualizados.length > 500 ? idsAtualizados.sublist(idsAtualizados.length - 500) : idsAtualizados;
      await prefs.setString('WM_KNOWN_IDS', jsonEncode(idsParaSalvar));

      final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();
      await localNotif.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/launcher_icon')));

      final androidPlugin = localNotif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'emissao_vip_v3', 'Emissões FãMilhasVIP',
          importance: Importance.max, sound: RawResourceAndroidNotificationSound('alerta'), playSound: true, enableVibration: true,
        ),
      );

      final String titulo = novasAprovadas.length == 1 ? "✈️ Oportunidade: ${novasAprovadas.first['programa']}" : "🚨 Radar VIP Atualizado";
      final String corpo = novasAprovadas.length == 1 ? novasAprovadas.first['trecho']?.toString() ?? 'Nova passagem encontrada!' : "Encontramos ${novasAprovadas.length} novas passagens nos seus filtros!";

      await localNotif.show(
        id: DateTime.now().millisecond, title: titulo, body: corpo,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('emissao_vip_v3', 'Emissões FãMilhasVIP', importance: Importance.max, priority: Priority.high, sound: RawResourceAndroidNotificationSound('alerta'), playSound: true),
        ),
      );

    } catch (e) {
      print("❌ [WM] Erro fatal no background: $e");
    }
    return Future.value(true);
  });
}

// 🚀 Handler de mensagens do Firebase (Push Oculto)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {

  debugPrint("🚨 [FCM] ACORDOU O BACKGROUND! Dados: ${message.data}");
  await Firebase.initializeApp();
  print("📩 Push Oculto Recebido (Tela Apagada): ${message.data}");

  if (message.data['action'] == 'SYNC_ALERTS' || message.data['tipo'] == 'NOVO_ALERTA') {
    // 🚀 USA O CÉREBRO CENTRAL DE FILTROS
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final filtros = await UserFilters.load();

    String programa = (message.data['programa'] ?? 'Geral');
    String trecho = (message.data['trecho'] ?? 'Nova Passagem Encontrada!');

    // 🚀 A MÁGICA ACONTECE AQUI TAMBÉM
    if (filtros.passaNoFiltroBasico(programa, trecho)) {
      print("✅ Filtro Aprovado no Background! Preparando notificação...");
      try {
        final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();
        await localNotif.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/launcher_icon')));

        final androidPlugin = localNotif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'emissao_vip_v3', 'Emissões FãMilhasVIP',
            importance: Importance.max, sound: RawResourceAndroidNotificationSound('alerta'), playSound: true, enableVibration: true,
          ),
        );

        await localNotif.show(
          id: DateTime.now().millisecond,
          title: "✈️ Oportunidade: $programa",
          body: trecho,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('emissao_vip_v3', 'Emissões FãMilhasVIP', importance: Importance.max, priority: Priority.high, sound: RawResourceAndroidNotificationSound('alerta'), playSound: true),
          ),
          payload: trecho, // 🚀 ENVIA O TRECHO COMO RASTREADOR
        );
      } catch (e) {
        print("❌ [BACKGROUND] Falha ao disparar notificação: $e");
      }
    } else {
      print("⛔ [BACKGROUND] BLOQUEADO pelo Cérebro Central (Destino ou Companhia não bate).");
    }
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

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // 🚀 NOVO: Imprime o Token FCM para provarmos que a conexão deu certo!
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      print("🔥 FIREBASE CONECTADO! TOKEN FCM: $token");
    } catch (e) {
      print("⚠️ Erro ao buscar Token do Firebase: $e");
    }

  // 🚀 INICIALIZAÇÃO DAS NOTIFICAÇÕES
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null && response.payload!.isNotEmpty) {
        // 🚀 O usuário clicou! Avisa o serviço para acender o Dourado!
        AlertService().registrarToqueNotificacao(response.payload!);
      }
    },
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
      title: 'PlamilhaSVIP',
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
// ==========================================
// ROTEADOR INICIAL — INTRO CINEMATOGRÁFICA
// ==========================================
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});
  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter>
    with TickerProviderStateMixin {

  // ── Controladores ──────────────────────────────────────────────
  late final AnimationController _ctrlLetterbox;
  late final AnimationController _ctrlLogo;
  late final AnimationController _ctrlGlow;
  late final AnimationController _ctrlExit;

  // ── Animações ──────────────────────────────────────────────────
  late final Animation<double> _letterboxTop;    // barra superior
  late final Animation<double> _letterboxBottom; // barra inferior
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _glowRadius;
  late final Animation<double> _exitOpacity;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Letterbox entra (300 ms)
    _ctrlLetterbox = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
    _letterboxTop    = Tween(begin: -80.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrlLetterbox, curve: Curves.easeOut));
    _letterboxBottom = Tween(begin: 80.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrlLetterbox, curve: Curves.easeOut));

    // 2. Logo aparece (700 ms, começa após 400 ms)
    _ctrlLogo = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
    _logoOpacity = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrlLogo, curve: Curves.easeIn));
    _logoScale = Tween(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrlLogo, curve: Curves.easeOutBack));

    // 3. Glow pulsa (900 ms, loop 2×)
    _ctrlGlow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    _glowRadius = Tween(begin: 8.0, end: 36.0)
        .animate(CurvedAnimation(parent: _ctrlGlow, curve: Curves.easeInOut));

    // 4. Saída: fade para preto (500 ms)
    _ctrlExit = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _exitOpacity = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrlExit, curve: Curves.easeIn));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Paralelo: letterbox + verificação de login
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 200)),
      _ctrlLetterbox.forward(),
    ]);

    await Future.delayed(const Duration(milliseconds: 100));
    if (!kIsWeb) {
  _introPlayer.play(AssetSource('sounds/intro.mp3')).ignore();
}
    await _ctrlLogo.forward();

    // Glow pulsa 2 vezes
    for (int i = 0; i < 2; i++) {
      await _ctrlGlow.forward();
      await _ctrlGlow.reverse();
    }

    // Segurar logo por um instante (estilo Game Freak)
    await Future.delayed(const Duration(milliseconds: 400));

    // Fade de saída + checar login simultaneamente
    final nextScreen = _resolveNextScreen();
    await _ctrlExit.forward();

    if (mounted && !_navigated) {
      _navigated = true;
      final screen = await nextScreen;
      if (mounted) {
        Navigator.pushReplacement(
          context, PageRouteBuilder(
            pageBuilder: (_, __, ___) => screen,
            transitionDuration: Duration.zero,
          ),
        );
      }
    }
  }

  Future<Widget> _resolveNextScreen() async {
    final firstUse = await AuthService().isFirstUse();
    return firstUse ? const LoginScreen() : const MainNavigator();
  }

  final AudioPlayer _introPlayer = AudioPlayer();

  @override
  void dispose() {
     _introPlayer.dispose(); // Garantindo que o player de áudio seja liberado quando a tela for destruída
    _ctrlLetterbox.dispose();
    _ctrlLogo.dispose();
    _ctrlGlow.dispose();
    _ctrlExit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [_ctrlLetterbox, _ctrlLogo, _ctrlGlow, _ctrlExit]),
        builder: (context, _) {
          return Stack(
            children: [

              // ── Fundo com grade pontilhada sutil (estética cyberpunk/VIP) ──
              Positioned.fill(
                child: CustomPaint(painter: _DotGridPainter()),
              ),

              // ── Centro: Logo + nome ──────────────────────────────────────
              Center(
                child: Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        // Ícone com glow
                        Container(
                          width: 96, height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withOpacity(0.7),
                                blurRadius: _glowRadius.value,
                                spreadRadius: _glowRadius.value * 0.3,
                              ),
                              BoxShadow(
                                color: Colors.white.withOpacity(0.08),
                                blurRadius: _glowRadius.value * 2,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/icon.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppTheme.accent.withOpacity(0.15),
                                child: Icon(Icons.flight,
                                    color: AppTheme.accent, size: 48),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Nome com split de cor (igual à AppBar)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text("PLAMILHAS",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6,
                                shadows: [
                                  Shadow(color: AppTheme.accent.withOpacity(0.4),
                                      blurRadius: _glowRadius.value),
                                ],
                              ),
                            ),
                            Text("VIP",
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 28,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 6,
                                shadows: [
                                  Shadow(color: AppTheme.accent,
                                      blurRadius: _glowRadius.value * 1.2),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Tagline
                        Text("RADAR DE EMISSÕES VIP",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 10,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Barras letterbox ─────────────────────────────────────────
              Positioned(
                top: _letterboxTop.value,
                left: 0, right: 0,
                child: Container(height: 80, color: Colors.black),
              ),
              Positioned(
                bottom: _letterboxBottom.value,
                left: 0, right: 0,
                child: Container(height: 80, color: Colors.black),
              ),

              // ── Fade de saída (overlay preto) ────────────────────────────
              if (_ctrlExit.value > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: _exitOpacity.value,
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Fundo pontilhado sutil ───────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeCap = StrokeCap.round;
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }
  @override
  bool shouldRepaint(_DotGridPainter old) => false;
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

class _MainNavigatorState extends State<MainNavigator> with WidgetsBindingObserver {
  int _currentIndex = 1; // Começa na aba central (Licença)
  final AlertService alertService = AlertService();

  final List<Widget> _screens = [
    const AlertsScreen(),
    const LicenseScreen(),
    const SmsScreen(),
  ];

  @override
  void initState() {
    super.initState();

    // Observa mudanças no ciclo de vida do app (foreground/background)
    WidgetsBinding.instance.addObserver(this);

  // 🚀 NOVO: Pede a permissão pro usuário logo que ele abre o app
    FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

    // 🚀 Chama a função de adaptação web/nativa
    registerWebCloseListener(); 
    alertService.startMonitoring();
    // ❌ APAGUEI A LINHA '_setupFirebase();' QUE ESTAVA AQUI!

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  if (message.data['action'] == 'SYNC_ALERTS') {
    
    // 🚀 O PUSH ACABOU DE CHEGAR!
    // Chamamos o serviço de alertas para buscar as novidades agora mesmo
    // sem esperar o cronômetro do polling.
    alertService.forceSync(); 

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

class _AlertsScreenState extends State<AlertsScreen> with WidgetsBindingObserver {
  final AlertService _alertService = AlertService();
  final List<Alert> _listaAlertasTodos = []; // Todos os dados recebidos
  List<Alert> _listaAlertasFiltrados = [];   // Apenas o que passa no filtro
  bool _isCarregando = true;
  
  UserFilters _filtros = UserFilters();

  final AudioPlayer _audioPlayer = AudioPlayer();

  // 🚀 1. VARIÁVEL DO SOM
  bool _isSoundEnabled = true; 
  bool _needsWebAudioInteraction = kIsWeb; // 🚀 Web precisa de interação para ativar o áudio

  // 🚀 NOVO: VARIÁVEL QUE GUARDA QUAL PASSAGEM DEVE PISCAR EM DOURADO
  String? _highlightedTrecho;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    
    _loadSoundPreference(); // 🚀 2. CARREGA PREFERÊNCIA AO ABRIR
    _carregarFiltros();
    _verificarNotificacaoDeAbertura(); // 🚀 NOVO: Checa se o app abriu por um clique
  }

  // 🚀 NOVO: OUVINTE DE CLIQUES (BACKGROUND E FOREGROUND)
  void _verificarNotificacaoDeAbertura() async {
    // 1. Caso o app estava fechado e abriu pelo clique
    final details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp && details.notificationResponse?.payload != null) {
       _ativarBlurDourado(details.notificationResponse!.payload!);
    }

    // 2. Caso o app já estava aberto (minimizou) e o usuário clicou
    _alertService.tapStream.listen((trechoClicado) {
       _ativarBlurDourado(trechoClicado);
    });
  }

  // 🚀 NOVO: ATIVA O DOURADO E DESLIGA DEPOIS DE 6 SEGUNDOS
  void _ativarBlurDourado(String trecho) {
    if (mounted) {
      setState(() => _highlightedTrecho = trecho);
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _highlightedTrecho = null);
      });
    }
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
  // 🚀 ESCUDO ANTI-DUPLICAÇÃO: Só deixa passar o que tiver um ID inédito!
        List<Alert> alertasIneditos = novosAlertas.where((novo) {
          // Verifica se ESSE id já existe na nossa lista principal
          return !_listaAlertasTodos.any((existente) => existente.id == novo.id);
        }).toList();

        // Se o servidor mandou coisas, mas todas eram repetidas, paramos por aqui silenciosamente.
        if (alertasIneditos.isEmpty) return;

        // Filtra APENAS os inéditos com as regras do usuário (Companhia, Origem, Destino)
        List<Alert> novosQuePassaram = alertasIneditos.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();

        setState(() {
          // Insere apenas os inéditos no topo da lista
          _listaAlertasTodos.insertAll(0, alertasIneditos);
          _aplicarFiltrosNaTela(); 
          _isCarregando = false;
        });

        // 🚀 Feedback Sonoro e Visual (Notificação)
        if (novosQuePassaram.isNotEmpty) {
          try {
            if (_isSoundEnabled) {
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
    // Tire o 'const' e use 'final'
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'emissao_vip_v3', // 🚀 CANAL V3 AQUI TAMBÉM
      'Emissões FãMilhas VIP',
      channelDescription: 'Avisos de novas passagens',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon', 
      sound: const RawResourceAndroidNotificationSound('alerta'), // Aqui o const fica só no som
      playSound: _isSoundEnabled, // A sua variável dinâmica brilha aqui!
    );
    
    final NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      id: alerta.id.hashCode,
      title: '✈️ ${alerta.programa} - Nova Oportunidade!',
      body: alerta.trecho != "N/A" ? alerta.trecho : alerta.mensagem,
      notificationDetails: platformChannelSpecifics,
      payload: alerta.trecho, // 🚀 NOVO: CARREGA O RASTREADOR
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
    WidgetsBinding.instance.removeObserver(this);
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

  // 🚀 O GATILHO DE RETORNO (LIFECYCLE)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("📱 App voltou para o primeiro plano! Sincronizando Silenciosamente...");
      // 🚀 FORÇA A ATUALIZAÇÃO DO FEED, MAS SEM TOCAR A SIRENE DE NOVO!
      _alertService.forceSync(silencioso: true); // Correção de sintaxe para _alertService
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold: A estrutura básica de layout da página (como o <body> no HTML).
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        // 🚀 O title agora é uma Column para caber o subtítulo de sincronia
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.radar, color: AppTheme.accent, size: 22),
                const SizedBox(width: 8),
                const Text(
                  "FEED DE EMISSÕES",
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2, fontSize: 18),
                ),
                const Text(
                  "VIP",
                  style: TextStyle(fontWeight: FontWeight.w300, color: AppTheme.accent, letterSpacing: 2, fontSize: 18),
                ),
              ],
            ),
          // 🚀 Use o Singleton diretamente com parênteses: AlertService()
          Text(
            AlertService().lastSyncLabel, 
            style: const TextStyle(fontSize: 10, color: AppTheme.muted),
          )
          ],
        ),
        actions: [
          // 🚀 NOVO BOTÃO DE VOLUME ANIMADO (FURA-BLOQUEIO WEB)
          Builder(
            builder: (context) {
              Widget btn = IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      _isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: _isSoundEnabled ? AppTheme.accent : AppTheme.muted,
                    ),
                    // O Badge Vermelho de Alerta "!"
                    if (_needsWebAudioInteraction)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppTheme.red, 
                            shape: BoxShape.circle
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: const Text(
                            '!', 
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), 
                            textAlign: TextAlign.center
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: "Ligar/Desligar Som",
                onPressed: () {
                  if (_needsWebAudioInteraction) {
                    setState(() => _needsWebAudioInteraction = false);
                    // 🚀 Toca o som para provar ao navegador que o usuário interagiu!
                    _audioPlayer.play(AssetSource('sounds/alerta.mp3')); 
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("🔊 Sistema de áudio desbloqueado com sucesso!"), 
                        backgroundColor: AppTheme.green, 
                        duration: Duration(seconds: 2)
                      )
                    );
                  } else {
                    _toggleSound();
                  }
                },
              );

              // 🚀 Se precisar interagir (Web), aplica a animação de "chacoalhar"
              if (_needsWebAudioInteraction) {
                return btn.animate(onPlay: (controller) => controller.repeat())
                          .shake(hz: 4, curve: Curves.easeInOut, duration: 600.ms)
                          .then(delay: 1500.ms); // Dá uma pausa entre os chacoalhões
              }
              
              return btn;
            },
          ),
          
          // BOTÃO DE FILTROS ORIGINAL (Mantenha o seu botão de filtros aqui embaixo)
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
                    return AlertCard(
                      alerta: alerta,
                      // 🚀 NOVO: AVISA O CARD SE ELE FOI O CLICADO
                      isHighlighted: _highlightedTrecho != null && alerta.trecho.contains(_highlightedTrecho!),
                    );
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
  final bool isHighlighted; // 🚀 NOVO: Recebe a informação se deve piscar
  
  const AlertCard({super.key, required this.alerta, this.isHighlighted = false}); // 🚀 NOVO: Construtor atualizado

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool _isExpanded = false;
  bool _blurCusto = false;
  bool _blurBalcao = false;

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

void _abrirBalcao() async {
    print("🟢 [BALCÃO] Copiando mensagem...");
    
    // 🚀 1. O MOTOR DE CÓPIA (PUXA DIRETO DO SEU MODELO NOVO)
    String mensagemParaCopiar = widget.alerta.mensagemBalcao;
    
    // Fallback de segurança: Se o JSON falhar ou vier "N/A", cria uma mensagem básica pra não quebrar a UX
    if (mensagemParaCopiar == "N/A" || mensagemParaCopiar.isEmpty) {
      print("⚠️ [BALCÃO] Mensagem do balcão não disponível, usando fallback.");
      mensagemParaCopiar = "👋 Olá! Gostaria de cotar a emissão do trecho: ${widget.alerta.trecho}\nCompanhia: ${widget.alerta.programa}";
    }

    // Copia para a Área de Transferência do celular/PC
    await Clipboard.setData(ClipboardData(text: mensagemParaCopiar));
    
    // Mostra o aviso verde de sucesso pro cliente
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📋 Mensagem copiada! Cole no grupo do Balcão."),
          backgroundColor: AppTheme.green,
          duration: Duration(seconds: 3),
        )
      );
    }

    // 🚀 2. O REDIRECIONAMENTO PRO WHATSAPP
    try {
      // 1. Busca a configuração do Gist
      final config = await DiscoveryService().getConfig();
      final String? urlGist = config?.whatsappGroupUrl;

      // 2. Define o link final do grupo
      final String urlFinal = (urlGist != null && urlGist.isNotEmpty) 
          ? urlGist 
          : "https://chat.whatsapp.com/DMyfA6rb7jmJsvCJUVU5vk";

      print("🔗 [WPP] URL DEFINIDA: $urlFinal");

      final Uri uri = Uri.parse(urlFinal);
      
      print("🚀 [WPP] TENTANDO ABRIR O LINK...");
      
      // 3. Abre o WhatsApp com a rota certa dependendo se é Web ou Celular
      await launchUrl(
        uri, 
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      
      print("✅ [WPP] LINK ABERTO COM SUCESSO!");

    } catch (e) {
      print("❌ [WPP] ERRO FATAL AO ABRIR WPP: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao abrir WhatsApp: $e"),
            backgroundColor: AppTheme.red,
          )
        );
      }
    }
  }

  void _emitirComAAgencia() async {
    print("🟢 [AGÊNCIA] Abrindo Link da Agência...");
    
    // 🚀 AGORA ELE LÊ A VARIÁVEL NOVA QUE VOCÊ CRIOU NO ALERT.DART!
    String urlAgencia = widget.alerta.link_agencia;

    // Se a variável nova falhar, tenta ler o link antigo por segurança
    if (urlAgencia == "N/A" || urlAgencia.isEmpty) {
        urlAgencia = widget.alerta.link ?? "";
    }

    if (urlAgencia.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link da Agência não disponível para esta emissão.")));
        return;
    }
    
    final Uri url = Uri.parse(urlAgencia);
    
    try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Não foi possível abrir o link da agência.")));
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

    // 🚀 NOVO: O EFEITO DOURADO VIP (Ativa o glow apenas se clicado)
    BoxShadow blurDourado = widget.isHighlighted 
        ? const BoxShadow(color: Colors.amberAccent, blurRadius: 20, spreadRadius: 2)
        : const BoxShadow(color: Colors.transparent);

    // AnimatedContainer: Um Container que anima suas propriedades automaticamente (como transitions no CSS).
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500), // 🚀 NOVO: Aumentado para 500ms pra transição do dourado ficar mais bonita
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16), // Espaçamento externo
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(12), // Border-radius do CSS
        // 🚀 NOVO: Borda dourada espessa se clicado, normal se não
        border: Border.all(
          color: widget.isHighlighted ? Colors.amberAccent : (_isExpanded ? corPrincipal.withOpacity(0.5) : AppTheme.border),
          width: widget.isHighlighted ? 2.0 : 1.0
        ),
        boxShadow: [
          blurDourado, // 🚀 NOVO: Aplica o Blur
          if (_isExpanded && !widget.isHighlighted) BoxShadow(color: corPrincipal.withOpacity(0.1), blurRadius: 10, spreadRadius: 1)
        ],
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
                            Text(prog, style: TextStyle(color: corPrincipal, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const Text(" • ", style: TextStyle(color: AppTheme.muted)),
                            Text("${widget.alerta.milhas} milhas", style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w400)),
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
                    const Divider(color: AppTheme.border, height: 20), // Linha divisória sutil
                    
                  // Grid de Dados Extraídos (Metadados)
                                      // Envolva a Row com Padding
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0), // 👈 Aqui define a margem das duas pontas
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInfoColumn("IDA", widget.alerta.dataIda),
                        _buildInfoColumn("VOLTA", widget.alerta.dataVolta),
                      AnimatedScale(
                        scale: _blurCusto ? 1.1 : 1.0, // Aumenta 10% no foco
                        duration: const Duration(milliseconds: 200),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _blurCusto ? corPrincipal.withOpacity(0.1) : Colors.transparent, // Fundo sutil
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _blurCusto ? corPrincipal : Colors.transparent), // Borda de foco
                          ),
                          child: _buildInfoColumn("FABRICADO", widget.alerta.valorFabricado),
                        ),
                      ),
                        AnimatedScale(
                          scale: _blurBalcao ? 1.1 : 1.0, // Aumenta 10% no foco
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _blurBalcao ? corPrincipal.withOpacity(0.1) : Colors.transparent, // Fundo sutil
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _blurBalcao ? corPrincipal : Colors.transparent), // Borda de foco
                            ),
                            child: _buildInfoColumn("BALCÃO", widget.alerta.valorBalcao, isHighlight: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16), // Espaçamento entre o grid e a descrição

                  Container(
                      height: 175, // Altura fixa e compacta
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

                  // Botão 1: EMITIR AGORA
                  if (widget.alerta.link != null && widget.alerta.link!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 45,
                        // 1. O GestureDetector envolve o botão para capturar o toque no Mobile
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _blurCusto = true),
                          onTapUp: (_) => setState(() => _blurCusto = false),
                          onTapCancel: () => setState(() => _blurCusto = false),
                          child: ElevatedButton.icon(
                            // 2. O onHover captura o mouse no PC
                            onHover: (hovering) => setState(() => _blurCusto = hovering),
                            onPressed: _abrirLink,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: corPrincipal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 4,
                              shadowColor: corPrincipal.withOpacity(0.4),
                            ),
                            icon: const Icon(Icons.open_in_browser, size: 18),
                            label: const Text("EMITIR COM MILHAS PRÓPRIAS", 
                              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                          ),
                        ),
                      ),
                    ),
                  
                  // Botão 2: EMITIR NO BALCÃO (Com a mensagem copiada para o clipboard)
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      // 1. O GestureDetector envolve o botão
                      child: GestureDetector(
                        onTapDown: (_) => setState(() => _blurBalcao = true),
                        onTapUp: (_) => setState(() => _blurBalcao = false),
                        onTapCancel: () => setState(() => _blurBalcao = false),
                        child: ElevatedButton.icon(
                          // 2. O onHover captura o mouse
                          onHover: (hovering) => setState(() => _blurBalcao = hovering),
                          onPressed: _abrirBalcao,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.esmerald,
                            foregroundColor: AppTheme.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 4,
                            shadowColor: AppTheme.muted.withOpacity(0.4),
                          ),
                          icon: const Icon(Icons.local_atm_rounded, size: 20),
                          label: const Text("EMITIR NO BALCÃO", 
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                      ),
          ),

                    // Botão 3: EMITIR COM FÃMILHASVIP (Novo)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.golden,
                            foregroundColor: AppTheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 4,
                            shadowColor: AppTheme.amber.withOpacity(0.4),
                          ),
                          icon: const Icon(Icons.verified_user_rounded, size: 20),
                          label: const Text("EMITIR COM O FÃMILHASVIP", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                          onPressed: () {
                          _emitirComAAgencia();
                          }
                        )

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
        Text(titulo, style: const TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          valor, 
          style: TextStyle(
            color: isHighlight ? AppTheme.green : Colors.white, 
            fontSize: 13.5, 
            fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w700,
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
    if (!_isMonitoring) {
      // 🚀 1. CHAMA O ESCUDO DE CONSENTIMENTO (As 2 camadas jurídicas)
      ConsentimentoSmsDialog.showIfNeeded(context, () async {
        
        // 🚀 2. SÓ ENTRA AQUI SE O USUÁRIO LEU, MARCOU AS CAIXINHAS E ACEITOU!
        var statusSms = await Permission.sms.status;
        
        if (!statusSms.isGranted) {
          // Pede a permissão real do Android
          var resultado = await Permission.sms.request();
          if (!resultado.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("⚠️ Permissão de SMS negada. Não podemos capturar."),
                  backgroundColor: AppTheme.red,
                )
              );
            }
            return; // Aborta! Não liga o serviço.
          }
        }

        // 🚀 3. PERMISSÃO CONCEDIDA: Liga o motor Kotlin
        try {
          await platform.invokeMethod('startSmsService');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('IS_SMS_MONITORING', true);
          
          if (mounted) setState(() => _isMonitoring = true);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
        }
      });

    } else {
      // 🚀 SE JÁ ESTAVA LIGADO, O USUÁRIO QUER DESLIGAR (Não precisa de termos)
      try {
        await platform.invokeMethod('stopSmsService');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('IS_SMS_MONITORING', false);
        
        if (mounted) setState(() => _isMonitoring = false);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 BLINDAGEM WEB: Se for navegador, mostra uma tela de aviso bonita e bloqueia o acesso nativo.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sms, color: AppTheme.accent, size: 22),
              SizedBox(width: 8),
              Text("SMS", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 2, fontSize: 20)),
              Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: 2, fontSize: 20)),
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
        centerTitle: true,
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
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge, color: AppTheme.accent, size: 22),
            SizedBox(width: 8),
            Text("SESSÃO", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 2, fontSize: 20)),
            Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: 2, fontSize: 20)),
          ],
        ),//centralizar o título
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
                  _buildInfoRow("LICENÇA", _userToken.toUpperCase(), valueColor: AppTheme.accent, isMono: true),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("VÁLIDA ATÉ", _userVencimento, valueColor: _getCorVencimento(_userVencimento)),
                  const Divider(color: AppTheme.border, height: 30),
                  _buildInfoRow("E-MAIL VINCULADO", _userEmail.toLowerCase(), valueColor: AppTheme.muted, size: 12),
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
