import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🚀 Importante para acessar a área de transferência (Clipboard)
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'main.dart'; 

/// Tela de Login e Ativação do Aplicativo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controladores para capturar o texto dos inputs.
  // Analogia: Similar ao `document.getElementById('id').value` ou refs no React.
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final AuthService _auth = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _carregarMemoriaDosInputs();
  }

  /// Recupera o último e-mail e token utilizados para facilitar o re-login.
  void _carregarMemoriaDosInputs() async {
    final dadosViejos = await _auth.getLastLoginData();
    if (dadosViejos['email']!.isNotEmpty) {
      setState(() {
        _emailController.text = dadosViejos['email']!;
        _tokenController.text = dadosViejos['token']!;
      });
    }
  }

  /// 🚀 FUNÇÃO PARA COLAR TEXTO DA ÁREA DE TRANSFERÊNCIA
  ///
  /// Analogia: Facilita a vida do usuário permitindo colar a chave de licença
  /// direto do WhatsApp/E-mail, similar ao comando `navigator.clipboard.readText()` no JS.
  void _colarDoClipboard(TextEditingController controller) async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        controller.text = data.text!;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Texto colado com sucesso!"), 
            backgroundColor: AppTheme.green,
            duration: Duration(seconds: 1),
          )
        );
      }
    }
  }

  /// Tenta realizar a autenticação no servidor.
  void _ativarSistema() async {
    if (_emailController.text.trim().isEmpty || _tokenController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha todos os campos!"), backgroundColor: AppTheme.red)
      );
      return;
    }

    setState(() => _isLoading = true);

    final resultado = await _auth.autenticarNoServidor(
      _emailController.text.trim(), 
      _tokenController.text.trim()
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (resultado['sucesso'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ ${resultado['mensagem']}"), backgroundColor: AppTheme.green)
      );
      
      // Navega para a tela principal e remove a tela de login da pilha (não volta ao apertar 'back').
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigator()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Erro: ${resultado['mensagem']}"), backgroundColor: AppTheme.red)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        // SingleChildScrollView: Permite que o conteúdo role se for maior que a tela.
        // Analogia: Essencial em formulários para que o teclado, ao subir, não cubra os campos de texto (evita o erro de 'bottom overflow').
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🚀 LOGOTIPO ESTILO CYBERPUNK
              Row(
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
              ),
              const SizedBox(height: 40),

              // Indicador de Segurança
              Container(
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
                      style: TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Campo de E-mail
              // TextField: O campo de entrada de texto (Analogia: <input type="text"> no HTML).
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                // InputDecoration: Define a aparência do campo (Rótulo, ícone, bordas).
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
              ),
              const SizedBox(height: 16),

              // Campo de Chave (Token) com suporte a Colar
              TextField(
                controller: _tokenController,
                style: const TextStyle(color: Colors.white, letterSpacing: 2, fontSize: 14),
                decoration: InputDecoration(
                  labelText: "Chave de Licença",
                  labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  filled: true,
                  fillColor: AppTheme.card,
                  prefixIcon: const Icon(Icons.key, color: AppTheme.muted, size: 20),
                  // 🚀 BOTÃO DE COLAR: Atalho rápido para preenchimento.
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste, color: AppTheme.accent, size: 20),
                    tooltip: "Colar Licença",
                    onPressed: () => _colarDoClipboard(_tokenController),
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
              ),
              const SizedBox(height: 40),

              // Botão de Ativação
              SizedBox(
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                      ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
