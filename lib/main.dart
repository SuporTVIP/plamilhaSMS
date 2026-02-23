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
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 🚀 NOVO
import 'utils/web_window_manager.dart';

// Instância global de Notificações
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 INICIALIZAÇÃO DAS NOTIFICAÇÕES (Configuração para Android)
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MilhasAlertApp());
}

// ==========================================
// APP ROOT (MaterialApp com Tema)
// ==========================================
class MilhasAlertApp extends StatelessWidget {
  const MilhasAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Milhas Alert',
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
  void initState() {
    super.initState();
    // 🚀 Chama a função que se adapta automaticamente (Faz nada no celular, desloga na Web)
    registerWebCloseListener(); 
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
  final List<Alert> _listaAlertasTodos = []; // Guarda TODOS os alertas da planilha
  List<Alert> _listaAlertasFiltrados = [];   // O que realmente aparece na tela
  bool _isCarregando = true;
  
  UserFilters _filtros = UserFilters(); // 🚀 Instância dos Filtros

  // 🚀 O REPRODUTOR DE ÁUDIO
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _carregarFiltros(); // Puxa da memória primeiro
  }

  void _carregarFiltros() async {
    _filtros = await UserFilters.load();
    _iniciarMotorDeTracao();
  }

void _iniciarMotorDeTracao() {
    _alertService.startMonitoring();

    _alertService.alertStream.listen((novosAlertas) async {
      if (mounted) {
        List<Alert> novosQuePassaram = novosAlertas.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();

        setState(() {
          _listaAlertasTodos.insertAll(0, novosAlertas);
          _aplicarFiltrosNaTela(); 
          _isCarregando = false;
        });

        // 🚀 TOCA O SOM E GERA O AVISO NO CELULAR!
        if (novosQuePassaram.isNotEmpty) {
          try {
            await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
            _mostrarNotificacao(novosQuePassaram.first); // Chama a notificação do primeiro card novo
          } catch (e) {
            print("Erro ao tocar som: $e");
          }
        }
      }
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isCarregando) setState(() => _isCarregando = false);
    });
  }

  // 🚀 FUNÇÃO QUE CRIA A NOTIFICAÇÃO NATIVA
  Future<void> _mostrarNotificacao(Alert alerta) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'emissao_vip', // ID do Canal
      'Emissões FãMilhas', // Nome do Canal
      channelDescription: 'Avisos de novas passagens',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      alerta.id.hashCode, // ID Único
      '✈️ ${alerta.programa} - Nova Oportunidade!', // Título
      alerta.trecho != "N/A" ? alerta.trecho : alerta.mensagem, // Corpo
      platformChannelSpecifics,
    );
  }

  // 🚀 FUNÇÃO QUE CORTA A LISTA COM BASE NAS ESCOLHAS DO USUÁRIO
  void _aplicarFiltrosNaTela() {
    setState(() {
      _listaAlertasFiltrados = _listaAlertasTodos.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();
    });
  }

  @override
  void dispose() {
    _alertService.stopMonitoring();
    super.dispose();
  }

  // 🚀 AÇÃO DO BOTÃO DE CIMA: ABRE O PAINEL E ESCUTA A RESPOSTA
  void _abrirPainelFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que o teclado empurre a tela
      backgroundColor: Colors.transparent,
      builder: (ctx) => FilterBottomSheet(
        filtrosAtuais: _filtros,
        onFiltrosSalvos: (novosFiltros) {
          _filtros = novosFiltros;
          _aplicarFiltrosNaTela(); // Atualiza a lista na hora que fecha o painel
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 🚀 CABEÇALHO ESTILIZADO CYBERPUNK
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, color: AppTheme.accent, size: 22),
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
        actions: [
          IconButton(
            icon: Icon(Icons.tune, color: _filtros.origens.isNotEmpty || _filtros.destinos.isNotEmpty || !_filtros.azulAtivo || !_filtros.latamAtivo || !_filtros.smilesAtivo ? AppTheme.green : AppTheme.accent), // Fica verde se tiver filtro ativo
            tooltip: "Filtros",
            onPressed: _abrirPainelFiltros, // 🚀 Chama o painel
          )
        ],
      ),
      body: _isCarregando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _listaAlertasFiltrados.isEmpty // Muda para usar a lista filtrada
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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _listaAlertasFiltrados.length, // Usa a lista filtrada
                  itemBuilder: (context, index) {
                    final alerta = _listaAlertasFiltrados[index];
                    return AlertCard(alerta: alerta);
                  },
                ),
    );
  }
}

