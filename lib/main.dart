import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'login_screen.dart'; // Importa a tela neon
import 'models/alert.dart';
import 'services/alert_service.dart';

void main() {
  runApp(const MilhasAlertApp());
}

class MilhasAlertApp extends StatelessWidget {
  const MilhasAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlaMilhasAlert',
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
// ==========================================
// TELA 1: ALERTAS (Feed em Tempo Real)
// ==========================================
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final AlertService _alertService = AlertService();
  final List<Alert> _listaAlertas = [];
  bool _isCarregando = true;

  @override
  void initState() {
    super.initState();
    _iniciarMotorDeTracao();
  }

  void _iniciarMotorDeTracao() {
    // 1. Inicia o Polling Dinâmico (Modo Economia Automático)
    _alertService.startMonitoring();

    // 2. Fica escutando a "Stream" (Tubo de dados) por novos alertas
    _alertService.alertStream.listen((novosAlertas) {
      if (mounted) {
        setState(() {
          // Adiciona os novos alertas no topo da lista
          _listaAlertas.insertAll(0, novosAlertas);
          _isCarregando = false;
        });
      }
    });

    // Timeout de carregamento inicial (se a planilha estiver vazia ou demorar)
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isCarregando) {
        setState(() => _isCarregando = false);
      }
    });
  }

  @override
  void dispose() {
    // Quando fechar o app, para o motor para economizar bateria
    _alertService.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("✈️ FEED DE EMISSÕES"),
        actions: [
          // O Botão de Filtros que implementaremos no próximo passo
          IconButton(
            icon: const Icon(Icons.tune, color: AppTheme.accent),
            tooltip: "Filtros",
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Filtros em desenvolvimento..."))
              );
            },
          )
        ],
      ),
      body: _isCarregando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _listaAlertas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.airplanemode_off, size: 64, color: AppTheme.border),
                      const SizedBox(height: 16),
                      const Text("Nenhuma emissão recente.", style: TextStyle(color: AppTheme.muted)),
                      const Text("Aguardando o radar...", style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _listaAlertas.length,
                  itemBuilder: (context, index) {
                    final alerta = _listaAlertas[index];
                    return AlertCard(alerta: alerta); // Componente visual do card
                  },
                ),
    );
  }
}

// ==========================================
// COMPONENTE: CARD DO ALERTA (Visual Cyberpunk)
// ==========================================
class AlertCard extends StatelessWidget {
  final Alert alerta;
  
  const AlertCard({super.key, required this.alerta});

  @override
  Widget build(BuildContext context) {
    // Define a cor da badge de acordo com o programa
    Color corPrograma = AppTheme.accent;
    if (alerta.programa.toUpperCase().contains("AZUL")) corPrograma = Colors.lightBlue;
    if (alerta.programa.toUpperCase().contains("LATAM")) corPrograma = Colors.redAccent;
    if (alerta.programa.toUpperCase().contains("SMILES")) corPrograma = Colors.orangeAccent;

    // Formata a data (Ex: 14:30)
    String horaFormatada = "${alerta.data.hour.toString().padLeft(2, '0')}:${alerta.data.minute.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho do Card (Programa + Hora)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.airplane_ticket, color: corPrograma, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      alerta.programa.toUpperCase(),
                      style: TextStyle(color: corPrograma, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: AppTheme.muted, size: 14),
                    const SizedBox(width: 4),
                    Text(horaFormatada, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
                )
              ],
            ),
          ),
          
          // Corpo do Card (Mensagem)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              alerta.mensagem,
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.text),
            ),
          ),

          // Rodapé do Card (Link de Emissão)
          if (alerta.link != null && alerta.link!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.green,
                    side: const BorderSide(color: AppTheme.green),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                  ),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text("ABRIR OFERTA"),
                  onPressed: () {
                    // Futuramente abriremos a WebView ou Link Externo aqui
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Link copiado/abrindo..."))
                    );
                  },
                ),
              ),
            )
        ],
      ),
    );
  }
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
  String _userUsuario = "...";
  String _userVencimento = "...";
  String _userIdPlanilha = "...";
  String _statusConexao = "Verificando Servidor...";
  bool _isBloqueado = false;
  bool _isSaindo = false; // Flag para evitar múltiplos cliques no botão de logoff

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
      _userUsuario = dados['usuario']!; // Exibe o nome do usuário
      _userVencimento = dados['vencimento']!; // Exibe o vencimento
      _userIdPlanilha = dados['idPlanilha']!; // Exibe o ID da planilha para debug

      _isBloqueado = (status != AuthStatus.autorizado);
      _statusConexao = (status == AuthStatus.autorizado) ? "Serviço Ativo" : "⛔ BLOQUEADO";
    });
  }

