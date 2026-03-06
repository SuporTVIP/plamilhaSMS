package com.suportvips.milhasalert.milhas_alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    private val BLACKLIST_SMS = Regex(
        "vivo|oi|tim|promoção|oferta|desconto|sorteio|compre agora|parabens voce ganhou|bet|ganhou|clique no link|cupom|bet365|tigrinho|liquidação",
        RegexOption.IGNORE_CASE
    )

    private fun shouldFilterMessage(message: String): Boolean {
        return BLACKLIST_SMS.containsMatchIn(message)
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.i("SmsReceiver", "===================================================")
        Log.i("SmsReceiver", "🚨 [RAIO-X NATIVO] GATILHO DE SMS DISPARADO PELO ANDROID!")

        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            Log.e("SmsReceiver", "❌ Ação ignorada: Não é um evento de SMS.")
            return
        }

        val prefs = context.getSharedPreferences("AppConfig", Context.MODE_PRIVATE)
        val isSmsEnabled = prefs.getBoolean("sms_capture_enabled", false)

        Log.i("SmsReceiver", "⚙️ Botão de Captura de SMS (SharedPreferences): $isSmsEnabled")

        if (!isSmsEnabled) {
            Log.w("SmsReceiver", "⏸️ Captura desligada no aplicativo. SMS descartado.")
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (sms in messages) {
            val body = sms.messageBody
            val sender = sms.originatingAddress ?: "Desconhecido"

            Log.i("SmsReceiver", "📩 SMS LIDO | Remetente: $sender | Texto: $body")

            if (shouldFilterMessage(body)) {
                Log.w("SmsReceiver", "🗑️ SMS BLOQUEADO PELA BLACKLIST BETA. Ignorando.")
                continue
            }

            Log.i("SmsReceiver", "✅ SMS APROVADO! Enviando para o SmsService processar em background...")

            val serviceIntent = Intent(context, SmsService::class.java).apply {
                putExtra("sender", sender)
                putExtra("body", body)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
        Log.i("SmsReceiver", "===================================================")
    }
}