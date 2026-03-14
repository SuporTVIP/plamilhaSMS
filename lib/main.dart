import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/theme.dart';
import 'login_screen.dart';
import 'models/alert.dart';
import 'services/alert_service.dart';
import 'services/auth_service.dart';
import 'services/discovery_service.dart';
import 'services/filter_service.dart';
import 'utils/web_highlight.dart';
import 'utils/web_window_manager.dart';
import 'widgets/consentimento_dialog.dart';

// Instância global de Notificações
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

/// Handler de mensagens do Firebase (Push Oculto) - ARQUITETURA 100% PUSH.
///
/// Este método é executado em um isolate separado quando o app está em background ou fechado.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🚨 [FCM-BACKGROUND] ACORDOU O MOTOR INVISÍVEL! Dados recebidos: ${message.data}");

  final String action = message.data['action'] ?? '';
  final String tipo = message.data['tipo'] ?? '';
  
  if (action != 'SYNC_ALERTS' && tipo != 'NOVO_ALERTA') {
    debugPrint("🤷‍♂️ [FCM-BACKGROUND] Push ignorado (não é um alerta de passagem).");
    return;
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final UserFilters filtros = await UserFilters.load();

  final String programa = message.data['programa'] ?? '';
  final String trecho = message.data['trecho'] ?? '';
  final String detalhes = message.data['detalhes'] ?? '';

  debugPrint("🔍 [FCM-RAIO-X] Analisando Voo: $programa | $trecho");

  // 1. Verifica filtros ANTES de gastar qualquer recurso
  if (!filtros.passaNoFiltroBasico(programa, trecho, detalhes: detalhes)) {
    debugPrint("⛔ [FCM-PORTEIRO] BARRADO! O Voo não atende aos critérios do usuário.");
    return;
  }
  debugPrint("✅ [FCM-PORTEIRO] APROVADO! O Voo passou no filtro da tela apagada.");

  // 2. Monta o objeto Alert COMPLETO do payload — sem usar a internet!
  final Alert novoAlerta = Alert.fromPush(message.data);

  // 3. Salva no cache local (ALERTS_CACHE_V2)
  final List<String> cacheRaw = prefs.getStringList('ALERTS_CACHE_V2') ?? [];
  
  // Proteção contra duplicatas
  final bool jaExiste = cacheRaw.any((String raw) {
    try {
      return jsonDecode(raw)['id'] == novoAlerta.id;
    } catch (_) {
      return false;
    }
  });

  if (jaExiste) {
    debugPrint("♻️ [FCM-CACHE] Descartado Silenciosamente. Este voo já existe no banco de dados local.");
    return;
  }

  debugPrint("💾 [FCM-CACHE] Salvando passagem INÉDITA no Cache Local...");
  cacheRaw.insert(0, jsonEncode(novoAlerta.toJson()));
  // Limita o histórico a 100 alertas
  await prefs.setStringList('ALERTS_CACHE_V2', cacheRaw.take(100).toList());

  // 4. Toca a sirene dourada e mostra notificação
  debugPrint("🔔 [FCM-UX] Disparando Sirene Dourada e Notificação visual do Android...");
  try {
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(android: initAndroid),
    );
    
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emissao_vip_v3',
        'Emissões FãMilhasVIP',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('alerta'),
        playSound: true,
        enableVibration: true,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      id: novoAlerta.id.hashCode,
      title: "✈️ Oportunidade: $programa",
      body: trecho,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'emissao_vip_v3',
          'Emissões FãMilhasVIP',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('alerta'),
          playSound: true,
        ),
      ),
      payload: trecho,
    );
    debugPrint("✨ [FCM-UX] Notificação exibida com sucesso!");
  } catch (e) {
    debugPrint("❌ [FCM-UX] Erro fatal ao tentar exibir notificação nativa: $e");
  }
}

/// Ponto de entrada do aplicativo.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Notificações locais (só mobile)
  if (!kIsWeb) {
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
        
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(android: initAndroid),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          AlertService().setPendingHighlight(response.payload!);
          AlertService().registrarToqueNotificacao(response.payload!);
        }
      },
    );
  }

  runApp(const MilhasAlertApp());

  // Web: permissão e token em background
  if (kIsWeb) {
    unawaited(_configurarPushWeb());
    iniciarReceptorWebHighlight((String trecho) {
      AlertService().setPendingHighlight(trecho);
    });
  }
}

/// Configura push web em background.
Future<void> _configurarPushWeb() async {
  try {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    final NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('❌ [WEB] Usuário recusou as notificações.');
      return;
    }

    debugPrint('✅ [WEB] Permissão concedida!');

    final String? webToken = await messaging.getToken(
      vapidKey: "BOsesHNzz8UHyRwiJRZJfd8ZgeA4hmGi_JPDVPKxOXXDN4T92NHlQa4sSi0m-2K_WnS-aQFXmlolAOSsrgKHg8M",
    );

    if (webToken == null || webToken.isEmpty) {
      debugPrint('⚠️ [WEB] Token gerado foi nulo.');
      return;
    }

    debugPrint("🔥 [WEB] TOKEN FCM WEB: $webToken");

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('FCM_TOKEN_WEB', webToken);
    debugPrint("💾 [WEB] Token salvo.");

  } catch (e) {
    debugPrint("⚠️ [WEB] Erro ao configurar push web: $e");
  }
}

