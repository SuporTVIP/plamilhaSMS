package com.suportvips.milhasalert.milhas_alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import org.json.JSONArray

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private val messageBuffer = mutableMapOf<String, String>()
        private val handlers      = mutableMapOf<String, Handler>()
        private val runnables     = mutableMapOf<String, Runnable>()
        private const val WAIT_TIME_MS = 5000L

        // Blacklist padrão — usada somente se o Gist ainda não foi carregado
        // (ex: primeira abertura offline ou antes do Flutter gravar no prefs).
        // Após o app abrir, o DiscoveryService sobrescreve esta lista no SharedPreferences.
        private val BLACKLIST_FALLBACK = listOf(
            "vivo", "oi", "tim", "promoção", "oferta", "desconto",
            "sorteio", "compre agora", "parabens voce ganhou", "bet",
            "ganhou", "clique no link", "cupom", "bet365", "tigrinho",
            "liquidação"
        )
    }

    /**
     * Lê a blacklist do Gist gravada pelo Flutter (DiscoveryService).
     * A chave é "flutter.DISCOVERY_SMS_BLACKLIST" e o valor é um JSON array de strings.
     * Se não encontrar, usa BLACKLIST_FALLBACK.
     */
    private fun getBlacklist(context: Context): List<String> {
        return try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val json = prefs.getString("flutter.DISCOVERY_SMS_BLACKLIST", null)
            if (!json.isNullOrBlank()) {
                val arr = JSONArray(json)
                val list = (0 until arr.length()).map { arr.getString(it) }
                Log.d("SmsReceiver", "📋 Blacklist do Gist: ${list.size} termos")
                list
            } else {
                Log.w("SmsReceiver", "⚠️ Blacklist do Gist não disponível. Usando fallback.")
                BLACKLIST_FALLBACK
            }
        } catch (e: Exception) {
            Log.e("SmsReceiver", "❌ Erro ao ler blacklist: ${e.message}")
            BLACKLIST_FALLBACK
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        if (!prefs.getBoolean("flutter.IS_SMS_MONITORING", false)) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val sender = messages[0]?.originatingAddress ?: "Desconhecido"

        val bodyPart = StringBuilder()
        for (sms in messages) bodyPart.append(sms?.messageBody ?: "")
        val textPart = bodyPart.toString()

        Log.i("SmsReceiver", "🧩 PEDAÇO de $sender: $textPart")

        messageBuffer[sender] = (messageBuffer[sender] ?: "") + textPart
        handlers[sender]?.removeCallbacks(runnables[sender]!!)

        val handler  = Handler(Looper.getMainLooper())
        val runnable = Runnable {
            val finalMessage = messageBuffer.remove(sender) ?: ""
            runnables.remove(sender)
            handlers.remove(sender)
            processarMensagemCompleta(context, sender, finalMessage)
        }

        handlers[sender]  = handler
        runnables[sender] = runnable
        handler.postDelayed(runnable, WAIT_TIME_MS)
    }

    private fun processarMensagemCompleta(
        context: Context, sender: String, fullMessage: String
    ) {
        Log.i("SmsReceiver", "===================================================")
        Log.i("SmsReceiver", "📩 SMS MONTADO | Remetente: $sender")
        Log.i("SmsReceiver", "📝 TEXTO: $fullMessage")

        // Verifica contra a blacklist vinda do Gist (ou fallback)
        val blacklist = getBlacklist(context)
        val msgLower  = fullMessage.lowercase()
        val bloqueado = blacklist.any { msgLower.contains(it.lowercase()) }

        if (bloqueado) {
            Log.w("SmsReceiver", "🗑️ BLOQUEADO pela blacklist do Gist.")
            return
        }

        Log.i("SmsReceiver", "✅ APROVADO! Enviando para o SmsService...")

        val serviceIntent = Intent(context, SmsService::class.java).apply {
            putExtra("sender", sender)
            putExtra("body", fullMessage)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
        Log.i("SmsReceiver", "===================================================")
    }
}