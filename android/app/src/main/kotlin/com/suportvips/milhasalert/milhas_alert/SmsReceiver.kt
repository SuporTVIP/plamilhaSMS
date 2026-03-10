package com.suportvips.milhasalert.milhas_alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    // 🚀 A MÁGICA: MEMÓRIA ESTÁTICA PARA GUARDAR OS PEDAÇOS
    companion object {
        private val messageBuffer = mutableMapOf<String, String>()
        private val handlers = mutableMapOf<String, Handler>()
        private val runnables = mutableMapOf<String, Runnable>()
        private const val WAIT_TIME_MS = 5000L // Espera 5 segundos pelo próximo pedaço
    }

    private val BLACKLIST_SMS = Regex(
        "vivo|oi|tim|promoção|oferta|desconto|sorteio|compre agora|parabens voce ganhou|bet|ganhou|clique no link|cupom|bet365|tigrinho|liquidação",
        RegexOption.IGNORE_CASE
    )

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // Verifica se a captura está ativada no Flutter
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isSmsEnabled = prefs.getBoolean("flutter.IS_SMS_MONITORING", false) 

        if (!isSmsEnabled) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val sender = messages[0]?.originatingAddress ?: "Desconhecido"
        
        // Pega o pedaço atual que a operadora entregou
        val bodyPart = StringBuilder()
        for (sms in messages) {
            bodyPart.append(sms?.messageBody ?: "")
        }
        val textPart = bodyPart.toString()

        Log.i("SmsReceiver", "🧩 PEDAÇO RECEBIDO de $sender: $textPart")

        // 🚀 1. GUARDA O PEDAÇO NO COFRE
        val currentText = messageBuffer[sender] ?: ""
        messageBuffer[sender] = currentText + textPart

        // 🚀 2. CANCELA O CRONÔMETRO ANTERIOR (se houver)
        handlers[sender]?.removeCallbacks(runnables[sender]!!)

        // 🚀 3. INICIA UM NOVO CRONÔMETRO DE 5 SEGUNDOS
        val handler = Handler(Looper.getMainLooper())
        val runnable = Runnable {
            // Tempo esgotado! A operadora parou de mandar pedaços. Vamos enviar!
            val finalMessage = messageBuffer[sender] ?: ""
            
            // Limpa o cofre
            messageBuffer.remove(sender) 
            runnables.remove(sender)
            handlers.remove(sender)

            processarMensagemCompleta(context, sender, finalMessage)
        }

        handlers[sender] = handler
        runnables[sender] = runnable
        handler.postDelayed(runnable, WAIT_TIME_MS)
    }

    // 🚀 4. FUNÇÃO QUE ENVIA A MENSAGEM COLADA PARA O GOOGLE
    private fun processarMensagemCompleta(context: Context, sender: String, fullMessage: String) {
        Log.i("SmsReceiver", "===================================================")
        Log.i("SmsReceiver", "📩 SMS MONTADO (COMPLETO) | Remetente: $sender")
        Log.i("SmsReceiver", "📝 TEXTO: $fullMessage")

        if (BLACKLIST_SMS.containsMatchIn(fullMessage)) {
            Log.w("SmsReceiver", "🗑️ SMS BLOQUEADO PELA BLACKLIST. Ignorando.")
            return
        }

        Log.i("SmsReceiver", "✅ SMS APROVADO! Enviando para o SmsService...")

        val serviceIntent = Intent(context, SmsService::class.java).apply {
            putExtra("sender", sender)
            putExtra("body", fullMessage) // 🚀 MUDAMOS DE "message" PARA "body"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
        Log.i("SmsReceiver", "===================================================")
    }
}