/// O root do aplicativo, define o tema e a rota inicial.
class MilhasAlertApp extends StatelessWidget {
  /// Construtor padrão para [MilhasAlertApp].
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

/// Tela de splash cinematográfica que decide o destino inicial do usuário.
class SplashRouter extends StatefulWidget {
  /// Construtor padrão para [SplashRouter].
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> with TickerProviderStateMixin {
  late final AnimationController _ctrlLetterbox;
  late final AnimationController _ctrlLogo;
  late final AnimationController _ctrlGlow;
  late final AnimationController _ctrlExit;

  late final Animation<double> _letterboxTop;
  late final Animation<double> _letterboxBottom;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _glowRadius;
  late final Animation<double> _exitOpacity;

  final AudioPlayer _introPlayer = AudioPlayer();
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _runSequence();
  }

  void _initAnimations() {
    _ctrlLetterbox = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _letterboxTop = Tween<double>(begin: -80.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrlLetterbox, curve: Curves.easeOut));
    _letterboxBottom = Tween<double>(begin: 80.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrlLetterbox, curve: Curves.easeOut));

    _ctrlLogo = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrlLogo, curve: Curves.easeIn));
    _logoScale = Tween<double>(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrlLogo, curve: Curves.easeOutBack));

    _ctrlGlow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _glowRadius = Tween<double>(begin: 8.0, end: 36.0)
        .animate(CurvedAnimation(parent: _ctrlGlow, curve: Curves.easeInOut));

    _ctrlExit = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _exitOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrlExit, curve: Curves.easeIn));
  }

  Future<void> _runSequence() async {
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 200)),
      _ctrlLetterbox.forward(),
    ]);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!kIsWeb) {
      _introPlayer.play(AssetSource('sounds/intro.mp3')).ignore();
    }
    await _ctrlLogo.forward();

    for (int i = 0; i < 2; i++) {
      await _ctrlGlow.forward();
      await _ctrlGlow.reverse();
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final Widget nextScreen = await _resolveNextScreen();
    await _ctrlExit.forward();

    if (mounted && !_navigated) {
      _navigated = true;
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => nextScreen,
            transitionDuration: Duration.zero,
          ),
        );
      }
    }
  }

  Future<Widget> _resolveNextScreen() async {
    final bool firstUse = await AuthService().isFirstUse();
    return firstUse ? const LoginScreen() : const MainNavigator();
  }

  @override
  void dispose() {
    _introPlayer.dispose();
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
        animation: Listenable.merge([_ctrlLetterbox, _ctrlLogo, _ctrlGlow, _ctrlExit]),
        builder: (BuildContext context, Widget? child) {
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
              _buildCenterLogo(),
              _buildLetterboxBars(),
              _buildExitOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenterLogo() {
    return Center(
      child: Opacity(
        opacity: _logoOpacity.value,
        child: Transform.scale(
          scale: _logoScale.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLogoIcon(),
              const SizedBox(height: 28),
              _buildLogoText(),
              const SizedBox(height: 10),
              _buildTagline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoIcon() {
    return Container(
      width: 96,
      height: 96,
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
            child: const Icon(Icons.flight, color: AppTheme.accent, size: 48),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoText() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          "PLAMILHAS",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: [
              Shadow(
                color: AppTheme.accent.withOpacity(0.4),
                blurRadius: _glowRadius.value
              ),
            ],
          ),
        ),
        Text(
          "VIP",
          style: TextStyle(
            color: AppTheme.accent,
            fontSize: 28,
            fontWeight: FontWeight.w300,
            letterSpacing: 6,
            shadows: [
              Shadow(
                color: AppTheme.accent,
                blurRadius: _glowRadius.value * 1.2
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagline() {
    return Text(
      "RADAR DE EMISSÕES VIP",
      style: TextStyle(
        color: Colors.white.withOpacity(0.35),
        fontSize: 10,
        letterSpacing: 4,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Widget _buildLetterboxBars() {
    return Stack(
      children: [
        Positioned(
          top: _letterboxTop.value,
          left: 0,
          right: 0,
          child: Container(height: 80, color: Colors.black),
        ),
        Positioned(
          bottom: _letterboxBottom.value,
          left: 0,
          right: 0,
          child: Container(height: 80, color: Colors.black),
        ),
      ],
    );
  }

  Widget _buildExitOverlay() {
    if (_ctrlExit.value <= 0) return const SizedBox.shrink();
    return Positioned.fill(
      child: Opacity(
        opacity: _exitOpacity.value,
        child: const ColoredBox(color: Colors.black),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeCap = StrokeCap.round;
    const double spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }
  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}
/// Gerencia a navegação por abas (Bottom Navigation Bar).
class MainNavigator extends StatefulWidget {
  /// Construtor padrão para [MainNavigator].
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> with WidgetsBindingObserver {
  int _currentIndex = 1; // Começa na aba central (Licença)
  final AlertService _alertService = AlertService();

  final List<Widget> _screens = const [
    AlertsScreen(),
    LicenseScreen(),
    SmsScreen(),
  ];

  /// Dispara uma notificação local.
  Future<void> _tocarNotificacaoLocal({
    required int idNotificacao, 
    required String titulo,
    required String corpo,
    String? payload,
  }) async {
    await flutterLocalNotificationsPlugin.show(
      id: idNotificacao,
      title: titulo,
      body: corpo,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'emissao_vip_v3',
          'Emissões FãMilhasVIP',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('alerta'),
          playSound: true,
        ),
      ),
      payload: payload,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pede a permissão pro usuário logo que ele abre o app
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    registerWebCloseListener();
    _alertService.startMonitoring();

    if (!kIsWeb) {
      _listenToForegroundPushes();
    }
  }

  void _listenToForegroundPushes() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final String action = message.data['action'] ?? '';
      final String tipo   = message.data['tipo']   ?? '';

      if (action != 'SYNC_ALERTS' && tipo != 'NOVO_ALERTA') return;

      final UserFilters filtros  = await UserFilters.load();
      final String programa = message.data['programa'] ?? '';
      final String trecho   = message.data['trecho']   ?? '';
      final String detalhes = message.data['detalhes'] ?? '';

      if (!filtros.passaNoFiltroBasico(programa, trecho, detalhes: detalhes)) {
        debugPrint("⛔ [FOREGROUND] Push bloqueado pelos filtros.");
        return;
      }

      final Alert novoAlerta = Alert.fromPush(message.data);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cacheRaw = prefs.getStringList('ALERTS_CACHE_V2') ?? [];

      final bool jaExiste = cacheRaw.any((String raw) {
        try { return jsonDecode(raw)['id'] == novoAlerta.id; } catch (_) { return false; }
      });

      if (!jaExiste) {
        cacheRaw.insert(0, jsonEncode(novoAlerta.toJson()));
        await prefs.setStringList('ALERTS_CACHE_V2', cacheRaw.take(100).toList());
        debugPrint("💾 [FOREGROUND] Alert salvo no cache: ${novoAlerta.trecho}");
      }

      await _tocarNotificacaoLocal(
        idNotificacao: novoAlerta.id.hashCode,
        titulo: "✈️ Oportunidade: $programa",
        corpo: trecho,
        payload: trecho,
      );

      _alertService.carregarDoCache();
      debugPrint("✅ [FOREGROUND] Feed atualizado via cache.");
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
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.muted,
        currentIndex: _currentIndex,
        onTap: (int index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.flight_takeoff), label: "Alertas"),
          BottomNavigationBarItem(icon: Icon(Icons.badge), label: "Licença"),
          BottomNavigationBarItem(icon: Icon(Icons.sms), label: "SMS"),
        ],
      ),
    );
  }
}

/// Exibe a lista de oportunidades de milhas em tempo real.
class AlertsScreen extends StatefulWidget {
  /// Construtor padrão para [AlertsScreen].
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with WidgetsBindingObserver {
  final AlertService _alertService = AlertService();
  final List<Alert> _listaAlertasTodos = [];
  List<Alert> _listaAlertasFiltrados = [];
  bool _isCarregando = true;
  
  UserFilters _filtros = UserFilters();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isSoundEnabled = true; 
  bool _needsWebAudioInteraction = kIsWeb;
  String? _highlightedTrecho;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadSoundPreference();
    _carregarFiltros();
    _verificarNotificacaoDeAbertura(); 
  }

  void _verificarNotificacaoDeAbertura() async {
    try {
      final NotificationAppLaunchDetails? details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      if (details != null &&
          details.didNotificationLaunchApp &&
          details.notificationResponse?.payload != null) {
        final String payload = details.notificationResponse!.payload!;
        debugPrint("👆 [UX-COLD] Cold Start detectado! Enfileirando: $payload");
        _alertService.setPendingHighlight(payload);
        WidgetsBinding.instance.addPostFrameCallback((_) => _drenaFilaDourado());
      }
    } catch (e) {
      debugPrint("⚠️ [UX-COLD] Erro ao ler getNotificationAppLaunchDetails: $e");
    }

    _alertService.tapStream.listen((String trechoClicado) {
      debugPrint("👆 [UX-WARM] Tap recebido via stream: $trechoClicado");
      _ativarBlurDourado(trechoClicado);
    });
  }

  void _drenaFilaDourado() {
    while (_alertService.pendingHighlightCount > 0) {
      final String? trecho = _alertService.consumePendingHighlight();
      if (trecho != null && mounted) {
        debugPrint("✨ [UI-FILA] Drenando destaque: $trecho (${_alertService.pendingHighlightCount} restantes)");
        _ativarBlurDourado(trecho);
      }
    }
  }

  void _ativarBlurDourado(String trecho) {
    if (mounted) {
      final String trechoNormalizado = trecho.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      debugPrint("✨ [UI-UX] Dourado ativado para ID normalizado: $trechoNormalizado");
      
      setState(() => _highlightedTrecho = trechoNormalizado); 
      
      Future<void>.delayed(const Duration(seconds: 15), () {
        if (mounted) setState(() => _highlightedTrecho = null);
      });
    }
  }

  Future<void> _carregarFiltros() async {
    _filtros = await UserFilters.load();
    _iniciarMotorDeTracao();
  }

  Future<void> _loadSoundPreference() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isSoundEnabled = prefs.getBool('SOUND_ENABLED') ?? true;
      });
    }
  }

  Future<void> _toggleSound() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
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

  void _iniciarMotorDeTracao() {
    debugPrint("🚀 [UI-MOTOR] Iniciando Motor de Tração e escutando Stream...");
    _alertService.startMonitoring();

    _alertService.alertStream.listen((List<Alert> novosAlertas) async {
      if (mounted) {
        debugPrint("📥 [UI-MOTOR] O Serviço enviou ${novosAlertas.length} alertas recém-chegados.");

        final List<Alert> alertasIneditos = novosAlertas.where((Alert novo) {
          final bool repetido = _listaAlertasTodos.any((Alert existente) => existente.id == novo.id);
          if (repetido) debugPrint("♻️ [UI-MOTOR] Descartado: ${novo.trecho}");
          return !repetido;
        }).toList();

        if (alertasIneditos.isNotEmpty) {
          debugPrint("🌟 [UI-MOTOR] ${alertasIneditos.length} alertas INÉDITOS!");

          setState(() {
            _listaAlertasTodos.insertAll(0, alertasIneditos);
            _aplicarFiltrosNaTela();
            _isCarregando = false;
          });
        } else {
          debugPrint("🛑 [UI-MOTOR] Todos já estavam na tela.");
          if (_isCarregando) setState(() => _isCarregando = false);
        }

        if (_alertService.pendingHighlightCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _drenaFilaDourado());
        }
      }
    });

    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted && _isCarregando) {
        debugPrint("⏱️ [UI-MOTOR] Timeout atingido. Removendo indicador.");
        setState(() => _isCarregando = false);
      }
    });
  }

  void _aplicarFiltrosNaTela() {
    setState(() {
      _listaAlertasFiltrados = _listaAlertasTodos.where((Alert a) => _filtros.alertaPassaNoFiltro(a)).toList();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertService.stopMonitoring();
    super.dispose();
  }

  void _abrirPainelFiltros() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => FilterBottomSheet(
        filtrosAtuais: _filtros,
        onFiltrosSalvos: (UserFilters novosFiltros) {
          _filtros = novosFiltros;
          _aplicarFiltrosNaTela();
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 App abriu! Lendo dados locais...");
      _alertService.carregarDoCache().then((_) {
        if (_alertService.pendingHighlightCount > 0 && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _drenaFilaDourado());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar, color: AppTheme.accent, size: 22),
              SizedBox(width: 8),
              Text(
                "FEED DE EMISSÕES",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                  fontSize: 18
                ),
              ),
              Text(
                "VIP",
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: AppTheme.accent,
                  letterSpacing: 2,
                  fontSize: 18
                ),
              ),
            ],
          ),
          Text(
            _alertService.lastSyncLabel,
            style: const TextStyle(fontSize: 10, color: AppTheme.muted),
          )
        ],
      ),
      actions: [
        _buildSoundButton(),
        _buildFilterButton(),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSoundButton() {
    return Builder(
      builder: (BuildContext context) {
        Widget btn = IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                _isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: _isSoundEnabled ? AppTheme.accent : AppTheme.muted,
              ),
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
              _audioPlayer.play(AssetSource('sounds/alerta.mp3'));

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("🔊 Sistema de áudio desbloqueado!"),
                  backgroundColor: AppTheme.green,
                  duration: Duration(seconds: 2)
                )
              );
            } else {
              _toggleSound();
            }
          },
        );

        if (_needsWebAudioInteraction) {
          return btn.animate(onPlay: (AnimationController controller) => controller.repeat())
                    .shake(hz: 4, curve: Curves.easeInOut, duration: 600.ms)
                    .then(delay: 1500.ms);
        }

        return btn;
      },
    );
  }

  Widget _buildFilterButton() {
    final bool hasActiveFilters = _filtros.origens.isNotEmpty ||
                                  _filtros.destinos.isNotEmpty ||
                                  !_filtros.azulAtivo ||
                                  !_filtros.latamAtivo ||
                                  !_filtros.smilesAtivo;
    return IconButton(
      icon: Icon(
        Icons.tune,
        color: hasActiveFilters ? AppTheme.green : AppTheme.accent
      ),
      tooltip: "Filtros",
      onPressed: _abrirPainelFiltros,
    );
  }

  Widget _buildBody() {
    if (_isCarregando) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }

    if (_listaAlertasFiltrados.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flight, size: 64, color: AppTheme.border),
            const SizedBox(height: 16),
            const Text("Nenhuma emissão encontrada.", style: TextStyle(color: AppTheme.muted)),
            const Text("Verifique seus filtros ou aguarde.", style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _listaAlertasFiltrados.length,
      itemBuilder: (BuildContext context, int index) {
        final Alert alerta = _listaAlertasFiltrados[index];
        final String trechoCardNormalizado = alerta.trecho.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

        return AlertCard(
          alerta: alerta,
          isHighlighted: _highlightedTrecho != null &&
                         trechoCardNormalizado.contains(_highlightedTrecho!),
        );
      },
    );
  }
}
/// Exibe as informações de um único alerta em um card expansível.
class AlertCard extends StatefulWidget {
  /// O alerta a ser exibido.
  final Alert alerta;
  