// ==========================================
// COMPONENTE: CARD DO ALERTA (Retrátil e Elegante)
// ==========================================
class AlertCard extends StatefulWidget {
  final Alert alerta;
  const AlertCard({super.key, required this.alerta});

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool _isExpanded = false;

  void _abrirLink() async {
    if (widget.alerta.link == null || widget.alerta.link!.isEmpty) return;
    final Uri url = Uri.parse(widget.alerta.link!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication); // Abre no navegador do celular
    } else {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Não foi possível abrir o link.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 PALETA DE CORES SUTIL (Cyberpunk Dark)
    Color corPrincipal = AppTheme.accent;
    Color corFundo = AppTheme.card;
    
    final prog = widget.alerta.programa.toUpperCase();
    if (prog.contains("AZUL")) {
      corPrincipal = const Color(0xFF38BDF8); // Azul claro
      corFundo = const Color(0xFF0C1927);     // Fundo com tintura azul muito escuro
    } else if (prog.contains("LATAM")) {
      corPrincipal = const Color(0xFFF43F5E); // Vermelho/Rosa
      corFundo = const Color(0xFF230D14);     // Fundo com tintura vermelha
    } else if (prog.contains("SMILES")) {
      corPrincipal = const Color(0xFFF59E0B); // Laranja
      corFundo = const Color(0xFF22160A);     // Fundo com tintura laranja
    }

    String horaFormatada = "${widget.alerta.data.hour.toString().padLeft(2, '0')}:${widget.alerta.data.minute.toString().padLeft(2, '0')}";

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isExpanded ? corPrincipal.withOpacity(0.5) : AppTheme.border),
        boxShadow: _isExpanded ? [BoxShadow(color: corPrincipal.withOpacity(0.1), blurRadius: 10, spreadRadius: 1)] : [],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded), // 🚀 Expande/Recolhe
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 CABEÇALHO RESUMIDO (Sempre Visível)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Ícone da Companhia
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: corPrincipal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.flight_takeoff, color: corPrincipal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  
                  // Info Principal (Trecho e Milhas)
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
                  
                  // Hora e Seta
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

            // 🔹 DETALHES EXPANDIDOS (Aparece ao clicar)
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
                        _buildInfoColumn("VENDA FÃ", widget.alerta.valorEmissao, isHighlight: true),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Texto Original Oculto (Apenas para contexto se o usuário quiser ler tudo)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        widget.alerta.mensagem,
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontStyle: FontStyle.italic),
                        maxLines: 4, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 🚀 BOTÃO DE IR PARA O SITE
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

  // Widget ajudante para as coluninhas de dados
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
// TELA 3: SMS CONNECTOR (Painel de Operações)
// ==========================================
class SmsScreen extends StatefulWidget {
  const SmsScreen({super.key});

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  bool _isMonitoring = false;
  
  // 🚀 Simulador de Console (Ficará real quando ligarmos no Emulador)
  final List<String> _logs = [
    "[SISTEMA] Módulo de interceptação pronto.",
    "[AVISO] Aguardando comando de inicialização...",
  ];

  void _toggleMonitoring() {
    setState(() {
      _isMonitoring = !_isMonitoring;
      String hora = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
      
      if (_isMonitoring) {
        _logs.insert(0, "[$hora] 🟢 Monitoramento NATIVO ATIVADO.");
        _logs.insert(0, "[$hora] 📡 Escutando porta SMS de entrada...");
      } else {
        _logs.insert(0, "[$hora] 🔴 Monitoramento PAUSADO pelo usuário.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 🚀 CABEÇALHO PADRONIZADO
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
            // 🚀 STATUS CARD (Indicador de Funcionamento)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
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
                  ).animate(target: _isMonitoring ? 1 : 0).shimmer(duration: 2.seconds, color: Colors.white24),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          color: !_isMonitoring ? AppTheme.red : AppTheme.green,
                          boxShadow: [BoxShadow(color: !_isMonitoring ? AppTheme.red : AppTheme.green, blurRadius: 10)]
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

            // 🚀 BOTÃO DE IGNIÇÃO
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMonitoring ? AppTheme.card : AppTheme.accent,
                  foregroundColor: _isMonitoring ? AppTheme.red : Colors.white,
                  side: _isMonitoring ? const BorderSide(color: AppTheme.red) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: _isMonitoring ? 0 : 10,
                  shadowColor: AppTheme.accent.withOpacity(0.5),
                ),
                icon: Icon(_isMonitoring ? Icons.stop_circle : Icons.play_circle_fill, size: 24),
                label: Text(
                  _isMonitoring ? "DESLIGAR CAPTURA" : "INICIAR CAPTURA NATIVA",
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 14),
                ),
                onPressed: _toggleMonitoring,
              ),
            ),
            const SizedBox(height: 30),

