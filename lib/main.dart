import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:share_plus/share_plus.dart'; // 🚀 NOVO IMPORT
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:PlamilhaSVIP/utils/web_stub.dart'
    if (dart.library.html) 'dart:html'
    as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // 🚀 PODE COLOCAR AQUI SEM MEDO
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
//import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
const String _fcmTokenMobilePrefsKey = 'FCM_TOKEN_MOBILE';

Future<void> _sincronizarTokenPushMobileAtual() async {
  if (kIsWeb) return;

  try {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    final String? token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[PUSH] Token FCM mobile indisponivel para sincronizacao.');
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String tokenAnterior = prefs.getString(_fcmTokenMobilePrefsKey) ?? '';
    await prefs.setString(_fcmTokenMobilePrefsKey, token);

    if (tokenAnterior != token) {
      debugPrint('[PUSH] Token FCM mobile atualizado localmente.');
    }

    await AuthService().sincronizarTokenPushAutorizadoAtual();
  } catch (e) {
    debugPrint('[PUSH] Falha ao sincronizar token mobile atual: $e');
  }
}

/// Handler de mensagens do Firebase (Push Oculto) - ARQUITETURA 100% PUSH.
///
/// Este método é executado em um isolate separado quando o app está em background ou fechado.
// Handler de toque em notificação quando app está em background.
// flutter_local_notifications v12+ roteia para cá, não para onDidReceiveNotificationResponse.
// OBRIGATÓRIO ser top-level (não pode ser método de classe).
@pragma('vm:entry-point')
void _onBackgroundNotificationTap(NotificationResponse response) {
  if (response.payload != null && response.payload!.isNotEmpty) {
    debugPrint('👆 [BG-TAP] Toque em background: \${response.payload}');
    AlertService().setPendingHighlight(response.payload!);
    AlertService().registrarToqueNotificacao(response.payload!);
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
    "🚨 [FCM-BG] ACORDOU O MOTOR INVISÍVEL! Dados recebidos: ${message.data}",
  );

  final String action = message.data['action'] ?? '';
  final String tipo = message.data['tipo'] ?? '';

  if (action != 'SYNC_ALERTS' && tipo != 'NOVO_ALERTA') {
    debugPrint(
      "🤷‍♂️ [FCM-BACKGROUND] Push ignorado (não é um alerta de passagem).",
    );
    return;
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  final String programa = message.data['programa'] ?? '';
  final String trecho = message.data['trecho'] ?? '';
  final String detalhes = message.data['detalhes'] ?? '';

  debugPrint("🔍 [FCM-RAIO-X] Analisando Voo: $programa | $trecho");

  // =====================================================================
  // 🚀 PASSO 1 E 2: SALVAR PRIMEIRO (A Fonte da Verdade)
  // =====================================================================

  // Monta o objeto Alert COMPLETO do payload — sem usar a internet!
  final Alert novoAlerta = Alert.fromPush(message.data);

  // Salva no cache local (ALERTS_CACHE_V2)
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
    debugPrint(
      "♻️ [FCM-CACHE] Descartado Silenciosamente. Este voo já existe no banco de dados local.",
    );
  } else {
    // 💾 MÁGICA: Salva no cache independente do filtro!
    debugPrint("💾 [FCM-CACHE] Salvando passagem INÉDITA no Cache Local...");
    cacheRaw.insert(0, jsonEncode(novoAlerta.toJson()));
    await prefs.setStringList('ALERTS_CACHE_V2', cacheRaw.take(100).toList());

    // Grava a data para a limpeza diária em carregarDoCache()
    await prefs.setString(
      'CACHE_DATE_V2',
      DateTime.now().toIso8601String().split('T')[0],
    );
  }

  // =====================================================================
  // 🚀 PASSO 3: O PORTEIRO (Decide se toca a sirene e mostra no celular)
  // =====================================================================

  final UserFilters filtros = await UserFilters.load();

  // Verifica filtros APÓS ter garantido que o dado está salvo
  if (!filtros.passaNoFiltroBasico(
    programa,
    trecho,
    detalhes: detalhes,
    contexto: 'fcm-background',
  )) {
    debugPrint(
      "⛔ [FCM-PORTEIRO] BARRADO! O Voo não atende aos critérios do usuário (Mas já está salvo).",
    );
    return; // 🛑 Aborta a execução aqui, impedindo o pop-up nativo do Android
  }
  debugPrint(
    "✅ [FCM-PORTEIRO] APROVADO! O Voo passou no filtro da tela apagada.",
  );

  // =====================================================================
  // 🚀 PASSO 4: EXIBIÇÃO DA NOTIFICAÇÃO NATIVO
  // =====================================================================

  debugPrint(
    "🔔 [FCM-UX] Disparando Sirene Dourada e Notificação visual do Android...",
  );
  try {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(android: initAndroid),
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emissao_vip_v5',
        'Alertas Sonoros VIP',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('alerta'),
        playSound: true,
        enableVibration: true,
      ),
    );

    // 🔕 Canal Silencioso (Obrigatório registrar para o Cooldown funcionar)
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emissao_vip_v5_silent', // Novo ID
        'Alertas Silenciosos (Cooldown)',
        importance: Importance.low, // 🚀 LOW garante que não faz som nem vibra
        playSound: false,
        enableVibration: false,
      ),
    );

    final bool somAtivo = prefs.getBool('SOUND_ENABLED') ?? true;
    final String statusSom = somAtivo ? "🔊 SONORA" : "🔕 SILENCIOSA";
    final String idCanal = somAtivo
        ? 'emissao_vip_v5'
        : 'emissao_vip_v5_silent';
    debugPrint(
      "🔔 [FCM-UX] Preparando Notificação $statusSom via canal: $idCanal",
    );

    await flutterLocalNotificationsPlugin.show(
      id: novoAlerta.id.hashCode,
      title: "✈️ Oportunidade: $programa",
      body: trecho,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          idCanal,
          'Emissões FãMilhasVIP',
          importance: somAtivo ? Importance.max : Importance.high,
          priority: Priority.high,
          sound: somAtivo
              ? const RawResourceAndroidNotificationSound('alerta')
              : null,
          playSound: somAtivo,
        ),
      ),
      payload:
          novoAlerta.id, // 🚀 Use o ID para o blur dourado funcionar sempre
    );
    debugPrint(
      "✨ [FCM-UX] Notificação (${somAtivo ? 'SONORA' : 'MUDA'}) exibida!",
    );
  } catch (e) {
    debugPrint("❌ [FCM-UX] Erro: $e");
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
    FirebaseMessaging.instance.onTokenRefresh.listen((String token) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fcmTokenMobilePrefsKey, token);
      debugPrint('[PUSH] onTokenRefresh recebeu um novo token mobile.');
      await AuthService().sincronizarTokenPushAutorizadoAtual();
    });
  }

  // Notificações locais (só mobile)
  if (!kIsWeb) {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(android: initAndroid),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          debugPrint('👆 [FG-TAP] Toque em foreground: \${response.payload}');
          AlertService().setPendingHighlight(response.payload!);
          AlertService().registrarToqueNotificacao(response.payload!);
        }
      },
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    // Cria o canal AQUI, na thread principal, antes do runApp.
    // Android 13+ pode descartar notificações silenciosamente se o canal
    // for criado apenas no isolate do background handler.
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emissao_vip_v5',
        'Alertas Sonoros',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('alerta'),
        playSound: true,
        enableVibration: true,
      ),
    );

    // 🔕 CANAL SILENCIOSO (Novo ID)
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emissao_vip_v5_silent', // ID Diferente
        'Alertas Silenciosos',
        importance: Importance.low,
        playSound: false,
        enableVibration: true,
      ),
    );
  }

  runApp(const MilhasAlertApp());

  // Web: o receptor do destaque continua ativo, mas o token push
  // só é sincronizado após a sessão ser validada pelo servidor.
  if (kIsWeb) {
    iniciarReceptorWebHighlight((String trecho) {
      debugPrint(
        "🌐 [WEB] Clique recebido! Ignorando timer e forçando PULL...",
      );

      // 🚀 Chama o forceSync diretamente, furando o bloqueio de 5 min!
      AlertService().forceSync(silencioso: true).then((_) {
        AlertService().setPendingHighlight(trecho);

        // Drena a fila logo após o sync terminar para o card acender na hora
        if (AlertService().pendingHighlightCount > 0) {
          AlertService()
              .consumePendingHighlight(); // (A lógica de acender fica a cargo da tela, mas já engatilhamos aqui)
        }
      });
    });
  } else {
    unawaited(_sincronizarTokenPushMobileAtual());
  }
}

/// Configura push web em background.
Future<void> _configurarPushWeb({bool sincronizarComServidor = false}) async {
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
      vapidKey:
          "BOsesHNzz8UHyRwiJRZJfd8ZgeA4hmGi_JPDVPKxOXXDN4T92NHlQa4sSi0m-2K_WnS-aQFXmlolAOSsrgKHg8M",
    );

    if (webToken == null || webToken.isEmpty) {
      debugPrint('⚠️ [WEB] Token gerado foi nulo.');
      return;
    }

    debugPrint("🔥 [WEB] TOKEN FCM WEB: $webToken");

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('FCM_TOKEN_WEB', webToken);
    debugPrint("💾 [WEB] Token salvo.");

    if (sincronizarComServidor) {
      final bool ok = await AuthService().sincronizarTokenPushWebAutorizado();
      debugPrint(
        ok
            ? "✅ [WEB] Token push associado à sessão autorizada."
            : "⛔ [WEB] Token push não foi associado ao servidor.",
      );
    }
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
      title: 'PramilhaSVIP',
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

