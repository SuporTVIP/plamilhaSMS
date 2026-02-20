import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'login_screen.dart'; // Importa a tela neon
import 'models/alert.dart';
import 'services/alert_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/filter_service.dart';
import 'package:audioplayers/audioplayers.dart';

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
        // 🚀 1. Antes de atualizar a tela, verifica se ALGUNS dos NOVOS alertas passa no filtro
        List<Alert> novosQuePassaram = novosAlertas.where((a) => _filtros.alertaPassaNoFiltro(a)).toList();

        setState(() {
          _listaAlertasTodos.insertAll(0, novosAlertas);
          _aplicarFiltrosNaTela(); 
          _isCarregando = false;
        });

        // 🚀 2. TOCA O SOM! (Se chegou algo novo e não foi bloqueado pelo filtro)
        if (novosQuePassaram.isNotEmpty) {
          try {
            await _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
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
        title: const Text("✈️ FEED DE EMISSÕES"),
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

// ==========================================
// COMPONENTE: PAINEL DE FILTROS (BOTTOM SHEET)
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
  final _origemController = TextEditingController();
  final _destinoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fazemos uma cópia para não alterar direto até o usuário clicar em "Salvar"
    _tempFiltros = UserFilters(
      latamAtivo: widget.filtrosAtuais.latamAtivo,
      smilesAtivo: widget.filtrosAtuais.smilesAtivo,
      azulAtivo: widget.filtrosAtuais.azulAtivo,
      origens: widget.filtrosAtuais.origens,
      destinos: widget.filtrosAtuais.destinos,
    );
    _origemController.text = _tempFiltros.origens;
    _destinoController.text = _tempFiltros.destinos;
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.all(Radius.circular(10))))),
            const SizedBox(height: 20),
            const Text("✈️ Filtro de Emissões", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 24),

            // Toggle Switches (Companhias)
            SwitchListTile(
              title: const Text("LATAM", style: TextStyle(color: Colors.white)),
              activeColor: const Color(0xFFF43F5E), // Vermelho Latam
              value: _tempFiltros.latamAtivo,
              onChanged: (val) => setState(() => _tempFiltros.latamAtivo = val),
            ),
            SwitchListTile(
              title: const Text("Smiles", style: TextStyle(color: Colors.white)),
              activeColor: const Color(0xFFF59E0B), // Laranja Smiles
              value: _tempFiltros.smilesAtivo,
              onChanged: (val) => setState(() => _tempFiltros.smilesAtivo = val),
            ),
            SwitchListTile(
              title: const Text("AZUL", style: TextStyle(color: Colors.white)),
              activeColor: const Color(0xFF38BDF8), // Azul
              value: _tempFiltros.azulAtivo,
              onChanged: (val) => setState(() => _tempFiltros.azulAtivo = val),
            ),
            
            const Divider(color: AppTheme.border, height: 30),

            // Campos de Texto (Origem / Destino)
            TextField(
              controller: _origemController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: "Origens (ex: GRU, JPA, NAT)",
                labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
                filled: true,
                fillColor: AppTheme.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (val) => _tempFiltros.origens = val,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destinoController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: "Destinos (ex: LIS, MIA, MCO)",
                labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
                filled: true,
                fillColor: AppTheme.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (val) => _tempFiltros.destinos = val,
            ),
            const SizedBox(height: 24),

            // Botão Salvar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text("APLICAR FILTROS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                onPressed: () async {
                  await _tempFiltros.save(); // Salva no celular
                  widget.onFiltrosSalvos(_tempFiltros); // Avisa a tela principal
                  if(context.mounted) Navigator.pop(context); // Fecha o painel
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