  /// Indica se o card deve ser destacado visualmente.
  final bool isHighlighted;

  /// Construtor padrão para [AlertCard].
  const AlertCard({
    super.key,
    required this.alerta,
    this.isHighlighted = false
  });

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool _isExpanded = false;
  bool _blurCusto = false;
  bool _blurBalcao = false;
  bool _blurAgencia = false;
 
  /// Tenta abrir o link de emissão no navegador externo.
  Future<void> _abrirLink() async {
    if (widget.alerta.link == null || widget.alerta.link!.isEmpty) return;
    final Uri url = Uri.parse(widget.alerta.link!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível abrir o link."))
        );
      }
    }
  }

  /// Copia a mensagem do balcão e tenta abrir o grupo de WhatsApp.
  Future<void> _abrirBalcao() async {
    String mensagemParaCopiar = widget.alerta.mensagemBalcao;
    
    if (mensagemParaCopiar == "N/A" || mensagemParaCopiar.isEmpty) {
      mensagemParaCopiar = "👋 Olá! Gostaria de cotar a emissão do trecho: ${widget.alerta.trecho}\nCompanhia: ${widget.alerta.programa}";
    }

    await Clipboard.setData(ClipboardData(text: mensagemParaCopiar));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📋 Mensagem copiada! Cole no grupo do Balcão."),
          backgroundColor: AppTheme.green,
          duration: Duration(seconds: 3),
        )
      );
    }

    try {
      final DiscoveryConfig? config = await DiscoveryService().getConfig();
      final String? urlGist = config?.whatsappGroupUrl;
      final String urlFinal = (urlGist != null && urlGist.isNotEmpty) 
          ? urlGist 
          : "https://chat.whatsapp.com/DMyfA6rb7jmJsvCJUVU5vk";

      final Uri uri = Uri.parse(urlFinal);
      await launchUrl(
        uri, 
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
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

  /// Tenta abrir o link de emissão com a agência.
  Future<void> _emitirComAAgencia() async {
    String urlAgencia = widget.alerta.linkAgencia;

    if (urlAgencia == "N/A" || urlAgencia.isEmpty) {
      urlAgencia = widget.alerta.link ?? "";
    }

    if (urlAgencia.isEmpty) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Link da Agência não disponível."))
        );
      }
      return;
    }
    
    final Uri url = Uri.parse(urlAgencia);
    
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível abrir o link da agência."))
        );
      }
    }
  }

  /// Formata strings de dinheiro vindas do JS que estão com casas decimais infinitas
  String _formatarDecimal(String valorOriginal) {
    if (valorOriginal == "N/A" || valorOriginal == "0" || valorOriginal.isEmpty) {
      return valorOriginal;
    }
    try {
      // Pega apenas números e o ponto/vírgula
      String limpo = valorOriginal.replaceAll(RegExp(r'[^\d.,]'), '');
      
      // Converte vírgula pra ponto para o Dart conseguir calcular
      limpo = limpo.replaceAll(',', '.');
      
      double numero = double.parse(limpo);
      
      // Trava em 2 casas decimais e devolve a vírgula (Padrão BR)
      return numero.toStringAsFixed(2).replaceAll('.', ',');
    } catch (e) {
      return valorOriginal; // Fallback: se não for número, devolve como chegou
    }
  }

  @override
  Widget build(BuildContext context) {
    final String prog = widget.alerta.programa.toUpperCase();
    Color corPrincipal = AppTheme.accent;
    Color corFundo = AppTheme.card;
    
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

    final BoxShadow blurDourado = widget.isHighlighted
        ? const BoxShadow(color: Colors.amberAccent, blurRadius: 20, spreadRadius: 2)
        : const BoxShadow(color: Colors.transparent);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isHighlighted
              ? Colors.amberAccent
              : (_isExpanded ? corPrincipal.withOpacity(0.5) : AppTheme.border),
          width: widget.isHighlighted ? 2.0 : 1.0
        ),
        boxShadow: [
          blurDourado,
          if (_isExpanded && !widget.isHighlighted)
            BoxShadow(color: corPrincipal.withOpacity(0.1), blurRadius: 10, spreadRadius: 1)
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(corPrincipal, prog),
            if (_isExpanded) _buildDetails(corPrincipal),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color corPrincipal, String prog) {
    final String horaFormatada = "${widget.alerta.data.hour.toString().padLeft(2, '0')}:${widget.alerta.data.minute.toString().padLeft(2, '0')}";

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: corPrincipal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)
            ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildDetails(Color corPrincipal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppTheme.border, height: 20),
          _buildInfoGrid(corPrincipal),
          const SizedBox(height: 12),
          _buildDescriptionBox(),
          const SizedBox(height: 16),
          _buildActionButtons(corPrincipal),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(Color corPrincipal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // IDA e VOLTA sem hover — só texto estático
          _buildInfoColumn("IDA",   widget.alerta.dataIda),
          _buildInfoColumn("VOLTA", widget.alerta.dataVolta),
          // 3 valores com zoom + crossfade de taxas
          _buildValueWithToast(
            "FABRICADO", widget.alerta.valorFabricado,
            corPrincipal, _blurCusto,
            (bool v) => setState(() => _blurCusto = v),
          ),
          _buildValueWithToast(
            "BALCÃO", widget.alerta.valorBalcao,
            AppTheme.esmerald, _blurBalcao,
            (bool v) => setState(() => _blurBalcao = v),
          ),
          _buildValueWithToast(
            "AGÊNCIA", widget.alerta.valorEmissao,
            AppTheme.golden, _blurAgencia,
            (bool v) => setState(() => _blurAgencia = v),
          ),
        ],
      ),
    );
  }

  Widget _buildValueWithToast(
    String label, String value, Color color,
    bool isFocused, Function(bool) onFocusChanged,
  ) {
    return MouseRegion(
      onEnter: (_) => onFocusChanged(true),
      onExit:  (_) => onFocusChanged(false),
      child: GestureDetector(
        onTapDown:   (_) => onFocusChanged(true),
        onTapUp:     (_) => onFocusChanged(false),
        onTapCancel: ()  => onFocusChanged(false),
        child: Padding(
          // Mantém o mesmo alinhamento das colunas IDA e VOLTA
          padding: const EdgeInsets.symmetric(vertical: 4), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label fixo (Ex: FABRICADO)
              Text(label, style: const TextStyle(
                color: AppTheme.muted, fontSize: 10,
                letterSpacing: 1, fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 4),
              
              // 🚀 O zoom puro direto nos números, sem "caixa" em volta
             SizedBox(
                height: 28, // Altura fixa pra não empurrar o layout pra baixo
                child: AnimatedScale(
                  scale: isFocused ? 1.08 : 1.0, // Retornei o zoom para 1.15
                  alignment: Alignment.centerLeft, // Cresce da esquerda pra direita
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack, // Dá um micro "pulo" suave no final
                  child: Padding( // 🚀 FALTAVA O "child:" BEM AQUI!
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(value, style: TextStyle(
                      color: color, fontSize: 11.5, fontWeight: FontWeight.w900,
                    )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionBox() {
    return Container(
      height: 175,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: SelectableText(
          (widget.alerta.detalhes.isNotEmpty && widget.alerta.detalhes != "N/A")
              ? widget.alerta.detalhes
              : widget.alerta.mensagem,
          style: const TextStyle(color: AppTheme.text, fontSize: 11, height: 1.4),
        ),
      ),
    );
  }

 Widget _buildActionButtons(Color corPrincipal) {
    return Column(
      children: [
        if (widget.alerta.link != null && widget.alerta.link!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildActionButton(
              "EMITIR COM MILHAS PRÓPRIAS",
              Icons.open_in_browser,
              corPrincipal,
              _abrirLink,
              showTax: true,
              // 🚀 LIGAÇÃO 1: Foca no FABRICADO
              onHoverChanged: (bool val) => setState(() => _blurCusto = val),
            ),
          ),
        _buildActionButton(
          "EMITIR NO BALCÃO",
          Icons.local_atm_rounded,
          AppTheme.esmerald,
          _abrirBalcao,
          showTax: true,
          // 🚀 LIGAÇÃO 2: Foca no BALCÃO
          onHoverChanged: (bool val) => setState(() => _blurBalcao = val),
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          "EMITIR COM FÃMILHASVIP",
          Icons.verified_user_rounded,
          AppTheme.golden,
          _emitirComAAgencia,
          textColor: AppTheme.surface,
          shadowColor: AppTheme.amber,
          showTax: true,
          // 🚀 LIGAÇÃO 3: Foca na AGÊNCIA
          onHoverChanged: (bool val) => setState(() => _blurAgencia = val),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label, IconData icon, Color color, VoidCallback onPressed, {
    Color? textColor, Color? shadowColor, bool showTax = false,
    ValueChanged<bool>? onHoverChanged, // 🚀 NOVO: Recebendo o Callback
  }) {
    final bool taxaExiste = widget.alerta.taxas != 'N/A' &&
        widget.alerta.taxas != '0' && widget.alerta.taxas.isNotEmpty;
    final Color taxColor  = taxaExiste ? color : Colors.redAccent;
    final String taxLabel = taxaExiste
        ? "Taxas de R\$ ${_formatarDecimal(widget.alerta.taxas)} inclusas"
        : 'Taxas aeroportuárias não inclusas';
    final IconData taxIcon = taxaExiste
        ? Icons.check_circle_outline
        : Icons.info_outline;

    return _HoverButton(
      onHoverChanged: onHoverChanged, // 🚀 NOVO: Passando o Callback para comunicação
      builder: (bool hovered) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toast desliza de cima para baixo com AnimatedSize
          if (showTax) AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: hovered
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: hovered ? 1.0 : 0.0,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      decoration: BoxDecoration(
                        color: taxColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: taxColor.withOpacity(0.35), width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(taxIcon, size: 13, color: taxColor),
                          const SizedBox(width: 6),
                          Text(taxLabel, style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: taxColor, letterSpacing: 0.2,
                          )),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          ),
          // Botão principal
          SizedBox(
            width: double.infinity,
            height: 45,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: textColor ?? Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: hovered ? 6 : 4,
                shadowColor: (shadowColor ?? color).withOpacity(0.4),
              ),
              icon: Icon(icon, size: 18),
              label: Text(label, style: const TextStyle(
                fontWeight: FontWeight.bold, letterSpacing: 1,
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String titulo, String valor, {Color? corValor}) {
    final Color corExibicao = corValor ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 5.4), // para evitar que textos longos encostem no próximo item
            child:
          Text(
            valor, 
            style: TextStyle(
              color: corExibicao,
              fontSize: 11.5, 
              fontWeight: corValor != null ? FontWeight.w900 : FontWeight.w700,
            )
          ),
          ),
        ],
      ),
    );
  }
}
class _HoverButton extends StatefulWidget {
  final Widget Function(bool isHovered) builder;
  final ValueChanged<bool>? onHoverChanged; // 🚀 NOVO: Callback de comunicação
  
  const _HoverButton({required this.builder, this.onHoverChanged});
  
  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _h = false;

  void _updateState(bool val) {
    if (_h != val) {
      setState(() => _h = val);
      if (widget.onHoverChanged != null) widget.onHoverChanged!(val);
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _updateState(true),
    onExit:  (_) => _updateState(false),
    child: GestureDetector(
      onTapDown:   (_) => _updateState(true),
      onTapUp:     (_) => _updateState(false),
      onTapCancel: ()  => _updateState(false),
      child: widget.builder(_h),
    ),
  );
}

/// Tela de conexão com SMS (exclusivo para Android).
class SmsScreen extends StatefulWidget {
  /// Construtor padrão para [SmsScreen].
  const SmsScreen({super.key});

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  static const MethodChannel _platform = MethodChannel('com.suportvips.milhasalert/sms_control');
  bool _isMonitoring = false;
  List<Map<String, String>> _smsHistory = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _carregarEstadoBotao();
    _loadHistory();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadHistory());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregarEstadoBotao() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isMonitoring = prefs.getBool('IS_SMS_MONITORING') ?? false;
    });
  }

  Future<void> _loadHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final String historyStr = prefs.getString('SMS_HISTORY') ?? '[]';
    try {
      final List<dynamic> decoded = jsonDecode(historyStr);
      if (mounted) {
        setState(() {
          _smsHistory = decoded.map((dynamic e) => {
            "remetente": e["remetente"].toString(),
            "mensagem": e["mensagem"].toString(),
            "hora": e["hora"].toString(),
          }).toList().reversed.toList();
        });
      }
    } catch(e) {
      debugPrint("Erro ao carregar histórico SMS: $e");
    }
  }

  Future<void> _toggleMonitoring() async {
    if (!_isMonitoring) {
      ConsentimentoSmsDialog.showIfNeeded(context, () async {
        final PermissionStatus statusSms = await Permission.sms.status;
        
        if (!statusSms.isGranted) {
          final PermissionStatus resultado = await Permission.sms.request();
          if (!resultado.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("⚠️ Permissão de SMS negada."),
                  backgroundColor: AppTheme.red,
                )
              );
            }
            return;
          }
        }

        try {
          await _platform.invokeMethod('startSmsService');
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('IS_SMS_MONITORING', true);
          
          if (mounted) setState(() => _isMonitoring = true);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
        }
      });

    } else {
      try {
        await _platform.invokeMethod('stopSmsService');
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('IS_SMS_MONITORING', false);
        
        if (mounted) setState(() => _isMonitoring = false);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebBlockingScreen();

    return Scaffold(
      appBar: _buildAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildToggleButton(),
            const SizedBox(height: 24),
            _buildHistoryHeader(),
            const SizedBox(height: 10),
            _buildHistoryList(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
    );
  }

  Widget _buildWebBlockingScreen() {
    return Scaffold(
      appBar: _buildAppBar(),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phonelink_erase, size: 80, color: AppTheme.border),
              SizedBox(height: 20),
              Text("Função Exclusiva Mobile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              SizedBox(height: 10),
              Text(
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

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: !_isMonitoring ? AppTheme.red.withOpacity(0.3) : AppTheme.green.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: !_isMonitoring ? AppTheme.red.withOpacity(0.05) : AppTheme.green.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 5
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
           .shimmer(duration: 2.seconds, color: Colors.white24),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
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
    );
  }

  Widget _buildToggleButton() {
    return SizedBox(
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
    );
  }

  Widget _buildHistoryHeader() {
    return const Row(
      children: [
        Icon(Icons.history, color: AppTheme.muted, size: 18),
        SizedBox(width: 8),
        Text("ÚLTIMOS SMS CAPTURADOS", style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 11)),
      ],
    );
  }

  Widget _buildHistoryList() {
    return Expanded(
      child: _smsHistory.isEmpty
      ? const Center(
          child: Text("Nenhum SMS interceptado ainda.", style: TextStyle(color: AppTheme.muted, fontSize: 12))
        )
      : ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: _smsHistory.length,
          itemBuilder: (BuildContext context, int index) {
            final Map<String, String> sms = _smsHistory[index];
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
    );
  }
}

/// Tela de informações da licença do usuário.
class LicenseScreen extends StatefulWidget {
  /// Construtor padrão para [LicenseScreen].
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

  Future<void> _inicializarSistema() async {
    setState(() => _statusConexao = "Validando Licença...");
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
        _statusConexao = (status == AuthStatus.autorizado) ? "Serviço Ativo" : "⛔ BLOQUEADO";
      });
    }
  }

  Future<void> _fazerLogoff() async {
    setState(() => _isSaindo = true);
    await _auth.logout();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const SplashRouter()));
    }
  }

  Color _getCorVencimento(String dataVencimentoStr) {
    if (dataVencimentoStr == "..." || dataVencimentoStr == "N/A") return AppTheme.muted;

    try {
      final List<String> partes = dataVencimentoStr.split('/');
      if (partes.length != 3) return AppTheme.muted;

      final DateTime validade = DateTime(int.parse(partes[2]), int.parse(partes[1]), int.parse(partes[0]));
      final DateTime hoje = DateTime.now();
      final DateTime hojeApenasData = DateTime(hoje.year, hoje.month, hoje.day);
      
      final int diasRestantes = validade.difference(hojeApenasData).inDays;

      if (diasRestantes <= 3) {
        return AppTheme.red;
      } else if (diasRestantes <= 7) {
        return AppTheme.yellow;
      } else {
        return AppTheme.green;
      }
    } catch (e) {
      return AppTheme.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildInfoGrid(),
            const SizedBox(height: 30),
            _buildLogoutButton(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge, color: AppTheme.accent, size: 22),
          SizedBox(width: 8),
          Text("SESSÃO", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 2, fontSize: 20)),
          Text("VIP", style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: 2, fontSize: 20)),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.refresh, color: AppTheme.muted), onPressed: _inicializarSistema)
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isBloqueado ? AppTheme.red.withOpacity(0.3) : AppTheme.green.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _isBloqueado ? AppTheme.red.withOpacity(0.05) : AppTheme.green.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 5
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
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
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
    );
  }

  Widget _buildInfoGrid() {
    return Container(
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
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
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

/// Modal para configuração de filtros de aeroportos e companhias.
class FilterBottomSheet extends StatefulWidget {
  /// Filtros atuais.
  final UserFilters filtrosAtuais;

  /// Callback disparado ao salvar os filtros.
  final Function(UserFilters) onFiltrosSalvos;

  /// Construtor padrão para [FilterBottomSheet].
  const FilterBottomSheet({super.key, required this.filtrosAtuais, required this.onFiltrosSalvos});

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  final TextEditingController _origensController = TextEditingController();
  final TextEditingController _destinosController = TextEditingController();
  final FocusNode _origensFocus = FocusNode();
  final FocusNode _destinosFocus = FocusNode();

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
      origens: List<String>.from(widget.filtrosAtuais.origens),
      destinos: List<String>.from(widget.filtrosAtuais.destinos),
    );
    _carregarAeroportos();
  }

  @override
  void dispose() {
    _origensController.dispose();
    _destinosController.dispose();
    _origensFocus.dispose();
    _destinosFocus.dispose();
    super.dispose();
  }

  Future<void> _carregarAeroportos() async {
    final List<String> list = await AeroportoService().getAeroportos();
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
        top: 20,
        left: 20,
        right: 20,
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
            _buildHandle(),
            const SizedBox(height: 20),
            _buildHeader(),
            const SizedBox(height: 24),
            _buildCompanySwitches(),
            const Divider(color: AppTheme.border, height: 30),
            _buildLocationFilters(),
            const SizedBox(height: 30),
            _buildApplyButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: const BoxDecoration(
          color: AppTheme.border,
          borderRadius: BorderRadius.all(Radius.circular(10))
        )
      )
    );
  }

  Widget _buildHeader() {
    return const Row(
      children: [
        Icon(Icons.radar, color: AppTheme.green),
        SizedBox(width: 10),
        Text("FILTRAGEM AVANÇADA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white)),
      ],
    );
  }

  Widget _buildCompanySwitches() {
    return Column(
      children: [
        _buildSwitch("LATAM", const Color(0xFFF43F5E), _tempFiltros.latamAtivo, (bool val) => setState(() => _tempFiltros.latamAtivo = val)),
        _buildSwitch("SMILES", const Color(0xFFF59E0B), _tempFiltros.smilesAtivo, (bool val) => setState(() => _tempFiltros.smilesAtivo = val)),
        _buildSwitch("AZUL", const Color(0xFF38BDF8), _tempFiltros.azulAtivo, (bool val) => setState(() => _tempFiltros.azulAtivo = val)),
      ],
    );
  }

  Widget _buildSwitch(String label, Color activeColor, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      activeColor: activeColor,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildLocationFilters() {
    if (_isLoadingAeros) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }
    return Column(
      children: [
        _buildAutocompleteChips("Origens", _tempFiltros.origens, _origensController, _origensFocus),
        const SizedBox(height: 20),
        _buildAutocompleteChips("Destinos", _tempFiltros.destinos, _destinosController, _destinosFocus),
      ],
    );
  }

  Widget _buildApplyButton() {
    return SizedBox(
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
          if(mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildAutocompleteChips(String titulo, List<String> listaSelecionados, TextEditingController controller, FocusNode focusNode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: const TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: listaSelecionados.map((String item) {
            return Chip(
              label: Text(item, style: const TextStyle(fontSize: 12, color: Colors.white)),
              backgroundColor: AppTheme.card,
              deleteIcon: const Icon(Icons.close, size: 16, color: AppTheme.red),
              onDeleted: () => setState(() => listaSelecionados.remove(item)),
            );
          }).toList(),
        ),
        if (listaSelecionados.isNotEmpty) const SizedBox(height: 10),
        Autocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
            return _todosAeroportos.where((String aeroporto) =>
              aeroporto.toLowerCase().contains(textEditingValue.text.toLowerCase()) && 
              !listaSelecionados.contains(aeroporto)
            );
          },
          onSelected: (String selecao) {
           setState(() {
              listaSelecionados.add(selecao);
              controller.clear();
            });
          },
          fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
            return TextField(
              controller: fieldTextEditingController, 
              focusNode: fieldFocusNode, 
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Adicionar $titulo...",
                hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: AppTheme.muted, size: 20),
                filled: true,
                fillColor: AppTheme.bg,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accent)),
                suffixIcon: fieldTextEditingController.text.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => fieldTextEditingController.clear())
                  : null,
              ),
              onSubmitted: (String value) {
                if (value.trim().isNotEmpty && !listaSelecionados.contains(value.toUpperCase())) {
                  setState(() {
                    listaSelecionados.add(value.toUpperCase());
                    fieldTextEditingController.clear();
                    fieldFocusNode.requestFocus();
                  });
                }
              },
            );
          },
          optionsViewBuilder: (BuildContext context, Function(String) onSelected, Iterable<String> options) {
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
                        onTap: () => onSelected(option),
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