            // 🚀 CONSOLE DE LOGS (Estilo Terminal)
            const Row(
              children: [
                Icon(Icons.terminal, color: AppTheme.muted, size: 18),
                SizedBox(width: 8),
                Text("CONSOLE DE ATIVIDADES", style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF030508), // Fundo quase preto para dar cara de prompt
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: SelectableText(
                        _logs[index],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: _logs[index].contains("🔴") 
                              ? AppTheme.red 
                              : _logs[index].contains("🟢") || _logs[index].contains("📡")
                                  ? AppTheme.green 
                                  : AppTheme.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        // 🚀 CABEÇALHO PADRONIZADO IGUAL AO DO ALERTA
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
            // Status do Serviço (Elevado)
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
                  // Avatar
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
                  
                  // Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          color: _isBloqueado ? AppTheme.red : AppTheme.green,
                          boxShadow: [BoxShadow(color: _isBloqueado ? AppTheme.red : AppTheme.green, blurRadius: 10)]
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
            
            // Info Expanded (Visual Clean)
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
            
            // BOTÃO DE SAIR ESTILIZADO
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.red, width: 1.5),
                  foregroundColor: AppTheme.red,
                  backgroundColor: AppTheme.red.withOpacity(0.05), // Fundo levemente vermelho
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

  // 🚀 WIDGET AUXILIAR PARA ALINHAR AS INFORMAÇÕES
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
// COMPONENTE: PAINEL DE FILTROS COM CHIPS (BOTTOM SHEET)
// ==========================================
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
    // Clona os filtros para edição
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
        bottom: MediaQuery.of(context).viewInsets.bottom + 20, // Empurra pra cima se o teclado abrir
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

            // 🚀 Toggle Switches (Companhias)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("LATAM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              activeColor: const Color(0xFFF43F5E), // Vermelho Latam
              value: _tempFiltros.latamAtivo,
              onChanged: (val) => setState(() => _tempFiltros.latamAtivo = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Smiles", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              activeColor: const Color(0xFFF59E0B), // Laranja Smiles
              value: _tempFiltros.smilesAtivo,
              onChanged: (val) => setState(() => _tempFiltros.smilesAtivo = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("AZUL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              activeColor: const Color(0xFF38BDF8), // Azul
              value: _tempFiltros.azulAtivo,
              onChanged: (val) => setState(() => _tempFiltros.azulAtivo = val),
            ),
            
            const Divider(color: AppTheme.border, height: 30),

            // 🚀 CHIPS: ORIGEM E DESTINO
            if (_isLoadingAeros) 
              const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            else ...[
              _buildAutocompleteChips("Origens", _tempFiltros.origens),
              const SizedBox(height: 20),
              _buildAutocompleteChips("Destinos", _tempFiltros.destinos),
            ],
            
            const SizedBox(height: 30),

            // Botão Salvar
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

  // 🚀 O MOTOR DE AUTOCOMPLETAR COM CHIPS
  Widget _buildAutocompleteChips(String titulo, List<String> listaSelecionados) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: const TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        
        // Área de exibição dos Chips Selecionados
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: listaSelecionados.map((item) {
            return Chip(
              label: Text(item, style: const TextStyle(fontSize: 12, color: Colors.white)),
              backgroundColor: AppTheme.card,
              deleteIcon: const Icon(Icons.close, size: 16, color: AppTheme.red),
              side: const BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onDeleted: () {
                setState(() => listaSelecionados.remove(item));
              },
            );
          }).toList(),
        ),
        
        if (listaSelecionados.isNotEmpty) const SizedBox(height: 10),

        // O Input de Busca
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
            return _todosAeroportos.where((aeroporto) => 
              aeroporto.toLowerCase().contains(textEditingValue.text.toLowerCase()) && 
              !listaSelecionados.contains(aeroporto) // Esconde os que já foram selecionados
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
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accent)),
              ),
              onSubmitted: (value) {
                // Permite adicionar texto livre se o usuário apertar Enter e não clicar na sugestão
                if (value.trim().isNotEmpty && !listaSelecionados.contains(value.toUpperCase())) {
                  setState(() {
                    listaSelecionados.add(value.toUpperCase());
                    textEditingController.clear();
                    focusNode.requestFocus(); // Mantém o teclado aberto para add mais
                  });
                }
              },
            );
          },
          // Estiliza a caixinha de sugestões que flutua
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
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