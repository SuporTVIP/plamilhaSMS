package com.suportvips.milhasalert.milhas_alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    // 🚀 BLACKLIST BETA HARDCODED
    private val BLACKLIST_SMS = Regex(
        "vivo|oi|tim|promoção|oferta|desconto|sorteio|compre agora|parabens voce ganhou|bet|ganhou|clique no link|cupom|bet365|tigrinho|liquidação",
        RegexOption.IGNORE_CASE
    )

    private fun shouldFilterMessage(message: String): Boolean {
        return BLACKLIST_SMS.containsMatchIn(message)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        // Verifica se o botão de captura foi LIGADO no aplicativo Flutter
        val prefs = context.getSharedPreferences("AppConfig", Context.MODE_PRIVATE)
        val isSmsEnabled = prefs.getBoolean("sms_capture_enabled", false)

        if (!isSmsEnabled) {
            Log.d("SmsReceiver", "Captura desligada pelo usuário. SMS ignorado.")
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (sms in messages) {
            val body = sms.messageBody
            val sender = sms.originatingAddress ?: "Desconhecido"

            // 🚀 VERIFICA A BLACKLIST
            if (shouldFilterMessage(body)) {
                Log.d("SMS_FILTER", "Mensagem bloqueada pela Blacklist Beta.")
                continue
            }

            Log.i("SmsReceiver", "SMS recebido de $sender. Delegando para o SmsService.")

            // Cria o Intent para acionar o Trabalhador que vai subir pra nuvem
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
    }
}