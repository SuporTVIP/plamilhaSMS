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
        // Cria o canal de notificação obrigatório no Android 8+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Sincronização Invisível",
                NotificationManager.IMPORTANCE_MIN // IMPORTANCE_MIN = Sem som, sem vibrar
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        AppLog.i("SmsService", "🚀 [RAIO-X NATIVO] SmsService Iniciado!")

        // 🚀 A BLINDAGEM CONTRA O CRASH DO ANDROID 8+
        // Mostra uma notificação de sistema provando que está fazendo um envio seguro
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notification = android.app.Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Sincronizando SMS")
                .setContentText("Transmitindo alerta para a nuvem...")
                .setSmallIcon(android.R.drawable.stat_sys_upload) // Ícone de upload do próprio Android
                .build()
            
            // Avisa o Android: "Calma, não me mate, eu estou na barra de notificações!"
            startForeground(1001, notification)
        }

        val sender = intent?.getStringExtra("sender") ?: return START_NOT_STICKY
        val body = intent.getStringExtra("body") ?: return START_NOT_STICKY

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = prefs.getString("flutter.USER_TOKEN", "") ?: ""
        val deviceId = prefs.getString("flutter.DEVICE_ID_V2", "") ?: ""
        val email = prefs.getString("flutter.USER_EMAIL", "") ?: ""

        if (token.isEmpty() || email.isEmpty()) {
            stopForeground(true) // Remove a notificação
            stopSelf(startId)
            return START_NOT_STICKY
        }

        Thread {
            try {
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
            } catch (e: Exception) {
                AppLog.e("SmsService", "❌ Erro ao salvar AppLog no celular: ", e)
            }

            AppLog.i("SmsService", "🌐 Acionando o NetworkLayer para enviar ao Google...")
            val sucesso = NetworkLayer.sendSmsData(token, deviceId, body, sender, email)
            
            if (sucesso) {
                AppLog.i("SmsService", "✅ SMS sincronizado com sucesso na nuvem do Google!")
            } else {
                AppLog.e("SmsService", "❌ Falha ao comunicar com o Google.")
            }
            
            // 🚀 FIM DO PROCESSO: Oculta a notificação visual e finaliza o serviço com segurança
            stopForeground(true) 
            stopSelf(startId) 
        }.start()

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}