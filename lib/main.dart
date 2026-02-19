import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'login_screen.dart'; // Importa a tela neon

void main() {
  runApp(const MilhasAlertApp());
}

class MilhasAlertApp extends StatelessWidget {
  const MilhasAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MilhasAlert',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashRouter(), // O guarda de trânsito
    );
  }
}

// ==========================================
// ROTEADOR INICIAL (Verifica se já logou)
// ==========================================
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _checkLogin() async {
    bool firstUse = await AuthService().isFirstUse();
    
    // Pequeno delay para a tela não piscar agressivamente
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
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    );
  }
}

// ==========================================
// CONTROLADOR DE NAVEGAÇÃO (As 3 Abas)
// ==========================================
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 1; // Começa na Licença

  final List<Widget> _screens = [
    const AlertsScreen(),
    const LicenseScreen(),
    const SmsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.green,
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

// --- PLACEHOLDERS ---
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("✈️ ALERTAS")),
    body: const Center(child: Text("Feed de Emissões", style: TextStyle(color: AppTheme.muted))),
  );
}

class SmsScreen extends StatelessWidget {
  const SmsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("💬 SMS CONNECTOR")),
    body: const Center(child: Text("Módulo Legado", style: TextStyle(color: AppTheme.muted))),
  );
}

// ==========================================
// TELA 2: LICENÇA (O Dashboard com botão Sair)
// ==========================================
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
  String _statusConexao = "Verificando Servidor...";

  @override
  void initState() {
    super.initState();
    _inicializarSistema();
  }

  void _inicializarSistema() async {
    setState(() => _statusConexao = "Validando Licença...");
    String id = await _auth.getDeviceId();
    Map<String, String> dados = await _auth.getDadosUsuario();
    AuthStatus status = await _auth.validarAcessoDiario();

    setState(() {
      _deviceId = id;
      _userToken = dados['token']!;
      _userEmail = dados['email']!;
      
      if (status == AuthStatus.autorizado) {
        _statusConexao = "🟢 Serviço Ativo";
      } else {
        _statusConexao = "⛔ BLOQUEADO";
      }
    });
  }

  // 🔴 FUNÇÃO DE LOGOFF (Sair)
  void _fazerLogoff() async {
    // Aqui no futuro chamaremos o GAS para limpar a coluna D ou E
    await _auth.logout();
    
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashRouter()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🪪 LICENÇA"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppTheme.accent), onPressed: _inicializarSistema)
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Status do Serviço
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, 
                      color: AppTheme.green, 
                      boxShadow: [BoxShadow(color: AppTheme.green, blurRadius: 20, spreadRadius: -10)]
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_statusConexao, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Info Device e Licença (Conforme Wireframe)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("LICENÇA", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  Text(_userToken, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                  const SizedBox(height: 15),
                  
                  const Text("E-MAIL VINCULADO", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  Text(_userEmail, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 15),

                  const Text("VINCULADO AO APARELHO", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  SelectableText(_deviceId, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
            const Spacer(),
            
            // BOTÃO DE SAIR
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.red),
                  foregroundColor: AppTheme.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
                icon: const Icon(Icons.logout),
                label: const Text("DESCONECTAR APARELHO"),
                onPressed: _fazerLogoff,
              ),
            )
          ],
        ),
      ),
    );
  }
}