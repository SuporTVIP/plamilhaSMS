import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart'; // Para animações suaves
import 'core/theme.dart';
import 'services/auth_service.dart';

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
      theme: AppTheme.darkTheme, // Usando nosso tema novo
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _auth = AuthService();
  String _deviceId = "Carregando...";
  String _statusConexao = "Verificando Servidor...";

  @override
  void initState() {
    super.initState();
    _inicializarSistema();
  }

  bool _bloqueado = false; // Novo estado para controlar a UI
  void _inicializarSistema() async {
    setState(() => _statusConexao = "Validando Licença...");

    // 1. Carrega ID
    String id = await _auth.getDeviceId();
    
    // 2. Validação "Day-Pass"
    AuthStatus status = await _auth.validarAcessoDiario();

    setState(() {
      _deviceId = id;
      
      if (status == AuthStatus.autorizado) {
        _statusConexao = "🟢 Sistema Operacional";
        _bloqueado = false;
        // Inicia monitoramento de alertas aqui, se necessário
      } else if (status == AuthStatus.bloqueado) {
        _statusConexao = "⛔ DISPOSITIVO NÃO AUTORIZADO";
        _bloqueado = true;
      } else {
        _statusConexao = "⚠️ Sem Rede (Offline)";
        _bloqueado = false; // Permitir uso offline se já tiver validado antes? (Decisão de Negócio)
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bloqueado) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 80, color: AppTheme.red),
                const SizedBox(height: 20),
                const Text(
                  "ACESSO NEGADO",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.red),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Todas as vagas de licença estão ocupadas.\n\nPara acessar, remova um dispositivo antigo na planilha (Aba Controle, Colunas B ou C).",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 40),
                SelectableText("Seu ID: $_deviceId", style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("TENTAR NOVAMENTE"),
                  onPressed: _inicializarSistema, // Tenta revalidar
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surface),
                )
              ],
            ),
          ),
        ),
      );
    }

    // ... Retorna o Scaffold normal do Dashboard se não estiver bloqueado ...
    return Scaffold(
      appBar: AppBar(
        title: const Text("DASHBOARD // MILHAS"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accent),
            onPressed: _inicializarSistema,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARTÃO DE STATUS (Animate para efeito Cyberpunk de entrada)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.card,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("STATUS DO SISTEMA", 
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(_statusConexao, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2),

            const SizedBox(height: 20),

            // CARTÃO DE LICENÇA (Device ID)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.fingerprint, color: AppTheme.accent),
                      SizedBox(width: 10),
                      Text("SUA LICENÇA (DEVICE ID)", 
                          style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SelectableText(
                    _deviceId,
                    style: const TextStyle(
                      fontFamily: 'monospace', 
                      fontSize: 14, 
                      letterSpacing: 1.2
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text("Envie este código ao administrador para liberar acesso.",
                      style: TextStyle(color: AppTheme.muted, fontSize: 10)),
                ],
              ),
            ).animate().fadeIn(delay: 300.ms).slideX(),

            const Spacer(),

            // BOTÃO DE AÇÃO (Futuro WebView)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.rocket_launch),
                label: const Text("ABRIR PAINEL DE EMISSÃO"),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("🚀 Em breve: Abrindo WebView..."))
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