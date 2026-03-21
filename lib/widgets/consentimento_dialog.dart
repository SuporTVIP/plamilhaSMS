import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Diálogo de consentimento para o processamento de SMS.
///
/// Apresenta os termos de uso e política de privacidade relacionados à captura
/// de mensagens SMS para fins operacionais.
class ConsentimentoSmsDialog extends StatefulWidget {
  /// Callback executado quando o usuário aceita os termos.
  final VoidCallback onAccepted;

  /// Construtor padrão para [ConsentimentoSmsDialog].
  const ConsentimentoSmsDialog({super.key, required this.onAccepted});

  /// Exibe o diálogo se o usuário ainda não tiver aceitado os termos.
  static Future<void> showIfNeeded(
    BuildContext context,
    VoidCallback onAccepted,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool hasConsented = prefs.getBool('TERMS_ACCEPTED_SMS') ?? false;

    if (!hasConsented) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false, // O usuário não pode fechar clicando fora
          builder: (BuildContext context) =>
              ConsentimentoSmsDialog(onAccepted: onAccepted),
        );
      }
    } else {
      onAccepted(); // Se já aceitou antes, segue o fluxo normal
    }
  }

  @override
  State<ConsentimentoSmsDialog> createState() => _ConsentimentoSmsDialogState();
}

class _ConsentimentoSmsDialogState extends State<ConsentimentoSmsDialog> {
  bool _checkPolitica = false;
  bool _checkFinalidade = false;

  Future<void> _aceitarTermos() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'TERMS_ACCEPTED_SMS',
      true,
    ); // Salva a assinatura digital do usuário
    if (mounted) {
      Navigator.of(context).pop();
      widget.onAccepted();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Só habilita o botão "Continuar" se as duas caixas estiverem marcadas
    final bool canContinue = _checkPolitica && _checkFinalidade;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.blue, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Permissão para Processamento de SMS",
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "O PramilhaSVIP pode processar mensagens SMS recebidas neste dispositivo apenas para identificar mensagens transacionais operacionais compatíveis com os filtros (ex: comunicações de bancos e companhias aéreas).",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              "Quando este recurso estiver ativado, as mensagens compatíveis poderão ser enviadas com segurança para a sua planilha privada de controle.",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              "O aplicativo:\n"
              "• Não vende seus dados;\n"
              "• Não usa SMS para publicidade;\n"
              "• Não acessa mensagens fora da finalidade descrita;\n"
              "• Permite desativação a qualquer momento.",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const Divider(height: 30),

            // Checkbox 1: Política de Privacidade
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: GestureDetector(
                onTap: () async {
                  // 🚀 TROQUE PELA SUA URL REAL DA HOSTINGER
                  final Uri url = Uri.parse(
                    'https://privacidade.suportvip.com/',
                  );

                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Erro ao abrir a Política de Privacidade.",
                          ),
                        ),
                      );
                    }
                  }
                },
                child: const Text(
                  "Li e concordo com a Política de Privacidade (Clique para ler).",
                  style: TextStyle(
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    color: Colors.blue,
                  ),
                ),
              ),
              value: _checkPolitica,
              onChanged: (bool? val) =>
                  setState(() => _checkPolitica = val ?? false),
            ),

            // Checkbox 2: Finalidade e Uso
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                "Autorizo o processamento de mensagens SMS compatíveis com os filtros para centralização operacional.",
                style: TextStyle(fontSize: 13),
              ),
              value: _checkFinalidade,
              onChanged: (bool? val) =>
                  setState(() => _checkFinalidade = val ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(), // Cancela e fecha a janela
          child: const Text("Agora não", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: canContinue ? _aceitarTermos : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: canContinue ? Colors.blue : Colors.grey.shade300,
          ),
          child: const Text("Continuar"),
        ),
      ],
    );
  }
}