class _SplashRouterState extends State<SplashRouter>
    with TickerProviderStateMixin {
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
    _ctrlLetterbox = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _letterboxTop = Tween<double>(
      begin: -80.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrlLetterbox, curve: Curves.easeOut));
    _letterboxBottom = Tween<double>(
      begin: 80.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrlLetterbox, curve: Curves.easeOut));

    _ctrlLogo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrlLogo, curve: Curves.easeIn));
    _logoScale = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrlLogo, curve: Curves.easeOutBack));

    _ctrlGlow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _glowRadius = Tween<double>(
      begin: 8.0,
      end: 36.0,
    ).animate(CurvedAnimation(parent: _ctrlGlow, curve: Curves.easeInOut));

    _ctrlExit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _exitOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrlExit, curve: Curves.easeIn));
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
        animation: Listenable.merge([
          _ctrlLetterbox,
          _ctrlLogo,
          _ctrlGlow,
          _ctrlExit,
        ]),
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
          "PRAMILHAS",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: [
              Shadow(
                color: AppTheme.accent.withOpacity(0.4),
                blurRadius: _glowRadius.value,
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
                blurRadius: _glowRadius.value * 1.2,
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

class _MainNavigatorState extends State<MainNavigator>
    with WidgetsBindingObserver {
  int _currentIndex = 1; // Começa na aba central (Licença)
  final AlertService _alertService = AlertService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  // ⏱️ Controle de Concorrência da Sirene
  DateTime? _ultimoToqueSiren;
  final int _cooldownSegundos = 15;

  // 🚀 NOVO: O Controlador que vai fazer a tela subir
  final ScrollController _alertScrollController = ScrollController();
  late final List<Widget> _screens = [
    AlertsScreen(scrollController: _alertScrollController),
    const LicenseScreen(),
    const SmsScreen(),
  ];

  Future<void> _verificarOtimizacaoBateria() async {
    // 🚀 Só pede no Mobile. O navegador ignora isso.
    if (!kIsWeb) {
      PermissionStatus status =
          await Permission.ignoreBatteryOptimizations.status;

      if (!status.isGranted) {
        if (mounted) {
          // 🚀 UX: Explica O POR QUÊ antes de pedir a permissão nativa
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext ctx) {
              return AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.battery_alert, color: AppTheme.yellow, size: 24),
                    SizedBox(width: 10),
                    Text(
                      "Atenção à Bateria",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  "Para que o Radar VIP consiga capturar as emissões no fundo da tela (mesmo com o celular no bolso), precisamos que você permita que o app ignore as otimizações de bateria.\n\nNa próxima tela, clique em 'Permitir'.",
                  style: TextStyle(
                    color: AppTheme.text,
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      // Agora sim, pede a permissão nativa do sistema!
                      await Permission.ignoreBatteryOptimizations.request();
                    },
                    child: const Text(
                      "ENTENDI",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }
      }
    }
  }

  /// Dispara uma notificação local.
  Future<void> _tocarNotificacaoLocal({
    required int idNotificacao,
    required String titulo,
    required String corpo,
    String? payload,
    bool forcarSilencioso = false, // 👈 Nova flag
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Se o usuário desligou geral OU se o sistema de cooldown mandou calar a boca:
    final bool somAtivo =
        (prefs.getBool('SOUND_ENABLED') ?? true) && !forcarSilencioso;

    await flutterLocalNotificationsPlugin.show(
      id: idNotificacao,
      title: titulo,
      body: corpo,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          somAtivo ? 'emissao_vip_v5' : 'emissao_vip_v5_silent',
          'Emissões FãMilhasVIP',
          importance: somAtivo ? Importance.max : Importance.low,
          priority: Priority.high,
          sound: somAtivo
              ? const RawResourceAndroidNotificationSound('alerta')
              : null,
          playSound: somAtivo,
          enableVibration: somAtivo,
        ),
      ),
      payload: payload,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _preAquecerAudioWeb();

    _verificarBloqueioLicenca();

    // 🚀 Chamamos a função de permissão aqui.
    // Ela roda em paralelo e não trava a abertura do app.
    _configurarNotificacoes();

    registerWebCloseListener();
    _alertService.startMonitoring();

    _listenToForegroundPushes();

    _verificarOtimizacaoBateria();

    // 🚀 SÓ PARA WEB: Escuta o sinal vindo do Service Worker (Background -> Foreground)
    if (kIsWeb) {
      _configurarEscutaServiceWorker();
    }
  }

  void _configurarEscutaServiceWorker() {
    if (!kIsWeb) return; // 🛡️ Segurança extra

    try {
      // 🚀 O TRUQUE: Usamos 'dynamic' para o compilador não reclamar do WindowStub
      final dynamic windowGerente = html.window;

      // Canal 1: navigator.serviceWorker
      if (windowGerente.navigator != null &&
          windowGerente.navigator.serviceWorker != null) {
        windowGerente.navigator.serviceWorker.onMessage.listen((event) {
          _processarMensagemSW(event.data);
        });
      }

      // Canal 2: window.onMessage
      html.window.onMessage.listen((event) {
        _processarMensagemSW(event.data);
      });

      debugPrint("📡 [WEB] Escutas do Service Worker (Navigator) ativadas.");
    } catch (e) {
      debugPrint("⚠️ [WEB] Erro ao acessar Navigator: $e");
    }
  }

  // Mantenha a função de processamento separada para organização
  void _processarMensagemSW(dynamic rawData) {
    try {
      if (rawData == null) return;

      Map<String, dynamic> dataMap = {};

      // Decodificação blindada para Web
      if (rawData is String) {
        dataMap = jsonDecode(rawData) as Map<String, dynamic>;
      } else {
        dataMap = jsonDecode(jsonEncode(rawData)) as Map<String, dynamic>;
      }

      if (dataMap['type'] == 'PLAMILHAS_PUSH_RECEIVED') {
        debugPrint("🔊 [WEB] SINAL DO SW CAPTURADO! Acionando sirene...");

        final Map<String, dynamic> payload = Map<String, dynamic>.from(
          dataMap['payload'] ?? {},
        );

        // Injeta na lista e toca o som
        _alertService.injetarAlertaPush(payload);
        _tocarSireneWeb();
      }
    } catch (e) {
      // Mensagens de sistema ou outros tipos de postMessage caem aqui e são ignoradas
    }
  }

  void _preAquecerAudioWeb() async {
    if (kIsWeb) {
      try {
        await _audioPlayer.setVolume(0.0); // Volume zero para ninguém ouvir
        await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
        await _audioPlayer.stop(); // Para rapidinho
        await _audioPlayer.setVolume(
          1.0,
        ); // Volta o volume pro máximo para a sirene real
        debugPrint("🔊 [WEB] Áudio pré-aquecido e destravado no navegador!");
      } catch (e) {
        debugPrint("🔇 [WEB] Falha ao pré-aquecer áudio: $e");
      }
    }
  }

  void _tocarSireneWeb() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool somAtivo = prefs.getBool('SOUND_ENABLED') ?? true;

    if (!somAtivo) return;

    final agora = DateTime.now();

    // 🛡️ O ESCUDO ANTI-AMBULÂNCIA: Verifica se está no tempo de recarga
    if (_ultimoToqueSiren != null &&
        agora.difference(_ultimoToqueSiren!).inSeconds < _cooldownSegundos) {
      debugPrint(
        "🔇 [COOLDOWN] Sirene WEB silenciada. Próximo som em ${_cooldownSegundos - agora.difference(_ultimoToqueSiren!).inSeconds}s.",
      );
      return; // 🛑 Aborta o som, mas o card na tela já foi desenhado!
    }

    try {
      _ultimoToqueSiren = agora; // ⏱️ Atualiza o relógio com a hora do disparo
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
      debugPrint("📢 [WEB] Sirene tocada com sucesso!");
    } catch (e) {
      debugPrint("🔇 Erro ao tocar sirene web: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🛡️ [SEGURANÇA] Validando licença no retorno ao app...");
      _verificarBloqueioLicenca();
    }
  }

  Future<void> _verificarBloqueioLicenca() async {
    // ⚡ Performance O(1): Validação simples de token/data
    final AuthStatus status = await AuthService().validarAcessoDiario();

    if (status == AuthStatus.autorizado) {
      if (kIsWeb) {
        await _configurarPushWeb(sincronizarComServidor: true);
      } else {
        unawaited(_sincronizarTokenPushMobileAtual());
      }
      return;
    }

    if (mounted) {
      debugPrint(
        "⛔ [SEGURANÇA] Licença expirada ou inválida. Expulsando usuário...",
      );

      // 1. Limpa os dados de login
      await AuthService().logout();

      // 2. Redireciona para a Splash que enviará para o Login
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashRouter()),
        );
      }
    }
  }

  // 🚀 Novo método ASSÍNCRONO para resolver o problema do S23+
  Future<void> _configurarNotificacoes() async {
    if (kIsWeb) return;

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    // No Android 13+ (S23+), precisamos checar e pedir explicitamente
    if (androidPlugin != null) {
      final bool? permitida = await androidPlugin.areNotificationsEnabled();

      if (permitida == null || !permitida) {
        await androidPlugin.requestNotificationsPermission();
        debugPrint("🔔 [PERMISSÃO] Pedindo autorização ao usuário...");
      } else {
        debugPrint("✅ [PERMISSÃO] Notificações já estão autorizadas.");
      }
    }
  }

  void _listenToForegroundPushes() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // 🚀 LOG 1: Recebimento e inspeção inicial do pacote
      debugPrint("📥 [FOREGROUND] Mensagem recebida com o app ABERTO!");
      debugPrint("📦 [FOREGROUND] Payload bruto: ${message.data}");

      final String action = message.data['action'] ?? '';
      final String tipo = message.data['tipo'] ?? '';

      debugPrint("🔍 [FOREGROUND] Ação: '$action' | Tipo: '$tipo'");

      if (action != 'SYNC_ALERTS' && tipo != 'NOVO_ALERTA') {
        // 🚀 LOG 2: Descarte rápido
        debugPrint(
          "🤷‍♂️ [FOREGROUND] Ignorado. Não é uma notificação de passagem válida.",
        );
        return;
      }

      final String programa = message.data['programa'] ?? '';
      final String trecho = message.data['trecho'] ?? '';
      final String detalhes = message.data['detalhes'] ?? '';

      debugPrint("🛫 [FOREGROUND] Avaliando Voo: $programa | $trecho");

      // =====================================================================
      // 🚀 PASSO 1 E 2: SALVAR PRIMEIRO INCONDICIONALMENTE (A Fonte da Verdade)
      // =====================================================================

      debugPrint("✅ [FOREGROUND] Convertendo para objeto Alert...");
      final Alert novoAlerta = Alert.fromPush(message.data);
      debugPrint("🆔 [FOREGROUND] ID do alerta extraído: ${novoAlerta.id}");

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cacheRaw =
          prefs.getStringList('ALERTS_CACHE_V2') ?? [];

      // 🚀 LOG 5: Verificação de duplicatas
      debugPrint(
        "📂 [FOREGROUND] Verificando se já existe no cache (total atual: ${cacheRaw.length} alertas)...",
      );
      final bool jaExiste = cacheRaw.any((String raw) {
        try {
          return jsonDecode(raw)['id'] == novoAlerta.id;
        } catch (_) {
          return false;
        }
      });

      if (!jaExiste) {
        // 🚀 LOG 6: Escrita no banco local
        debugPrint(
          "✨ [FOREGROUND] Alerta INÉDITO! Gravando no banco de dados local...",
        );
        cacheRaw.insert(0, jsonEncode(novoAlerta.toJson()));
        await prefs.setStringList(
          'ALERTS_CACHE_V2',
          cacheRaw.take(100).toList(),
        );
        await prefs.setString(
          'CACHE_DATE_V2',
          DateTime.now().toIso8601String().split('T')[0],
        );
        debugPrint(
          "💾 [FOREGROUND] Alert salvo no cache com sucesso: ${novoAlerta.trecho}",
        );
      } else {
        // 🚀 LOG 7: Tratamento de duplicata (implicit else documentado no log)
        debugPrint(
          "♻️ [FOREGROUND] Alerta DUPLICADO detectado. Ignorando a gravação para evitar repetição na tela.",
        );
      }

      // 🔄 Atualiza o motor da UI silenciosamente para garantir que a lista fique fresca
      _alertService.carregarDoCache();

      // =====================================================================
      // 🚀 PASSO 3: O PORTEIRO (Decide se toca a sirene e mostra o Banner Nativo)
      // =====================================================================

      // 🚀 LOG 3: Início da checagem de regras de negócio para exibição
      debugPrint(
        "⚙️ [FOREGROUND] Carregando filtros atuais do usuário para o Pop-Up...",
      );
      final UserFilters filtros = await UserFilters.load();

      if (!filtros.passaNoFiltroBasico(
        programa,
        trecho,
        detalhes: detalhes,
        contexto: 'foreground-popup',
      )) {
        debugPrint(
          "⛔ [FOREGROUND] Push bloqueado pelos filtros visuais (Mas já salvo no banco!).",
        );
        return; // Aborta pop-up nativo superior e sirene
      }

      // 🚀 LOG 4: Passou nos filtros
      debugPrint("✅ [FOREGROUND] Voo passou nos filtros de exibição!");

      // 🚀 LOG 8: Verificação do Mute
      debugPrint(
        "🔊 [FOREGROUND] Verificando se a sirene está permitida pelo usuário...",
      );
      final bool somAtivo =
          prefs.getBool('SOUND_ENABLED') ?? true; // 🚀 Lendo a preferência

      debugPrint(
        "🎛️ [FOREGROUND] Chave de Som atual: ${somAtivo ? 'LIGADA' : 'MUTADA'}",
      );

      if (somAtivo) {
        final agora = DateTime.now();
        bool forcarSilencioso = false;

        // 🛡️ O ESCUDO NO MOBILE: Se chegou muito rápido, joga pro canal mudo
        if (_ultimoToqueSiren != null &&
            agora.difference(_ultimoToqueSiren!).inSeconds <
                _cooldownSegundos) {
          debugPrint("🔇 [COOLDOWN] Push Mobile silenciado para evitar spam.");
          forcarSilencioso = true;
        } else {
          _ultimoToqueSiren = agora; // ⏱️ Se vai tocar som, atualiza o relógio
        }

        debugPrint("🔔 [FOREGROUND] Acionando o pop-up nativo...");

        // 🚀 O pulo do gato: alteramos temporariamente a preferência do som só para este disparo
        await _tocarNotificacaoLocal(
          idNotificacao: novoAlerta.id.hashCode,
          titulo: "✈️ Oportunidade: $programa",
          corpo: trecho,
          payload: novoAlerta.id,
          forcarSilencioso:
              forcarSilencioso, // 👈 Passe essa flag para a função
        );
      } else {
        debugPrint(
          "🔕 [FOREGROUND] Som está desativado, notificações nativas superiores ignoradas.",
        );
        // O app já foi atualizado pelo _alertService.carregarDoCache() acima.
      }

      debugPrint("✅ [FOREGROUND] Fluxo finalizado. Feed atualizado via cache.");
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
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.muted,
        currentIndex: _currentIndex,
        onTap: (int index) {
          // 🚀 UX: Lógica do "Double Tap" para Voltar ao Topo
          if (_currentIndex == 0 && index == 0) {
            if (_alertScrollController.hasClients) {
              _alertScrollController.animateTo(
                0, // 0 é o topo exato da tela
                duration: const Duration(milliseconds: 600),
                curve: Curves
                    .easeOutCubic, // Animação super macia e desacelerada no final
              );
            }
          }
          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.flight_takeoff),
            label: "Alertas",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.badge), label: "Licença"),
          BottomNavigationBarItem(icon: Icon(Icons.sms), label: "SMS"),
        ],
      ),
    );
  }
}

