package com.suportvips.milhasalert.milhas_alert

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

class SmsService : Service() {

    private val CHANNEL_ID = "SmsSyncChannel"

    override fun onCreate() {
        super.onCreate()
        Log.i("SmsService", "⚙️ onCreate: Inicializando serviço de SMS...")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Sincronização Invisível",
                NotificationManager.IMPORTANCE_MIN // Sem som, sem vibrar
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i("SmsService", "🚀 [RAIO-X NATIVO] SmsService onStartCommand acionado!")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notification = android.app.Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Sincronizando SMS VIP")
                .setContentText("Transmitindo para a nuvem...")
                .setSmallIcon(android.R.drawable.stat_sys_upload) 
                .build()
            
            startForeground(1001, notification)
        }

        // Se a intent for nula (o Android reiniciou o serviço sozinho), a gente morre.
        if (intent == null) {
            Log.e("SmsService", "❌ Intent Nula! Serviço abortado.")
            stopForeground(true)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val sender = intent.getStringExtra("sender")
        val body = intent.getStringExtra("body")

        if (sender == null || body == null) {
             Log.e("SmsService", "❌ Faltou remetente ou body! Sender: $sender | Body: $body")
             stopForeground(true)
             stopSelf(startId)
             return START_NOT_STICKY
        }

        Log.i("SmsService", "📦 Pacote recebido com sucesso: $sender -> $body")

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = prefs.getString("flutter.USER_TOKEN", "") ?: ""
        val deviceId = prefs.getString("flutter.DEVICE_ID_V2", "") ?: ""
        val email = prefs.getString("flutter.USER_EMAIL", "") ?: ""

        if (token.isEmpty() || email.isEmpty()) {
            Log.e("SmsService", "❌ Usuário não está logado (Falta Token/Email). Abortando...")
            stopForeground(true) 
            stopSelf(startId)
            return START_NOT_STICKY
        }

        Thread {
            try {
                // Salva no histórico local (para aparecer na tela do App)
                val historyStr = prefs.getString("flutter.SMS_HISTORY", "[]") ?: "[]"
                val historyArray = org.json.JSONArray(historyStr)
                
                val newSms = org.json.JSONObject()
                newSms.put("remetente", sender)
                newSms.put("mensagem", body)
                
                val sdf = java.text.SimpleDateFormat("dd/MM HH:mm", java.util.Locale.getDefault())
                newSms.put("hora", sdf.format(java.util.Date()))
                
                historyArray.put(newSms)
                
                val limitedArray = org.json.JSONArray()
                val start = if (historyArray.length() > 15) historyArray.length() - 15 else 0
                for (i in start until historyArray.length()) {
                    limitedArray.put(historyArray.get(i))
                }
                prefs.edit().putString("flutter.SMS_HISTORY", limitedArray.toString()).apply()
                Log.i("SmsService", "💾 SMS salvo no histórico local com sucesso.")
            } catch (e: Exception) {
                Log.e("SmsService", "❌ Erro ao salvar histórico no celular: ", e)
            }

            Log.i("SmsService", "🌐 Acionando o NetworkLayer para enviar ao Google...")
            
            // Tenta enviar. 
            // NOTA: Se o seu AppLog e o NetworkLayer existirem e estiverem corretos, isso vai brilhar!
            try {
               val sucesso = NetworkLayer.sendSmsData(token, deviceId, body, sender, email)
               if (sucesso) {
                   Log.i("SmsService", "✅ SMS sincronizado com sucesso na nuvem do Google!")
               } else {
                   Log.e("SmsService", "❌ Falha ao comunicar com o Google (Retornou false).")
               }
            } catch (e: Exception) {
               Log.e("SmsService", "❌ CRASH FATAL no NetworkLayer: ", e)
            }
            
            Log.i("SmsService", "🏁 Encerrando o SmsService com sucesso.")
            stopForeground(true) 
            stopSelf(startId) 
        }.start()

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}