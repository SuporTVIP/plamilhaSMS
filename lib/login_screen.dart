import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'main.dart'; // Para navegar para o MainNavigator após login

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final AuthService _auth = AuthService();
  bool _isLoading = false;

  void _ativarSistema() async {
    if (_emailController.text.isEmpty || _tokenController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha todos os campos!"), backgroundColor: Colors.redAccent)
      );
      return;
    }

    setState(() => _isLoading = true);

    // Salva localmente
    await _auth.salvarLoginLocal(_emailController.text, _tokenController.text);

    // Navega para o Dashboard substituindo a tela atual
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigator()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cores extraídas do seu design
    const Color neonPurple = Color(0xFFB026FF);
    const Color darkBg = Color(0xFF050505);
    const Color inputBorder = Color(0xFF333333);

    return Scaffold(
      backgroundColor: darkBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // TÍTULO NEON
              Text(
                "MilhasAlert", // Mude para PlamilhaSMS se preferir
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: neonPurple,
                  shadows: [
                    Shadow(color: neonPurple.withOpacity(0.8), blurRadius: 20),
                    Shadow(color: neonPurple.withOpacity(0.4), blurRadius: 40),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // CAIXA DE STATUS (Simulando o design)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1F16), // Fundo verde super escuro
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1B3B26)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 12),
                    Text(
                      "aguardando ativação de licença",
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w500),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // INPUT: E-MAIL
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "e-mail de destino",
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: const Icon(Icons.email, color: neonPurple, size: 20),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: neonPurple),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // INPUT: CHAVE (TOKEN)
              TextField(
                controller: _tokenController,
                style: const TextStyle(color: Colors.white, letterSpacing: 2),
                decoration: InputDecoration(
                  labelText: "chave de licença",
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: const Icon(Icons.lock, color: neonPurple, size: 20),
                  suffixIcon: const Icon(Icons.build, color: Colors.grey, size: 20),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: neonPurple),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // BOTÃO ATIVAR
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: neonPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 10,
                    shadowColor: neonPurple.withOpacity(0.5),
                  ),
                  onPressed: _isLoading ? null : _ativarSistema,
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "ativar sistema", 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)
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