/// Exibe a lista de oportunidades de milhas em tempo real.
class AlertsScreen extends StatefulWidget {
  final ScrollController?
  scrollController; // 🚀 Controlador para o "Voltar ao Topo"

  const AlertsScreen({super.key, this.scrollController});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with WidgetsBindingObserver {
  final AlertService _alertService = AlertService();
  final List<Alert> _listaAlertasTodos = [];
  List<Alert> _listaAlertasFiltrados = [];
  bool _isCarregando = true;
  StreamSubscription<List<Alert>>? _alertSub;
  final Set<String> _idsExistentes = {};
  // dentro da sua classe _AlertsScreenState
  final Map<String, int> _highlightRetryCount = {};
  static const int _maxHighlightRetries = 10;
  final Set<String> _regioesExpandidasBarra = {};

  UserFilters _filtros = UserFilters();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isSoundEnabled = true;
  bool _needsWebAudioInteraction = kIsWeb;
  String? _highlightedTrecho;

  // ── Gist config state ────────────────────────────────────────────────
  bool _maintenanceMode = false; // card de manutenção no topo do feed
  String _announcement = ''; // card de aviso dinâmico no topo do feed

  // 🚀 NOVO: Normalizador Indestrutível
  String _normalizar(String texto) {
    if (texto.isEmpty) return "";
    return texto
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        ) // Limpa todo o resto (traços, emojis, etc)
        .toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadSoundPreference();
    _carregarFiltros();
    _verificarNotificacaoDeAbertura();
    _carregarConfigGist(); // maintenance_mode, announcement, min_version
    _popularDicionarioIata();
  }

