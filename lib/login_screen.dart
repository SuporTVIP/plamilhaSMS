import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme.dart';
import 'main.dart';
import 'services/auth_service.dart';

/// Tela de Login e Ativação do Aplicativo.
///
/// Esta tela é o portão de entrada para novos usuários ou para re-autenticação.
/// Ela coleta o e-mail e o token (chave de licença) e os valida com o servidor.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Gerencia o estado e a lógica da tela de login.
class _LoginScreenState extends State<LoginScreen> {
  // Controladores de interface para os campos de texto.
  // No Flutter, TextEditingController é usado para ler e escrever valores em widgets de texto.
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  // Instância do serviço de autenticação para processar os dados.
  final AuthService _auth = AuthService();

  // Flag de controle para exibir o indicador de progresso (spinner).
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Tenta preencher automaticamente os campos se o usuário já logou antes.
    _carregarMemoriaDosInputs();
  }

  /// Recupera os dados do último login bem-sucedido para facilitar a experiência do usuário.
  Future<void> _carregarMemoriaDosInputs() async {
    final Map<String, String> lastData = await _auth.getLastLoginData();
    if (lastData['email']!.isNotEmpty) {
      setState(() {
        _emailController.text = lastData['email']!;
        _tokenController.text = lastData['token']!;
      });
    }
  }

  /// Inicia o processo de autenticação enviando os dados para o servidor.
  Future<void> _ativarSistema() async {
    final String email = _emailController.text.trim();
    final String token = _tokenController.text.trim();

    // Validação básica local antes de tentar a conexão de rede.
    if (email.isEmpty || token.isEmpty) {
      _mostrarMensagem("Preencha todos os campos!", isErro: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Chama o serviço para validar no Google Apps Script (GAS).
      final Map<String, dynamic> result = await _auth.autenticarNoServidor(email, token);

      if (mounted) {
        setState(() => _isLoading = false);

        if (result['sucesso'] == true) {
          _mostrarMensagem("✅ ${result['mensagem']}");

          // Navega para a interface principal e remove o login da pilha (impede retorno).
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainNavigator()),
          );
        } else {
          _mostrarMensagem("❌ Erro: ${result['mensagem']}", isErro: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _mostrarMensagem("Falha na conexão com o servidor.", isErro: true);
      }
    }
  }

  /// Permite colar conteúdo da área de transferência (Clipboard) diretamente no campo.
  /// Muito útil para tokens longos recebidos por mensagem.
  Future<void> _colarDoClipboard(TextEditingController controller) async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        controller.text = data.text!;
      });
      _mostrarMensagem("Texto colado com sucesso!");
    }
  }

  /// Utilitário centralizado para exibir avisos rápidos (SnackBar) na tela.
  void _mostrarMensagem(String mensagem, {bool isErro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: isErro ? AppTheme.red : AppTheme.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        // SingleChildScrollView evita erros de layout quando o teclado virtual aparece.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogo(),
              const SizedBox(height: 40),
              _buildSecurityBadge(),
              const SizedBox(height: 30),
              _buildInputs(),
              const SizedBox(height: 40),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// Constrói o logotipo da marca com estilo futurista (Cyberpunk).
  Widget _buildLogo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.radar, color: AppTheme.accent, size: 40),
        const SizedBox(width: 12),
        Text(
          "PLAMILHAS",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
            // Sombra neon característica da identidade visual.
            shadows: [Shadow(color: AppTheme.accent.withOpacity(0.5), blurRadius: 20)],
          ),
        ),
        Text(
          "VIP",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 40,
            fontWeight: FontWeight.w300,
            color: AppTheme.accent,
            shadows: [Shadow(color: AppTheme.accent.withOpacity(0.5), blurRadius: 20)],
          ),
        ),
      ],
    );
  }

  /// Exibe um selo indicando que a conexão é protegida.
  Widget _buildSecurityBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield, color: AppTheme.accent, size: 20),
          SizedBox(width: 12),
          Text(
            "Autenticação de Segurança",
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Agrupa os campos de entrada de dados.
  Widget _buildInputs() {
    return Column(
      children: [
        _buildTextField(
          controller: _emailController,
          label: "E-mail de Destino",
          icon: Icons.email,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _tokenController,
          label: "Chave de Licença",
          icon: Icons.key,
          isToken: true,
        ),
      ],
    );
  }

  /// Helper genérico para criação de campos de texto estilizados.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isToken = false,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        letterSpacing: isToken ? 2 : 0,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
        filled: true,
        fillColor: AppTheme.card,
        prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
        // Adiciona o botão de colar apenas no campo de token.
        suffixIcon: isToken
          ? IconButton(
              icon: const Icon(Icons.content_paste, color: AppTheme.accent, size: 20),
              tooltip: "Colar Licença",
              onPressed: () => _colarDoClipboard(controller),
            )
          : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
      ),
    );
  }

  /// Constrói o botão principal de ativação do sistema.
  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 10,
          shadowColor: AppTheme.accent.withOpacity(0.3),
        ),
        onPressed: _isLoading ? null : _ativarSistema,
        child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text(
              "INICIAR SESSÃO",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
      ),
    );
  }
}
