import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'services/discovery_service.dart';
import 'main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final AuthService _auth = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true; // 🚀 Controle do olhinho da senha

  @override
  void initState() {
    super.initState();
    _carregarMemoriaDosInputs();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _carregarMemoriaDosInputs() async {
    final Map<String, String> dadosViejos = await _auth.getLastLoginData();
    if (dadosViejos['email']!.isNotEmpty) {
      setState(() {
        _emailController.text = dadosViejos['email']!;
        _tokenController.text = dadosViejos['token']!;
      });
    }
  }

  // 🚀 Redireciona para o site de vendas buscando a URL dinâmica do Gist
  Future<void> _abrirSiteVendas() async {
    try {
      final config = await DiscoveryService().getConfig();
      // Se não encontrar no Gist, usa o fallback padrão
      String urlString =
          config?.urlRenovacaoLicenca ?? "https://pramilhas.suportvip.com/";
      final Uri uri = Uri.parse(urlString);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Erro ao abrir link de vendas: $e");
    }
  }

  Future<void> _ativarSistema() async {
    final String email = _emailController.text.trim();
    final String token = _tokenController.text.trim();

    if (email.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preencha todos os campos!"),
          backgroundColor: AppTheme.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final Map<String, dynamic> resultado = await _auth.autenticarNoServidor(
      email,
      token,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (resultado['sucesso'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ ${resultado['mensagem']}"),
          backgroundColor: AppTheme.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) => const MainNavigator(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Erro: ${resultado['mensagem']}"),
          backgroundColor: AppTheme.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: AutofillGroup(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(),
                const SizedBox(height: 40),
                _buildSecurityIndicator(),
                const SizedBox(height: 30),
                _buildEmailField(),
                const SizedBox(height: 16),
                _buildTokenField(),
                const SizedBox(height: 40),
                _buildSubmitButton(),
                const SizedBox(height: 24),
                _buildNoAccessButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoAccessButton() {
    return TextButton(
      onPressed: _abrirSiteVendas,
      style: TextButton.styleFrom(foregroundColor: AppTheme.muted),
      child: RichText(
        textAlign: TextAlign.center,
        text: const TextSpan(
          style: TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontFamily: 'Inter',
            letterSpacing: 0.5,
          ),
          children: [
            TextSpan(text: "AINDA NÃO TEM ACESSO? "),
            TextSpan(
              text: "CLIQUE AQUI",
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Ícone reduzido ligeiramente para alinhar melhor com o texto
        const Icon(Icons.radar, color: AppTheme.accent, size: 36),
        const SizedBox(width: 12),
        Text(
          "PRAMILHAS",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            color: AppTheme.black,
            // 🚀 Na letra preta, a sombra tem que ser BEM mais leve e espalhada
            shadows: [
              Shadow(
                color: AppTheme.accent.withValues(
                  alpha: 0.15,
                ), // 👈 Troquei aqui
                blurRadius: 15,
              ),
            ],
          ),
        ),
        Text(
          "VIP",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w900, // 🚀 BOLD TOTAL (Igual à Splash)
            letterSpacing: 4,
            color: AppTheme.accent,
            // 🚀 Na letra roxa, a sombra pode ser um pouco mais forte para o "Glow"
            shadows: [
              Shadow(color: AppTheme.accent.withOpacity(0.4), blurRadius: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityIndicator() {
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

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      autofillHints: const [AutofillHints.email, AutofillHints.username],
      style: const TextStyle(color: AppTheme.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: "E-mail de Destino",
        labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
        filled: true,
        fillColor: AppTheme.card,
        prefixIcon: const Icon(Icons.email, color: AppTheme.muted, size: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
      ),
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildTokenField() {
    return TextField(
      controller: _tokenController,
      obscureText: _obscurePassword, // 🚀 Usa o estado dinâmico
      autofillHints: const [AutofillHints.password],
      style: const TextStyle(
        color: AppTheme.text,
        letterSpacing: 2,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: "SENHA",
        labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
        filled: true,
        fillColor: AppTheme.card,
        prefixIcon: const Icon(Icons.key, color: AppTheme.muted, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
            color: AppTheme.accent,
            size: 20,
          ),
          tooltip: _obscurePassword ? "Mostrar Senha" : "Ocultar Senha",
          onPressed: () {
            // 🚀 Inverte o estado e atualiza a UI
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        TextInput.finishAutofillContext();
        _ativarSistema();
      },
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 10,
          shadowColor: AppTheme.accent.withValues(alpha: 0.3),
        ),
        onPressed: _isLoading
            ? null
            : () {
                TextInput.finishAutofillContext();
                _ativarSistema();
              },
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                "INICIAR SESSÃO",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
      ),
    );
  }
}