  // =========================================================================
  // 🌍 QoL VIP: Popula o Dicionário Estático de IATAs na abertura do App
  // =========================================================================
  Future<void> _popularDicionarioIata() async {
    try {
      final List<String> list = await AeroportoService().getAeroportos();
      if (list.isNotEmpty) {
        for (String aero in list) {
          final partes = aero.split(' - ');
          if (partes.length >= 2) {
            final String iata = partes[0].trim().toUpperCase();
            final String nome = partes[1].trim();
            AirportCache.iataToFullName[iata] = nome;
          }
        }
        debugPrint(
          "🧠 [CÉREBRO VIP] Dicionário IATA carregado com ${AirportCache.iataToFullName.length} aeroportos.",
        );

        // 🚀 Atualiza a tela para os cards reconhecerem os nomes imediatamente
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("⚠️ Erro ao carregar Dicionário IATA: $e");
    }
  }

  void _verificarNotificacaoDeAbertura() {
    // ── tapStream: registrado SINCRONAMENTE (antes de qualquer await) ─────
    // Garante que eventos de cold-start disparados em main() antes do
    // widget montar não se percam por falta de listener.
    _alertService.tapStream.listen((String trechoClicado) {
      debugPrint(
        '👆 [WARM-TAP] Tap recebido: $trechoClicado | carregando: $_isCarregando',
      );
      // Se a lista ainda está carregando, enfileira para drenar quando os cards chegarem.
      // Se já está pronta, acende direto — o addPostFrameCallback dentro de
      // _ativarBlurDourado garante que o setState do dourado vem depois de qualquer
      // rebuild pendente.
      if (_isCarregando) {
        _alertService.setPendingHighlight(trechoClicado);
      } else {
        _ativarBlurDourado(trechoClicado);
      }
    });

    // ── Cold start: verifica se a notificação abriu o app ────────────────
    _verificarColdStart();
  }

  Future<void> _verificarColdStart() async {
    try {
      final NotificationAppLaunchDetails? details =
          await flutterLocalNotificationsPlugin
              .getNotificationAppLaunchDetails();
      if (details != null &&
          details.didNotificationLaunchApp &&
          details.notificationResponse?.payload != null) {
        final String payload = details.notificationResponse!.payload!;
        debugPrint('👆 [COLD-START] Notificação abriu o app: $payload');
        _alertService.setPendingHighlight(payload);
        // addPostFrameCallback garante que os cards já estão na tela
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _drenaFilaDourado();
        });
      } else {
        debugPrint('ℹ️ [COLD-START] App não abriu por notificação.');
      }
    } catch (e) {
      debugPrint('⚠️ [COLD-START] Erro: $e');
    }
  }

  void _drenaFilaDourado() {
    while (_alertService.pendingHighlightCount > 0) {
      final String? trecho = _alertService.consumePendingHighlight();
      if (trecho != null && mounted) {
        debugPrint(
          "✨ [UI-FILA] Drenando destaque: $trecho (${_alertService.pendingHighlightCount} restantes)",
        );
        _ativarBlurDourado(trecho);
      }
    }
  }

  Map<String, Alert> _alertIndex = {};
  String _key(String id) => _normalizar(id);
  void _rebuildIndex() {
    _alertIndex = {
      for (final a in _listaAlertasFiltrados) _key(a.id): a,
      for (final a in _listaAlertasFiltrados) _key(a.trecho): a,
    };
  }

  void _ativarBlurDourado(String payload) {
    if (!mounted) return;

    final String termoBusca = _normalizar(payload);
    if (termoBusca.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final bool existe = _alertIndex.containsKey(termoBusca);

      debugPrint(
        "[DOURADO] buscando=\"$termoBusca\" | existe: $existe | index: ${_alertIndex.length}",
      );

      if (!existe) {
        // contador de retries
        final int current = (_highlightRetryCount[termoBusca] ?? 0) + 1;
        if (current > _maxHighlightRetries) {
          debugPrint(
            "[DOURADO] ❌ max retries atingido para $termoBusca — abortando.",
          );
          _highlightRetryCount.remove(termoBusca);
          return;
        }

        _highlightRetryCount[termoBusca] = current;
        debugPrint("[DOURADO] ⏳ não encontrado no index, retry $current...");

        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _ativarBlurDourado(payload);
        });
        return;
      }

      // ACHOU — limpa contador e aplica highlight
      _highlightRetryCount.remove(termoBusca);

      setState(() => _highlightedTrecho = termoBusca);

      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _highlightedTrecho == termoBusca) {
          setState(() => _highlightedTrecho = null);
        }
      });
    });
  }

  // ── Gist config: maintenance, announcement, min_version ──────────────────
  Future<void> _carregarConfigGist() async {
    final DiscoveryConfig? config = await DiscoveryService().getConfig();
    if (config == null || !mounted) return;

    // ── announcement & maintenance_mode ─────────────────────────────────
    if (mounted) {
      setState(() {
        _maintenanceMode = config.maintenanceMode;
        _announcement = config.announcement.trim();
      });
    }

    // ── min_version: dialog bloqueante se versão instalada for menor ────
    // Só faz sentido em mobile — web não tem versão de APK.
    if (!kIsWeb) {
      try {
        final PackageInfo info = await PackageInfo.fromPlatform();
        if (_versaoMenorQue(info.version, config.minVersion) && mounted) {
          _mostrarDialogAtualizacao(config.minVersion, config.updateUrl);
        }
      } catch (e) {
        debugPrint('⚠️ [GIST] Erro ao verificar versão: $e');
      }
    }
  }

  /// Compara duas versões semânticas: retorna true se [atual] < [minima].
  bool _versaoMenorQue(String atual, String minima) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parse(atual);
    final m = parse(minima);
    for (int i = 0; i < 3; i++) {
      final ai = i < a.length ? a[i] : 0;
      final mi = i < m.length ? m[i] : 0;
      if (ai < mi) return true;
      if (ai > mi) return false;
    }
    return false; // igual
  }

  /// Dialog bloqueante de versão mínima.
  /// Não tem botão de fechar — o usuário precisa clicar em Atualizar.
  void _mostrarDialogAtualizacao(String versaoMinima, String urlDownload) {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // não fecha tocando fora
      builder: (_) => PopScope(
        canPop: false, // não fecha com botão voltar
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.system_update_rounded,
                color: AppTheme.accent,
                size: 22,
              ),
              SizedBox(width: 10),
              Text(
                'Atualização necessária',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Esta versão do app não é mais suportada.\n'
            'Por favor, atualize para a versão $versaoMinima ou superior para continuar.',
            style: const TextStyle(color: AppTheme.text, height: 1.5),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Abre a Play Store na página do app ou o link direto de download, dependendo do que estiver disponível.
                  final Uri uri = Uri.parse(urlDownload);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(
                  'ATUALIZAR AGORA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            _isSoundEnabled
                ? "🔊 Notificações sonoras ATIVADAS"
                : "🔇 Notificações sonoras MUTADAS",
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

    _alertSub = _alertService.alertStream.listen((
      List<Alert> novosAlertas,
    ) async {
      if (mounted) {
        debugPrint(
          "📥 [UI-MOTOR] O Serviço enviou ${novosAlertas.length} alertas recém-chegados.",
        );

        final List<Alert> alertasIneditos = novosAlertas.where((novo) {
          final key = novo.id;
          if (_idsExistentes.contains(key)) return false;
          if (_listaAlertasTodos.any((e) => e.id == key)) return false;
          _idsExistentes.add(key);
          return true;
        }).toList();

        if (alertasIneditos.isNotEmpty) {
          debugPrint(
            "🌟 [UI-MOTOR] ${alertasIneditos.length} alertas INÉDITOS!",
          );

          setState(() {
            _listaAlertasTodos.insertAll(0, alertasIneditos);
            _aplicarFiltrosNaTela();
            _rebuildIndex(); // 🔥 AGORA FUNCIONA
            _isCarregando = false;
          });
        } else {
          debugPrint("🛑 [UI-MOTOR] Todos já estavam na tela.");
          if (_isCarregando) setState(() => _isCarregando = false);
        }

        if (_alertService.pendingHighlightCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) _drenaFilaDourado();
            });
          });
        }
      }
    });

    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted && _isCarregando) {
        debugPrint("⏱️ [UI-MOTOR] Timeout atingido. Removendo indicador.");
        setState(() => _isCarregando = false);
      }
    });
  }

  void _aplicarFiltrosNaTela() {
    debugPrint(
      "🔎 [UI-FILTER] Reaplicando filtros na lista. total=${_listaAlertasTodos.length}",
    );
    _listaAlertasFiltrados = _listaAlertasTodos
        .where((Alert a) => _filtros.alertaPassaNoFiltro(a))
        .toList();
    debugPrint(
      "📋 [UI-FILTER] Resultado da lista filtrada: exibidos=${_listaAlertasFiltrados.length} ocultos=${_listaAlertasTodos.length - _listaAlertasFiltrados.length}",
    );
  }

  @override
  void dispose() {
    _alertSub?.cancel();
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
          setState(() {
            _filtros = novosFiltros;
            _aplicarFiltrosNaTela();
            _rebuildIndex();
          });
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (kIsWeb) {
        // 🌐 NA WEB: Força a busca HTTP imediata para não ter buracos!
        debugPrint('🌐 [WEB] Aba focada! Forçando PULL do servidor...');
        _alertService.carregarDoCache().then((_) {
          _verificarPendenciasDouradas();
        });
      } else {
        // 📱 NO MOBILE: O background já gravou no disco. Leitura instantânea!
        debugPrint(
          '📱 [MOBILE] App abriu! Carregando cache local ultra-rápido...',
        );
        _alertService.carregarDoCache().then((_) {
          _verificarPendenciasDouradas();
        });
      }
    }
  }

  void _verificarPendenciasDouradas() {
    if (!mounted) return;
    if (_alertService.pendingHighlightCount > 0) {
      debugPrint(
        '✨ [RESUME] ${_alertService.pendingHighlightCount} pendentes — drenando...',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _drenaFilaDourado();
      });
    }
  }

  // =========================================================================
  // 🚀 NOVOS HELPERS DE FILTRO (AGORA NO LUGAR CERTO)
  // =========================================================================

  bool get _hasActiveFilters {
    return _filtros.origens.isNotEmpty ||
        _filtros.destinos.isNotEmpty ||
        !_filtros.azulAtivo ||
        !_filtros.latamAtivo ||
        !_filtros.smilesAtivo ||
        !_filtros.outrosAtivo;
  }

  void _resetarCompanhias() async {
    setState(() {
      _filtros.azulAtivo = true;
      _filtros.latamAtivo = true;
      _filtros.smilesAtivo = true;
      _filtros.outrosAtivo = true;
      _aplicarFiltrosNaTela();
      _rebuildIndex();
    });
    await _filtros.save();
  }

  void _alterarCompanhiaLocal(String cia, bool estado) async {
    setState(() {
      if (cia == "Azul") _filtros.azulAtivo = estado;
      if (cia == "Latam") _filtros.latamAtivo = estado;
      if (cia == "Smiles") _filtros.smilesAtivo = estado;
      if (cia == "Outros") _filtros.outrosAtivo = estado;

      _aplicarFiltrosNaTela();
      _rebuildIndex();
    });
    await _filtros.save();
  }

  void _removerFiltroLocal(bool isOrigem, String local) async {
    setState(() {
      if (isOrigem) {
        _filtros.origens.remove(local);
      } else {
        _filtros.destinos.remove(local);
      }
      _aplicarFiltrosNaTela();
      _rebuildIndex();
    });
    await _filtros.save();
  }

  void _limparTodosFiltros() async {
    setState(() {
      _filtros = UserFilters();
      _aplicarFiltrosNaTela();
      _rebuildIndex();
    });
    await _filtros.save();
  }

  // =========================================================================
  // 🚀 INTERFACE VISUAL DA TELA DE ALERTAS
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: _buildAppBar(), body: _buildBody());
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
                  fontSize: 18,
                ),
              ),
              Text(
                "VIP",
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: AppTheme.accent,
                  letterSpacing: 2,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          Text(
            _alertService.lastSyncLabel,
            style: const TextStyle(fontSize: 10, color: AppTheme.muted),
          ),
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
                _isSoundEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
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
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: const Text(
                      '!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          tooltip: "Ligar/Desligar Som",
          onPressed: () async {
            if (_needsWebAudioInteraction) {
              setState(() => _needsWebAudioInteraction = false);
              try {
                await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("🔊 Sistema de áudio desbloqueado!"),
                      backgroundColor: AppTheme.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                debugPrint("🔇 [WEB] Erro ao destravar áudio: $e");
                if (mounted) {
                  setState(() => _needsWebAudioInteraction = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "🔇 O navegador bloqueou o áudio. O app continuará no modo silencioso.",
                      ),
                      backgroundColor: AppTheme.red,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              }
            } else {
              _toggleSound();
            }
          },
        );

        if (_needsWebAudioInteraction) {
          return btn
              .animate(
                onPlay: (AnimationController controller) => controller.repeat(),
              )
              .shake(hz: 4, curve: Curves.easeInOut, duration: 600.ms)
              .then(delay: 1500.ms);
        }
        return btn;
      },
    );
  }

  Widget _buildFilterButton() {
    return IconButton(
      icon: Icon(
        Icons.tune,
        color: _hasActiveFilters ? AppTheme.green : AppTheme.accent,
      ),
      tooltip: "Filtros",
      onPressed: _abrirPainelFiltros,
    );
  }

  Widget _buildActiveFiltersRow() {
    if (!_hasActiveFilters) return const SizedBox.shrink();

    final List<Widget> chips = [];

    if (!_filtros.azulAtivo ||
        !_filtros.latamAtivo ||
        !_filtros.smilesAtivo ||
        !_filtros.outrosAtivo) {
      // Se a companhia está ativa, cria um chip pra ela. O "X" desativa ela.
      if (_filtros.azulAtivo) {
        chips.add(
          _buildMiniChip(
            "✈️ Azul",
            () => _alterarCompanhiaLocal("Azul", false),
          ),
        );
      }
      if (_filtros.latamAtivo) {
        chips.add(
          _buildMiniChip(
            "✈️ Latam",
            () => _alterarCompanhiaLocal("Latam", false),
          ),
        );
      }
      if (_filtros.smilesAtivo) {
        chips.add(
          _buildMiniChip(
            "✈️ Smiles",
            () => _alterarCompanhiaLocal("Smiles", false),
          ),
        );
      }
      if (_filtros.outrosAtivo) {
        chips.add(
          _buildMiniChip(
            "✈️ Outros",
            () => _alterarCompanhiaLocal("Outros", false),
          ),
        );
      }

      // Se o usuário fechou TODAS as companhias no dedo, mostramos um chip de reset geral
      if (!_filtros.azulAtivo &&
          !_filtros.latamAtivo &&
          !_filtros.smilesAtivo &&
          !_filtros.outrosAtivo) {
        chips.add(_buildMiniChip("🚫 Nenhuma Cia", _resetarCompanhias));
      }
    }

    // 🚀 MOTOR DE AGRUPAMENTO DA BARRA HORIZONTAL
    void agruparBarra(List<String> lista, bool isOrigem) {
      Map<String, List<String>> agrupado = {};
      for (String item in lista) {
        final partes = item.split(' - ');
        if (partes.length >= 3) {
          agrupado
              .putIfAbsent(partes.last.trim().toUpperCase(), () => [])
              .add(item);
        } else {
          chips.add(
            _buildMiniChip(
              isOrigem ? "🛫 ${partes.first}" : "🛬 ${partes.first}",
              () => _removerFiltroLocal(isOrigem, item),
            ),
          );
        }
      }

      agrupado.forEach((regiao, aeros) {
        final key = "${isOrigem ? 'O' : 'D'}_$regiao";
        if (aeros.length >= 2) {
          if (_regioesExpandidasBarra.contains(key)) {
            // MODO EXPANDIDO
            chips.add(
              _buildMiniChip(
                "🔽 $regiao",
                () => setState(() => _regioesExpandidasBarra.remove(key)),
                corBorda: AppTheme.border,
                corFundo: Colors.transparent,
              ),
            );
            for (String aero in aeros) {
              chips.add(
                _buildMiniChip(
                  isOrigem
                      ? "🛫 ${aero.split(' - ').first}"
                      : "🛬 ${aero.split(' - ').first}",
                  () => _removerFiltroLocal(isOrigem, aero),
                ),
              );
            }
          } else {
            // 🌍 MODO COMPACTO (A pílula que apaga tudo)
            chips.add(
              _buildMiniChip(
                "🌍 ${isOrigem ? 'De' : 'Para'} $regiao (${aeros.length})",
                () {
                  // O X deleta tudo
                  setState(() {
                    lista.removeWhere((e) => aeros.contains(e));
                    _aplicarFiltrosNaTela();
                    _rebuildIndex();
                  });
                  _filtros.save();
                },
                onTap: () => setState(
                  () => _regioesExpandidasBarra.add(key),
                ), // O clique expande
                corFundo: AppTheme.accent.withOpacity(0.3),
                corBorda: AppTheme.accent,
              ),
            );
          }
        } else {
          for (String aero in aeros) {
            chips.add(
              _buildMiniChip(
                isOrigem
                    ? "🛫 ${aero.split(' - ').first}"
                    : "🛬 ${aero.split(' - ').first}",
                () => _removerFiltroLocal(isOrigem, aero),
              ),
            );
          }
        }
      });
    }

    agruparBarra(_filtros.origens, true);
    agruparBarra(_filtros.destinos, false);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // 🚀 UX VIP: Força o Flutter a aceitar o Mouse como se fosse Touch
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse, // 👈 A mágica acontece aqui!
            PointerDeviceKind.trackpad,
          },
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) => Center(child: chips[index]),
        ),
      ),
    );
  }

  Widget _buildMiniChip(
    String label,
    VoidCallback onDeleted, {
    VoidCallback? onTap,
    Color? corBorda,
    Color? corFundo,
  }) {
    // ==========================================================
    // 🚀 CÉREBRO DO TOOLTIP NA PÍLULA
    // Tenta achar as 3 letras da IATA dentro do label (ex: "🛫 AFL")
    // ==========================================================
    String tooltipMsg = "";
    final match = RegExp(r'[A-Z]{3}').firstMatch(label);

    if (match != null) {
      final iata = match.group(0)!;
      final nome = AirportCache.iataToFullName[iata]; // Busca no nosso cache!
      if (nome != null) {
        tooltipMsg = "🌍 $nome";
      }
    }

    // O texto base da pílula
    Widget textWidget = Text(
      label,
      style: const TextStyle(
        color: AppTheme.text,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );

    // Se achou no dicionário, embrulha o texto com o Tooltip Mágico
    if (tooltipMsg.isNotEmpty) {
      textWidget = Tooltip(
        message: tooltipMsg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        preferBelow: true,
        waitDuration: kIsWeb
            ? const Duration(milliseconds: 100)
            : const Duration(milliseconds: 500),
        child: textWidget,
      );
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: corFundo ?? AppTheme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corBorda ?? AppTheme.accent.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: textWidget, // 🚀 Coloca o texto (com ou sem Tooltip) aqui
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close, size: 14, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartEmptyState() {
    // Substitua o bloco `if (_hasActiveFilters)` inteiro por este:
    if (_hasActiveFilters) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🚀 UX VIP: Efeito Sonar/Radar flutuante suave e animado
            // 🚀 UX VIP: Efeito Sonar/Radar flutuante suave e animado
            Stack(
              alignment: Alignment.center,
              children: [
                // Os Círculos de Onda (Sonar)
                Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.border.withOpacity(0.05),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(
                      begin: const Offset(1.0, 1.0), // 👈 CORREÇÃO AQUI
                      end: const Offset(1.8, 1.8), // 👈 CORREÇÃO AQUI
                      duration: 1.5.seconds,
                      curve: Curves.easeOut,
                    )
                    .fade(begin: 0.5, end: 0.0),

                Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.border.withOpacity(0.1),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(
                      begin: const Offset(1.0, 1.0), // 👈 CORREÇÃO AQUI
                      end: const Offset(2.2, 2.2), // 👈 CORREÇÃO AQUI
                      delay: 500.ms,
                      duration: 1.5.seconds,
                      curve: Curves.easeOut,
                    )
                    .fade(begin: 0.3, end: 0.0),

                // O ícone do Radar Central
                const Icon(
                      Icons.satellite_alt_rounded,
                      size: 40,
                      color: AppTheme.border,
                    )
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .moveY(begin: -3, end: 3, duration: 1.seconds),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Rastreando o Céu...',
              style: TextStyle(
                color: AppTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ).animate().fade(delay: 300.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 8),
            const Text(
              'O sonar VIP está varrendo o banco de dados das companhias.\nNenhum voo para os seus filtros por enquanto!',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ).animate().fade(delay: 400.ms),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red.withOpacity(0.1),
                foregroundColor: AppTheme.red,
                side: const BorderSide(color: AppTheme.red),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_sweep),
              label: const Text(
                "LIMPAR TODOS OS FILTROS",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              onPressed: _limparTodosFiltros,
            ).animate().fade(delay: 500.ms).scale(),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🚀 UX: Ícone flutuante suave para indicar que o sistema está "vigiando"
          const Icon(Icons.radar, size: 64, color: AppTheme.border)
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .moveY(begin: -5, end: 5, duration: 2.seconds),
          const SizedBox(height: 16),
          const Text(
            'Tudo limpo por aqui!',
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ).animate().fade(delay: 300.ms),
          const SizedBox(height: 8),
          const Text(
            'Aguarde, o radar VIP está varrendo as companhias.',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
            textAlign: TextAlign.center,
          ).animate().fade(delay: 400.ms),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              height: 90,
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 180,
                            height: 14,
                            color: AppTheme.surface,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 100,
                            height: 12,
                            color: AppTheme.surface,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 1200.ms, color: Colors.white12);
  }

  Widget _buildBody() {
    if (_isCarregando) {
      return _buildSkeletonLoading();
    }

    final List<Widget> banners = [
      if (_maintenanceMode) _buildMaintenanceBanner(),
      if (_announcement.isNotEmpty) _buildAnnouncementCard(),
    ];

    Widget mainContent = CustomScrollView(
      controller: widget.scrollController, // 🚀 O Cérebro do scroll conectado!
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (banners.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(children: banners),
            ),
          ),

        if (_listaAlertasFiltrados.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildSmartEmptyState(),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                final Alert alerta = _listaAlertasFiltrados[index];
                final String trechoNorm = _normalizar(alerta.trecho);
                final String idNorm = _normalizar(alerta.id);
                final bool isGolden =
                    _highlightedTrecho != null &&
                    (trechoNorm.contains(_highlightedTrecho!) ||
                        idNorm.contains(_highlightedTrecho!));

                return AlertCard(
                  key: ValueKey(alerta.id),
                  alerta: alerta,
                  isHighlighted: isGolden,
                );
              }, childCount: _listaAlertasFiltrados.length),
            ),
          ),
      ],
    );

    return Column(
      children: [
        _buildActiveFiltersRow(),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            strokeWidth: 3, // 🚀 Fica mais gordinho e premium
            onRefresh: () async {
              // 🚀 UX: Vibração ao puxar a lista (Feedback Tátil)
              HapticFeedback.mediumImpact();

              await _alertService.forceSync(silencioso: false);

              if (mounted) {
                // 🚀 UX: Som removido a pedido do feedback (evita irritar o usuário).
                // O SnackBar verde abaixo já é o feedback visual perfeito!

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Radar atualizado com sucesso!",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    backgroundColor: AppTheme.green,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            },
            child: mainContent,
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.yellow.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.yellow.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.build_circle_outlined,
            color: AppTheme.yellow,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sistema em manutenção. Algumas funcionalidades podem estar limitadas.',
              style: TextStyle(
                color: AppTheme.yellow,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withOpacity(0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_outlined, color: AppTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _announcement,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
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
    this.isHighlighted = false,
  });

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool _isExpanded = false;
  bool _blurCusto = false;
  bool _blurBalcao = false;
  bool _blurAgencia = false;

  // =========================================================================
  // 🚀 NOVAS FUNÇÕES DE QoL (Quality of Life)
  // =========================================================================

  // /// 🌍 CÉREBRO QoL: Converte "GRU" -> "São Paulo Guarulhos" p/ Leigos
  // String _expandTrechoTooltip(String trechoRaw) {
  //   if (trechoRaw == "N/A" || trechoRaw.isEmpty) return "";

  //   RegExp iataRegExp = RegExp(r'\b\w{3}\b');
  //   Iterable<Match> matches = iataRegExp.allMatches(trechoRaw);

  //   String tooltipText = "";
  //   Set<String> iatasFound = {};

  //   for (Match match in matches) {
  //     iatasFound.add(match.group(0)!);
  //   }

  //   if (iatasFound.isNotEmpty) {
  //     for (int i = 0; i < iatasFound.length; i++) {
  //       final String iata = iatasFound.elementAt(i).toUpperCase();
  //       final String? fullName = AirportCache.iataToFullName[iata];

  //       if (fullName != null) {
  //         tooltipText += "🌍 $iata: $fullName";
  //       }

  //       if (i < iatasFound.length - 1 && tooltipText.isNotEmpty) {
  //         tooltipText += "\n";
  //       }
  //     }
  //   }

  //   return tooltipText;
  // }

  /// Copia o texto para a área de transferência com feedback tátil e visual
  void _copiarTexto(String texto, String label) {
    if (texto == "N/A" || texto.isEmpty) return;

    Clipboard.setData(ClipboardData(text: texto));
    HapticFeedback.lightImpact(); // Vibração premium

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.content_copy, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                "$label copiado!",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppTheme.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Gera a mensagem de marketing e abre a gaveta nativa do celular
  /// Gera a mensagem de marketing e abre a gaveta nativa (ou WhatsApp na Web)
  Future<void> _compartilharVoo() async {
    final String valorAgencia = _formatarDecimal(widget.alerta.valorEmissao);

    final String texto =
        "✈️ *Alerta de Emissão!*\n"
        "Encontrei essa oportunidade no radar *PramilhasVIP*:\n\n"
        "🛫 *Trecho:* ${widget.alerta.trecho}\n"
        "🏷️ *Programa:* ${widget.alerta.programa}\n"
        "💰 *Custo Agência:* R\$ $valorAgencia\n"
        "💸 *Milhas:* ${widget.alerta.milhas}\n\n"
        "👉 _Quer receber alertas VIPs? Acesse:_ pramilhasweb.suportvip.com";

    if (kIsWeb) {
      // 🌐 NA WEB: A gaveta nativa falha. Vamos forçar o WhatsApp Web!
      final String textoCodificado = Uri.encodeComponent(texto);
      final Uri whatsappUrl = Uri.parse("https://wa.me/?text=$textoCodificado");

      try {
        // 🛡️ PLANO B EMBUTIDO: Já copia o texto por segurança antes de abrir a aba
        await Clipboard.setData(ClipboardData(text: texto));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Abrindo WhatsApp... O texto também foi copiado!'),
              backgroundColor: AppTheme.accent,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Lança a nova aba do WhatsApp Web
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } catch (e) {
        // Se der erro (ex: bloqueador de pop-up), cai no fallback normal
        _copiarTexto(texto, "Mensagem Promocional");
      }
    } else {
      // 📱 NO MOBILE: O Share.share abre a gaveta do sistema lindamente (Whats, Insta, Telegram...)
      try {
        await Share.share(texto);
      } catch (e) {
        _copiarTexto(texto, "Mensagem Promocional");
      }
    }
  }

  /// 🚀 NOVO: Copia a mensagem completa (marketing) com 1 clique
  void _copiarVooCompleto() {
    final String valorAgencia = _formatarDecimal(widget.alerta.valorEmissao);

    final String texto =
        "✈️ *Alerta de Emissão!*\n"
        "Encontrei essa oportunidade no radar *PramilhasVIP*:\n\n"
        "🛫 *Trecho:* ${widget.alerta.trecho}\n"
        "🏷️ *Programa:* ${widget.alerta.programa}\n"
        "💰 *Custo Agência:* R\$ $valorAgencia\n"
        "💸 *Milhas:* ${widget.alerta.milhas}\n\n"
        "👉 _Quer receber alertas VIPs? Acesse:_ pramilhasweb.suportvip.com";

    _copiarTexto(texto, "Oportunidade completa");
  }

  // =========================================================================
  // FUNÇÕES DE AÇÃO EXTERNA EXISTENTES
  // =========================================================================

  Future<void> _abrirLink() async {
    if (widget.alerta.link == null || widget.alerta.link!.isEmpty) return;
    final Uri url = Uri.parse(widget.alerta.link!);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível abrir o link.")),
        );
    }
  }

  Future<void> _abrirBalcao() async {
    String mensagemParaCopiar = widget.alerta.mensagemBalcao;
    if (mensagemParaCopiar == "N/A" || mensagemParaCopiar.isEmpty) {
      mensagemParaCopiar =
          "👋 Olá! Gostaria de cotar a emissão do trecho: ${widget.alerta.trecho}\nCompanhia: ${widget.alerta.programa}";
    }
    await Clipboard.setData(ClipboardData(text: mensagemParaCopiar));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📋 Mensagem copiada! Cole no grupo do Balcão."),
          backgroundColor: AppTheme.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
    try {
      final DiscoveryConfig? config = await DiscoveryService().getConfig();
      final String urlFinal =
          config?.whatsappGroupUrl ??
          "https://chat.whatsapp.com/DMyfA6rb7jmJsvCJUVU5vk";
      await launchUrl(
        Uri.parse(urlFinal),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao abrir WhatsApp: $e"),
            backgroundColor: AppTheme.red,
          ),
        );
    }
  }

  Future<void> _emitirComAAgencia() async {
    String urlAgencia = widget.alerta.linkAgencia;
    if (urlAgencia == "N/A" || urlAgencia.isEmpty)
      urlAgencia = widget.alerta.link ?? "";
    if (urlAgencia.isEmpty) return;

    try {
      final Uri url = Uri.parse(urlAgencia);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Não foi possível abrir o link da agência."),
          ),
        );
    }
  }

  String _formatarDecimal(String valorOriginal) {
    if (valorOriginal == "N/A" || valorOriginal == "0" || valorOriginal.isEmpty)
      return valorOriginal;
    try {
      String limpo = valorOriginal
          .replaceAll(RegExp(r'[^\d.,]'), '')
          .replaceAll(',', '.');
      double numero = double.parse(limpo);
      return numero.toStringAsFixed(2).replaceAll('.', ',');
    } catch (e) {
      return valorOriginal;
    }
  }

  // =========================================================================
  // CONSTRUÇÃO DA INTERFACE (UI)
  // =========================================================================

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
    } else if (prog.contains("TAP")) {
      corPrincipal = const Color(0xFF2DD4BF);
      corFundo = const Color(0xFF0A1F1C);
    } else if (prog.contains("IBERIA") || prog.contains("IBÉRIA")) {
      corPrincipal = const Color(0xFFD30000);
      corFundo = const Color(0xFF1A0505);
    } else if (prog.contains("AADVANTAGE")) {
      corPrincipal = const Color(0xFF0078D2);
      corFundo = const Color(0xFF0B172A);
    } else if (prog.contains("GOL")) {
      corPrincipal = const Color(0xFFFF5C00);
      corFundo = const Color(0xFF140800);
    } else if (prog.contains("QATAR")) {
      corPrincipal = const Color(0xFF860232);
      corFundo = const Color(0xFF140108);
    } else {
      corPrincipal = const Color.fromARGB(255, 192, 190, 190);
      corFundo = AppTheme.black;
    }

    final BoxShadow blurDourado = widget.isHighlighted
        ? const BoxShadow(
            color: Colors.amberAccent,
            blurRadius: 20,
            spreadRadius: 2,
          )
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
          width: widget.isHighlighted ? 2.0 : 1.0,
        ),
        boxShadow: [
          blurDourado,
          if (_isExpanded && !widget.isHighlighted)
            BoxShadow(
              color: corPrincipal.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 1,
            ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(corPrincipal, prog),
            // 🚀 UX: O EFEITO SANFONA MÁGICO AQUI!
            AnimatedSize(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _isExpanded
                  ? _buildDetails(corPrincipal)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color corPrincipal, String prog) {
    final String horaFormatada =
        "${widget.alerta.data.hour.toString().padLeft(2, '0')}:${widget.alerta.data.minute.toString().padLeft(2, '0')}";
    final Duration idadeDoAlerta = DateTime.now().difference(
      widget.alerta.data,
    );
    Color corRelogio = AppTheme.muted;

    if (idadeDoAlerta.inMinutes < 60) {
      corRelogio = AppTheme.green;
    } else if (idadeDoAlerta.inHours < 4) {
      corRelogio = AppTheme.yellow;
    }

    final String trechoDisplay = widget.alerta.trecho != "N/A"
        ? widget.alerta.trecho
        : "Nova Oportunidade!";

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: corPrincipal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.flight_takeoff, color: corPrincipal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🚀 UX: Long Press no Trecho para Copiar
                // 🚀 UX: Long Press no Trecho para Copiar
                GestureDetector(
                  onTap: () => _copiarTexto(trechoDisplay, "Trecho"),
                  onLongPress: () => _copiarTexto(trechoDisplay, "Trecho"),
                  // 👇 Substitua a partir daqui! 👇
                  child: Text(
                    trechoDisplay,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 👆 Até aqui! 👆
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      prog,
                      style: TextStyle(
                        color: corPrincipal,
                        fontSize: 13.2,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const Text(" • ", style: TextStyle(color: AppTheme.muted)),
                    Text(
                      "${widget.alerta.milhas} milhas",
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, color: corRelogio, size: 10),
                  const SizedBox(width: 4),
                  Text(
                    horaFormatada,
                    style: TextStyle(
                      color: corRelogio,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Icon(
                _isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: AppTheme.muted,
                size: 20,
              ),
            ],
          ),
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
          // 🚀 UX: Header dos detalhes com os botões de Copiar e Compartilhar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "INFORMAÇÕES DO VOO",
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🚀 NOVO BOTÃO: COPIAR TUDO
                  InkWell(
                    onTap: _copiarVooCompleto,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 14, color: corPrincipal),
                          const SizedBox(width: 4),
                          Text(
                            "COPIAR",
                            style: TextStyle(
                              color: corPrincipal,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // BOTÃO EXISTENTE: COMPARTILHAR
                  InkWell(
                    onTap: _compartilharVoo,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.ios_share_rounded,
                            size: 14,
                            color: corPrincipal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "COMPARTILHAR",
                            style: TextStyle(
                              color: corPrincipal,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          _buildInfoColumn("IDA", widget.alerta.dataIda),
          _buildInfoColumn("VOLTA", widget.alerta.dataVolta),
          _buildValueWithToast(
            "FABRICADO",
            widget.alerta.valorFabricado,
            corPrincipal,
            _blurCusto,
            (bool v) => setState(() => _blurCusto = v),
          ),
          _buildValueWithToast(
            "BALCÃO",
            widget.alerta.valorBalcao,
            AppTheme.esmerald,
            _blurBalcao,
            (bool v) => setState(() => _blurBalcao = v),
          ),
          _buildValueWithToast(
            "AGÊNCIA",
            widget.alerta.valorEmissao,
            AppTheme.golden,
            _blurAgencia,
            (bool v) => setState(() => _blurAgencia = v),
          ),
        ],
      ),
    );
  }

  Widget _buildValueWithToast(
    String label,
    String value,
    Color color,
    bool isFocused,
    Function(bool) onFocusChanged,
  ) {
    return MouseRegion(
      onEnter: (_) => onFocusChanged(true),
      onExit: (_) => onFocusChanged(false),
      child: GestureDetector(
        onTapDown: (_) => onFocusChanged(true),
        onTapUp: (_) => onFocusChanged(false),
        onTapCancel: () => onFocusChanged(false),
        onLongPress: () => _copiarTexto(value, label),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🚀 UX: Sem o ícone de cópia para não poluir
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 28,
                child: AnimatedScale(
                  scale: isFocused ? 1.08 : 1.0,
                  alignment: Alignment.centerLeft,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          Text(
            titulo,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _copiarTexto(valor, titulo),
            onLongPress: () =>
                _copiarTexto(valor, titulo), // 🚀 Adicionado Long Press também
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
              // 🚀 UX: Sem o ícone de cópia
              child: Text(
                valor,
                style: TextStyle(
                  color: corExibicao,
                  fontSize: 11.5,
                  fontWeight: corValor != null
                      ? FontWeight.w900
                      : FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
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
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 11,
            height: 1.4,
          ),
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
              onHoverChanged: (bool val) => setState(() => _blurCusto = val),
            ),
          ),
        _buildActionButton(
          "EMITIR NO BALCÃO",
          Icons.local_atm_rounded,
          AppTheme.esmerald,
          _abrirBalcao,
          showTax: true,
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
          onHoverChanged: (bool val) => setState(() => _blurAgencia = val),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed, {
    Color? textColor,
    Color? shadowColor,
    bool showTax = false,
    ValueChanged<bool>? onHoverChanged,
  }) {
    final bool taxaExiste =
        widget.alerta.taxas != 'N/A' &&
        widget.alerta.taxas != '0' &&
        widget.alerta.taxas.isNotEmpty;
    final Color taxColor = taxaExiste ? color : Colors.redAccent;
    final String taxLabel = taxaExiste
        ? "Taxas de R\$ ${_formatarDecimal(widget.alerta.taxas)} inclusas"
        : 'Taxas aeroportuárias não inclusas';
    final IconData taxIcon = taxaExiste
        ? Icons.check_circle_outline
        : Icons.info_outline;

    return _HoverButton(
      onHoverChanged: onHoverChanged,
      builder: (bool hovered) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTax)
            AnimatedSize(
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
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: taxColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: taxColor.withOpacity(0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(taxIcon, size: 13, color: taxColor),
                              const SizedBox(width: 6),
                              Text(
                                taxLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: taxColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          SizedBox(
            width: double.infinity,
            height: 45,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: textColor ?? Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: hovered ? 6 : 4,
                shadowColor: (shadowColor ?? color).withOpacity(0.4),
              ),
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
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
    onExit: (_) => _updateState(false),
    child: GestureDetector(
      onTapDown: (_) => _updateState(true),
      onTapUp: (_) => _updateState(false),
      onTapCancel: () => _updateState(false),
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
  static const MethodChannel _platform = MethodChannel(
    'com.suportvips.milhasalert/sms_control',
  );
  bool _isMonitoring = false;
  List<Map<String, String>> _smsHistory = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _carregarEstadoBotao();
    _loadHistory();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadHistory(),
    );
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
          _smsHistory = decoded
              .map(
                (dynamic e) => {
                  "remetente": e["remetente"].toString(),
                  "mensagem": e["mensagem"].toString(),
                  "hora": e["hora"].toString(),
                },
              )
              .toList()
              .reversed
              .toList();
        });
      }
    } catch (e) {
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
                ),
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
          if (mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
        }
      });
    } else {
      try {
        await _platform.invokeMethod('stopSmsService');
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('IS_SMS_MONITORING', false);

        if (mounted) setState(() => _isMonitoring = false);
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Erro nativo: $e")));
      }
    }
  }

  // 🚀 NOVO: Formata o tempo "fixo" do Android para tempo relativo "Há X min"
  String _formatarTempoSms(String? dataSms) {
    if (dataSms == null || dataSms.isEmpty) return "";
    try {
      final agora = DateTime.now();
      final partes = dataSms.split(' '); // Separa "23/03" de "14:30"
      if (partes.length < 2) return dataSms;

      final dataPartes = partes[0].split('/');
      final horaPartes = partes[1].split(':');

      // Monta o objeto DateTime assumindo o ano atual
      final DateTime dtSms = DateTime(
        agora.year,
        int.parse(dataPartes[1]),
        int.parse(dataPartes[0]),
        int.parse(horaPartes[0]),
        int.parse(horaPartes[1]),
      );

      final diff = agora.difference(dtSms);

      if (diff.inMinutes < 1) return "Agora mesmo";
      if (diff.inMinutes < 60) return "Há ${diff.inMinutes} min";
      if (diff.inHours < 24) return "Há ${diff.inHours} h";
      return dataSms; // Se for de outro dia, mostra a data normal
    } catch (e) {
      return dataSms;
    }
  }

  // 🚀 NOVO: Cópia inteligente com extração de código
  void _copiarSms(String texto) {
    if (texto.isEmpty) return;

    // Procura por sequências de 4 a 8 dígitos (padrão de OTP/Token)
    final RegExp regExp = RegExp(r'\b\d{4,8}\b');
    final Match? match = regExp.firstMatch(texto);

    String textoParaCopiar;
    String labelToast;

    if (match != null) {
      textoParaCopiar = match.group(0)!;
      labelToast = "Código de verificação copiado!"; // Sucesso na extração
    } else {
      textoParaCopiar = texto;
      labelToast = "Conteúdo do SMS copiado!"; // Fallback: mensagem completa
    }

    Clipboard.setData(ClipboardData(text: textoParaCopiar));
    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              labelToast,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: AppTheme.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
          Text(
            "SMS",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
              fontSize: 20,
            ),
          ),
          Text(
            "VIP",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.accent,
              letterSpacing: 2,
              fontSize: 20,
            ),
          ),
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
              Text(
                "Função Exclusiva Mobile",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 10),
              Text(
                "A interceptação de SMS ocorre localmente no aparelho para garantir a sua privacidade.\n\nInstale o aplicativo no seu celular Android para ativar o motor de captura.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
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
        border: Border.all(
          color: !_isMonitoring
              ? AppTheme.red.withOpacity(0.3)
              : AppTheme.green.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: !_isMonitoring
                ? AppTheme.red.withOpacity(0.05)
                : AppTheme.green.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
                _isMonitoring ? Icons.satellite_alt : Icons.portable_wifi_off,
                size: 60,
                color: _isMonitoring ? AppTheme.green : AppTheme.muted,
              )
              .animate(target: _isMonitoring ? 1 : 0)
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
                  color: !_isMonitoring ? AppTheme.red : AppTheme.green,
                ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: _isMonitoring ? 0 : 10,
        ),
        icon: Icon(
          _isMonitoring ? Icons.stop_circle : Icons.play_circle_fill,
          size: 24,
        ),
        label: Text(
          _isMonitoring ? "DESLIGAR SMS" : "INICIAR REDIRECIONAMENTO SMS",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 14,
          ),
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
        Text(
          "ÚLTIMOS SMS CAPTURADOS",
          style: TextStyle(
            color: AppTheme.muted,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    return Expanded(
      child: _smsHistory.isEmpty
          ? const Center(
              child: Text(
                "Nenhum SMS interceptado ainda.",
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: _smsHistory.length,
              itemBuilder: (BuildContext context, int index) {
                final Map<String, String> sms = _smsHistory[index];
                final String mensagem = sms["mensagem"] ?? "";
                // 🚀 Chama o formatador de tempo relativo
                final String tempoRelativo = _formatarTempoSms(sms["hora"]);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => _copiarSms(mensagem), // 🚀 Cópia Inteligente
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
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
                              Text(
                                sms["remetente"] ?? "",
                                style: const TextStyle(
                                  color: AppTheme.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 🚀 Exibe o tempo relativo (Há X min)
                                  Text(
                                    tempoRelativo,
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => Share.share(mensagem),
                                    child: const Icon(
                                      Icons.share,
                                      size: 14,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            mensagem,
                            style: const TextStyle(
                              color: AppTheme.text,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
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

    if (mounted) {
      setState(() {
        _deviceId = id;
        _userToken = dados['token'] ?? "...";
        _userEmail = dados['email'] ?? "...";
        _userUsuario = dados['usuario'] ?? "...";
        _userVencimento = dados['vencimento'] ?? "...";
        _userIdPlanilha = dados['idPlanilha'] ?? "...";
      });
    }

    final AuthStatus status = await _auth.validarAcessoDiario();

    if (mounted) {
      setState(() {
        _isBloqueado = (status != AuthStatus.autorizado);
        _statusConexao = (status == AuthStatus.autorizado)
            ? "Serviço Ativo"
            : "BLOQUEADO";
      });
    }
  }

  Future<void> _fazerLogoff() async {
    setState(() => _isSaindo = true);

    try {
      // 1. Apaga no Firebase (Garante que o celular fica surdo IMEDIATAMENTE)
      await FirebaseMessaging.instance.deleteToken();
      debugPrint("🗑️ [FCM] Token destruído no Firebase.");

      // 2. 🚀 AVISA O GOOGLE APPS SCRIPT PARA LIMPAR A VAGA E O TOKEN
      final config = await DiscoveryService().getConfig();
      if (config != null && config.gasUrl.isNotEmpty) {
        final uri = Uri.parse(config.gasUrl);
        await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'action': 'REMOVE_DEVICE',
                'deviceId': _deviceId,
              }),
            )
            .timeout(const Duration(seconds: 5));
        debugPrint(
          "🧹 [GAS] Planilha avisada do Logoff. Vaga e Token liberados!",
        );
      }
    } catch (e) {
      if (e.toString().contains('Failed to fetch')) {
        debugPrint(
          "🧹 [GAS] Planilha avisada do Logoff (CORS ignorado). Vaga liberada!",
        );
      } else {
        debugPrint("⚠️ Erro durante o logoff remoto: $e");
      }
    }

    // 3. Limpa os dados de usuário locais do aparelho (Obrigatório dar await aqui!)
    await _auth.logout();

    // 4. SÓ DEPOIS de apagar tudo, manda pra Splash Screen!
    if (mounted) {
      // Usa pushAndRemoveUntil para DESTRUIR a pilha de telas inteira!
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const SplashRouter()),
        (Route<dynamic> route) => false, // 🔥 Remove todas as rotas anteriores!
      );
    }
  }

  Color _getCorVencimento(String dataVencimentoStr) {
    if (dataVencimentoStr == "..." || dataVencimentoStr == "N/A")
      return AppTheme.muted;

    try {
      final List<String> partes = dataVencimentoStr.split('/');
      if (partes.length != 3) return AppTheme.muted;

      final DateTime validade = DateTime(
        int.parse(partes[2]),
        int.parse(partes[1]),
        int.parse(partes[0]),
      );
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
            const SizedBox(height: 15),
            _buildRenovarLicencaButton(),
            const SizedBox(height: 10),
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
          Text(
            "SESSÃO",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
              fontSize: 20,
            ),
          ),
          Text(
            "VIP",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.accent,
              letterSpacing: 2,
              fontSize: 20,
            ),
          ),
        ],
      ),
      actions: [
        // 🚀 Novo botão de suporte
        IconButton(
          icon: const Icon(Icons.help_outline, color: AppTheme.muted),
          tooltip: 'Suporte',
          onPressed: _mostrarDialogoSuporte, // 🚀 Chama o método que criamos
        ),
        // Botão de recarga existente
        IconButton(
          icon: _statusConexao == "Validando Licença..."
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: AppTheme.accent,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.refresh, color: AppTheme.muted),
          tooltip: 'Recarregar Dados',
          onPressed: _statusConexao == "Validando Licença..."
              ? null
              : _inicializarSistema,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// 🚀 1. Chama o Popup Intermediário
  Future<void> _mostrarDialogoSuporte() async {
    final config = await DiscoveryService().getConfig();

    // Agora o Gist só precisa ter o e-mail limpo! Ex: master@devs.suportvip.com
    String emailDestino = config?.urlSuporte ?? "master@devs.suportvip.com";

    // Faxina por segurança (caso tenha sobrado um mailto: no Gist)
    emailDestino = emailDestino.replaceAll('mailto:', '').split('?').first;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                color: AppTheme.accent,
                size: 24,
              ),
              SizedBox(width: 10),
              Text(
                "Suporte VIP",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            "Você será redirecionado para o seu aplicativo de e-mail.\n\n"
            "Para um atendimento mais rápido, seja o mais detalhista possível na descrição e não hesite em anexar imagens/prints da tela mostrando o problema.",
            style: TextStyle(color: AppTheme.text, height: 1.4, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "CANCELAR",
                style: TextStyle(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.send, size: 18),
              label: const Text(
                "ABRIR E-MAIL",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _dispararEmailSincrono(emailDestino);
              },
            ),
          ],
        );
      },
    );
  }

  /// 🚀 2. Constrói o Link Manualmente (100% à prova de falhas)
  /// 🚀 2. Constrói o Link Manualmente (100% à prova de falhas)
  Future<void> _dispararEmailSincrono(String emailDestino) async {
    final String tokenAtual = _userToken;
    final String emailAtual = _userEmail;

    final String corpo =
        '''
Olá Equipe PramilhaSVIP,

Gostaria de solicitar suporte para o seguinte assunto:
( ) Problema com Notificações
( ) Erro na Renovação de Licença
( ) Bug Visual ou Travamento
( ) Sugestão / Outros

Descrição detalhada:
[Escreva aqui o que está acontecendo e anexe imagens se necessário]

---
Dados para identificação (Não apagar):
Licença: $tokenAtual
E-mail: $emailAtual
''';

    // 🚀 Codificação manual e cirúrgica
    final String subjectEncoded = Uri.encodeComponent(
      "Suporte Técnico - PramilhaSVIP",
    );
    final String bodyEncoded = Uri.encodeComponent(corpo);

    try {
      // 🛡️ PLANO B UNIVERSAL: Sempre copia o e-mail por segurança
      await Clipboard.setData(ClipboardData(text: emailDestino));

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Abrindo webmail... O e-mail $emailDestino foi copiado caso precise!',
              ),
              backgroundColor: AppTheme.accent,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        // 🌐 SOLUÇÃO WEB: Abre o GMAIL WEB direto no navegador do usuário!
        // (Se preferir o Outlook Web, use o link comentado abaixo)
        // final String webUrl = "https://outlook.live.com/mail/0/deeplink/compose?to=$emailDestino&subject=$subjectEncoded&body=$bodyEncoded";

        final String webUrl =
            "https://mail.google.com/mail/?view=cm&fs=1&to=$emailDestino&su=$subjectEncoded&body=$bodyEncoded";

        await launchUrl(
          Uri.parse(webUrl),
          mode: LaunchMode.externalApplication, // Abre numa nova aba lindamente
        );
        debugPrint("📧 [WEB] Redirecionado para o Webmail com sucesso!");
      } else {
        // 📱 MOBILE: launchUrl com mailto (Funciona perfeito no Android/iOS)
        final String mailtoLink =
            "mailto:$emailDestino?subject=$subjectEncoded&body=$bodyEncoded";

        await launchUrl(
          Uri.parse(mailtoLink),
          mode: LaunchMode.externalApplication,
        );
        debugPrint("📧 [MOBILE] App de e-mail nativo acionado!");
      }
    } catch (e) {
      debugPrint("❌ [SUPORTE] Erro ao abrir e-mail: $e");
    }
  }

  Widget _buildStatusCard() {
    final bool isVerifying = _statusConexao == "Validando Licença...";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerifying
              ? AppTheme.accent.withOpacity(0.3)
              : (_isBloqueado
                    ? AppTheme.red.withOpacity(0.3)
                    : AppTheme.green.withOpacity(0.2)),
        ),
        boxShadow: [
          BoxShadow(
            color: isVerifying
                ? AppTheme.accent.withOpacity(0.05)
                : (_isBloqueado
                      ? AppTheme.red.withOpacity(0.05)
                      : AppTheme.green.withOpacity(0.05)),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
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
                'https://ui-avatars.com/api/?name=${Uri.encodeComponent(_userUsuario)}&background=0D1320&color=3B82F6&size=200&bold=true',
              ),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🚀 UX: Mostra um mini-spinner azul se estiver validando, ou o ponto de cor
              if (isVerifying)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: AppTheme.accent,
                    strokeWidth: 2,
                  ),
                )
              else
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
                  fontSize:
                      16, // Reduzi levemente pra encaixar o "VALIDANDO..."
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: isVerifying
                      ? AppTheme.accent
                      : (_isBloqueado ? AppTheme.red : Colors.white),
                ),
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow("USUÁRIO", _userUsuario, valueColor: Colors.white),
          const Divider(color: AppTheme.border, height: 30),

          // 🚀 AQUI ESTÁ A MUDANÇA: Substituímos o token pela nossa "Licença Fantasia"
          _buildInfoRow(
            "TIPO DE LICENÇA",
            _userVencimento == "N/A" ? "BÁSICA (Pendente)" : "VIP PREMIUM",
            valueColor: AppTheme.accent,
            isMono: true,
          ),

          const Divider(color: AppTheme.border, height: 30),
          _buildInfoRow(
            "VÁLIDA ATÉ",
            _userVencimento,
            valueColor: _getCorVencimento(_userVencimento),
          ),
          const Divider(color: AppTheme.border, height: 30),
          _buildInfoRow(
            "E-MAIL VINCULADO",
            _userEmail.toLowerCase(),
            valueColor: AppTheme.muted,
            size: 12,
          ),
          const Divider(color: AppTheme.border, height: 30),
          _buildInfoRow(
            "ID PLANILHA CLIENTE",
            _userIdPlanilha,
            isMono: true,
            size: 10,
          ),
          const Divider(color: AppTheme.border, height: 30),
          _buildInfoRow(
            "VINCULADO AO APARELHO",
            _deviceId,
            isMono: true,
            size: 10,
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _isSaindo
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppTheme.red,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.power_settings_new),
        label: Text(
          _isSaindo ? "DESCONECTANDO..." : "DESCONECTAR APARELHO",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        onPressed: _isSaindo ? null : _fazerLogoff,
      ),
    );
  }

  Widget _buildRenovarLicencaButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.green, width: 1.5),
          foregroundColor: AppTheme
              .esmerald, // Certifique-se de que essa cor existe no seu AppTheme
          backgroundColor: AppTheme.green.withOpacity(0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // 🚀 1. Correção: Trocamos "child" por "icon"
        icon: const Icon(Icons.autorenew_rounded, size: 22),
        label: const Text(
          "RENOVAR LICENÇA",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        // 🚀 2. Lógica para buscar a URL no Gist e abrir o site
        onPressed: _isSaindo
            ? null
            : () async {
                try {
                  // Busca a configuração mais recente do seu Gist
                  final config = await DiscoveryService().getConfig();

                  // 🚀 Proteção dupla: verifica se é nulo E se está vazio
                  String urlString = config?.urlRenovacaoLicenca ?? "";
                  if (urlString.trim().isEmpty) {
                    urlString =
                        "https://pramilhasweb.suportvip.com/"; // Fallback seguro
                  }

                  final Uri uri = Uri.parse(urlString);

                  // Lança o navegador externo
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    debugPrint("⚠️ Não foi possível abrir o link: $urlString");
                  }
                } catch (e) {
                  debugPrint("❌ Erro ao abrir link de renovação: $e");
                }
              },
      ),
    );
  }

  Widget _buildInfoRow(
    String title,
    String value, {
    Color valueColor = AppTheme.muted,
    bool isMono = false,
    double size = 13,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: size,
            fontWeight: FontWeight.bold,
            fontFamily: isMono ? 'monospace' : null,
          ),
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
  const FilterBottomSheet({
    super.key,
    required this.filtrosAtuais,
    required this.onFiltrosSalvos,
  });

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
  final Set<String> _regioesExpandidas = {};

  @override
  void initState() {
    super.initState();
    _tempFiltros = UserFilters(
      latamAtivo: widget.filtrosAtuais.latamAtivo,
      smilesAtivo: widget.filtrosAtuais.smilesAtivo,
      azulAtivo: widget.filtrosAtuais.azulAtivo,
      outrosAtivo: widget.filtrosAtuais.outrosAtivo,
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

    // =========================================================================
    // 🌍 QoL VIP: Popula o Dicionário Estático de IATAs instantaneamente
    // =========================================================================
    if (list.isNotEmpty) {
      for (String aero in list) {
        final partes = aero.split(' - ');
        if (partes.length >= 2) {
          final String iata = partes[0].trim().toUpperCase();
          final String nome = partes[1].trim();

          AirportCache.iataToFullName[iata] = nome;
        }
      }
    }

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
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Row(
      children: [
        Icon(Icons.radar, color: AppTheme.green),
        SizedBox(width: 10),
        Text(
          "FILTRAGEM AVANÇADA",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildCompanySwitches() {
    return Column(
      children: [
        _buildSwitch(
          "LATAM",
          const Color(0xFFF43F5E),
          _tempFiltros.latamAtivo,
          (bool val) => setState(() => _tempFiltros.latamAtivo = val),
        ),
        _buildSwitch(
          "SMILES",
          const Color(0xFFF59E0B),
          _tempFiltros.smilesAtivo,
          (bool val) => setState(() => _tempFiltros.smilesAtivo = val),
        ),
        _buildSwitch(
          "AZUL",
          const Color(0xFF38BDF8),
          _tempFiltros.azulAtivo,
          (bool val) => setState(() => _tempFiltros.azulAtivo = val),
        ),
        _buildSwitch(
          "OUTROS INTERNACIONAIS (TAP, AA, IBERIA...)",
          const Color(0xFF9333EA), // Um roxo elegante para diferenciar
          _tempFiltros.outrosAtivo,
          (bool val) => setState(() => _tempFiltros.outrosAtivo = val),
        ),
      ],
    );
  }

  Widget _buildSwitch(
    String label,
    Color activeColor,
    bool value,
    Function(bool) onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      activeColor: activeColor,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildLocationFilters() {
    if (_isLoadingAeros) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }
    return Column(
      children: [
        _buildAutocompleteChips(
          "Origens",
          _tempFiltros.origens,
          _origensController,
          _origensFocus,
        ),
        const SizedBox(height: 20),
        _buildAutocompleteChips(
          "Destinos",
          _tempFiltros.destinos,
          _destinosController,
          _destinosFocus,
        ),
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
          shadowColor: AppTheme.green.withOpacity(0.5),
        ),
        child: const Text(
          "APLICAR FILTROS",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        onPressed: () async {
          await _tempFiltros.save();
          widget.onFiltrosSalvos(_tempFiltros);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildAutocompleteChips(
    String titulo,
    List<String> listaSelecionados,
    TextEditingController controller,
    FocusNode focusNode,
  ) {
    // 🚀 Extrai as regiões dinamicamente direto da lista do servidor
    final Set<String> regioesSet = {};
    for (String aero in _todosAeroportos) {
      final partes = aero.split(' - ');
      if (partes.length >= 3) {
        regioesSet.add(partes.last.trim().toUpperCase());
      }
    }

    // 🗺️ UX VIP: Ordenação Geográfica Inteligente (De cima p/ baixo no mapa)
    final List<String> ordemGeografica = [
      "NORTE",
      "NORDESTE",
      "CENTRO-OESTE",
      "SUDESTE",
      "SUL",
      "EXTERIOR",
    ];

    final List<String> regioes = regioesSet.toList()
      ..sort((a, b) {
        int indexA = ordemGeografica.indexOf(a);
        int indexB = ordemGeografica.indexOf(b);

        // Se aparecer alguma região nova na planilha que não tá na lista, joga pro final
        if (indexA == -1) indexA = 999;
        if (indexB == -1) indexB = 999;

        // Se ambas não estiverem na lista, ordena alfabeticamente entre elas
        if (indexA == 999 && indexB == 999) return a.compareTo(b);

        return indexA.compareTo(indexB);
      });

    return Column(
      // ... O resto da função continua exatamente igual a partir daqui ...
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              titulo.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🧹 O BOTÃO DE LIMPEZA RÁPIDA (Só aparece se tiver algo)
                if (listaSelecionados.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        listaSelecionados
                            .clear(); // 🧨 Zera a lista instantaneamente
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_sweep,
                            color: AppTheme.red.withOpacity(0.8),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "Limpar",
                            style: TextStyle(
                              color: AppTheme.red.withOpacity(0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (listaSelecionados.isNotEmpty) const SizedBox(width: 8),

                // 🚀 O BOTÃO DE DROPDOWN DE REGIÕES
                if (regioes.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: "Adicionar por Região",
                    icon: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.travel_explore,
                          color: AppTheme.accent,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          "Regiões",
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    color: AppTheme.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (String regiaoEscolhida) {
                      setState(() {
                        for (String aero in _todosAeroportos) {
                          if (aero.toUpperCase().endsWith(regiaoEscolhida) &&
                              !listaSelecionados.contains(aero)) {
                            listaSelecionados.add(aero);
                          }
                        }
                      });
                    },
                    itemBuilder: (BuildContext context) {
                      return regioes.map((String regiao) {
                        return PopupMenuItem<String>(
                          value: regiao,
                          child: Text(
                            "🌍 Adicionar $regiao",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList();
                    },
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        const SizedBox(height: 10),

        // 🚀 O NOVO WRAP COM INTELIGÊNCIA DE AGRUPAMENTO
        Builder(
          builder: (context) {
            Map<String, List<String>> agrupado = {};
            List<String> avulsos = [];

            // Separa quem tem região de quem não tem
            for (String item in listaSelecionados) {
              final partes = item.split(' - ');
              if (partes.length >= 3) {
                agrupado
                    .putIfAbsent(partes.last.trim().toUpperCase(), () => [])
                    .add(item);
              } else {
                avulsos.add(item);
              }
            }

            List<Widget> chips = [];

            // 1. Aeroportos Avulsos (Sem região)
            for (String item in avulsos) {
              chips.add(
                Chip(
                  label: Text(
                    item,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  backgroundColor: AppTheme.card,
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppTheme.red,
                  ),
                  onDeleted: () =>
                      setState(() => listaSelecionados.remove(item)),
                ),
              );
            }

            // 2. Regiões Agrupadas
            agrupado.forEach((regiao, aeros) {
              final String key = "${titulo}_$regiao";

              if (aeros.length >= 2) {
                // Se escolheu 2 ou mais, agrupa!
                if (_regioesExpandidas.contains(key)) {
                  // 🔽 MODO EXPANDIDO (Mostra o botão de ocultar + todos os aeroportos)
                  chips.add(
                    InputChip(
                      label: Text(
                        "🔽 Ocultar $regiao",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: AppTheme.border,
                      onPressed: () =>
                          setState(() => _regioesExpandidas.remove(key)),
                    ),
                  );
                  for (String aero in aeros) {
                    chips.add(
                      Chip(
                        label: Text(
                          aero,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: AppTheme.card,
                        deleteIcon: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppTheme.red,
                        ),
                        onDeleted: () =>
                            setState(() => listaSelecionados.remove(aero)),
                      ),
                    );
                  }
                } else {
                  // 🌍 MODO COMPACTO (A Pílula VIP)
                  chips.add(
                    InputChip(
                      label: Text(
                        "🌍 Região: $regiao (${aeros.length})",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: AppTheme.accent.withOpacity(0.3),
                      side: const BorderSide(color: AppTheme.accent),
                      deleteIcon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.red,
                      ),
                      onDeleted: () => setState(
                        () => listaSelecionados.removeWhere(
                          (e) => aeros.contains(e),
                        ),
                      ), // Apaga todos!
                      onPressed: () => setState(
                        () => _regioesExpandidas.add(key),
                      ), // Expande!
                    ),
                  );
                }
              } else {
                // Só tem 1 aeroporto dessa região, exibe normalzinho
                for (String aero in aeros) {
                  chips.add(
                    Chip(
                      label: Text(
                        aero,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: AppTheme.card,
                      deleteIcon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.red,
                      ),
                      onDeleted: () =>
                          setState(() => listaSelecionados.remove(aero)),
                    ),
                  );
                }
              }
            });

            return Wrap(spacing: 8.0, runSpacing: 8.0, children: chips);
          },
        ),
        if (listaSelecionados.isNotEmpty) const SizedBox(height: 10),
        Autocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty)
              return const Iterable<String>.empty();
            return _todosAeroportos.where(
              (String aeroporto) =>
                  aeroporto.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  ) &&
                  !listaSelecionados.contains(aeroporto),
            );
          },
          onSelected: (String selecao) {
            setState(() {
              listaSelecionados.add(selecao);
              controller.clear();
            });
          },
          fieldViewBuilder:
              (
                BuildContext context,
                TextEditingController fieldTextEditingController,
                FocusNode fieldFocusNode,
                VoidCallback onFieldSubmitted,
              ) {
                return TextField(
                  controller: fieldTextEditingController,
                  focusNode: fieldFocusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Adicionar $titulo...",
                    hintStyle: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppTheme.muted,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: AppTheme.bg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.accent),
                    ),
                    suffixIcon: fieldTextEditingController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => fieldTextEditingController.clear(),
                          )
                        : null,
                  ),
                  onSubmitted: (String value) {
                    if (value.trim().isNotEmpty &&
                        !listaSelecionados.contains(value.toUpperCase())) {
                      setState(() {
                        listaSelecionados.add(value.toUpperCase());
                        fieldTextEditingController.clear();
                        fieldFocusNode.requestFocus();
                      });
                    }
                  },
                );
              },
          optionsViewBuilder:
              (
                BuildContext context,
                Function(String) onSelected,
                Iterable<String> options,
              ) {
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
                            title: Text(
                              option,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
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