void _fazerLogoff() async {
    setState(() => _isSaindo = true); // Ativa o loading
    await _auth.logout(); // Aguarda a planilha ser limpa
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashRouter()));
    }
  }

  // 🚀 LÓGICA DE CORES DA LICENÇA (Inteligência de Datas)
  Color _getCorVencimento(String dataVencimentoStr) {
    if (dataVencimentoStr == "..." || dataVencimentoStr == "N/A") return AppTheme.muted;

    try {
      // Divide a string "DD/MM/YYYY"
      List<String> partes = dataVencimentoStr.split('/');
      if (partes.length != 3) return AppTheme.muted;

      // Cria os objetos de data comparáveis (ano, mês, dia)
      DateTime validade = DateTime(int.parse(partes[2]), int.parse(partes[1]), int.parse(partes[0]));
      DateTime hoje = DateTime.now();
      
      // Zera as horas para comparar apenas os dias úteis
      hoje = DateTime(hoje.year, hoje.month, hoje.day);
      
      // Calcula a diferença em dias
      int diasRestantes = validade.difference(hoje).inDays;

      if (diasRestantes <= 3) {
        return AppTheme.red; // 🔴 0 a 3 dias (Crítico)
      } else if (diasRestantes <= 7) {
        return AppTheme.yellow; // 🟡 4 a 7 dias (Alerta) - Laranja/Amarelo
      } else {
        return AppTheme.green; // 🟢 Mais de 7 dias (Tranquilo)
      }
    } catch (e) {
      return AppTheme.muted; // Fallback em caso de erro na string
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
      body: SingleChildScrollView( 
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Status do Serviço (REFORMULADO)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  // 🚀 FOTO PROVISÓRIA (Avatar com iniciais)
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: AppTheme.border,
                    // Usa a API gratuita do ui-avatars para gerar uma imagem com o nome do usuário
                    backgroundImage: NetworkImage(
                      'https://ui-avatars.com/api/?name=${Uri.encodeComponent(_userUsuario)}&background=0D1320&color=3B82F6&size=200'
                    ),
                  ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
                  
                  const SizedBox(height: 20),
                  
                  // 🚀 BOLA VERDE AO LADO DO TEXTO
                 Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 14, 
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          color: _isBloqueado ? AppTheme.red : AppTheme.green, 
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(_statusConexao, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Info Expanded
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("USUÁRIO", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  Text(_userUsuario, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 15),

                  const Text("LICENÇA", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  Text(_userToken, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                  const SizedBox(height: 15),
                  
                  const Text("VÁLIDA ATÉ", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  // 🚀 AQUI A COR MUDA DINAMICAMENTE
                  Text(
                    _userVencimento, 
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.bold,
                      color: _getCorVencimento(_userVencimento) // Chamada da inteligência de cor
                    )
                  ),
                  const SizedBox(height: 15),

                  const Text("E-MAIL VINCULADO", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  Text(_userEmail, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 15),

                  const Text("ID DA PLANILHA CLIENTE", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  SelectableText(_userIdPlanilha, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 15),

                  const Text("VINCULADO AO APARELHO", style: TextStyle(color: AppTheme.muted, fontSize: 10, letterSpacing: 1.5)),
                  SelectableText(_deviceId, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
 // BOTÃO DE SAIR COM LOADING
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.red),
                  foregroundColor: AppTheme.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
                icon: _isSaindo 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.red, strokeWidth: 2)) 
                  : const Icon(Icons.logout),
                label: Text(_isSaindo ? "DESCONECTANDO..." : "DESCONECTAR APARELHO"),
                onPressed: _isSaindo ? null : _fazerLogoff,
              ),
            )
          ],
        ),
      ),
    );
  }
}