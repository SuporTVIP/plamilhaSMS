package com.suportvips.milhasalert.milhas_alert

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log

class SmsService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val sender = intent?.getStringExtra("sender") ?: return START_NOT_STICKY
        val body = intent.getStringExtra("body") ?: return START_NOT_STICKY

        // 🚀 O HACK DE OURO: LENDO O BANCO DE DADOS DO FLUTTER NATIVAMENTE!
        // O Flutter usa o nome "FlutterSharedPreferences" e sempre adiciona "flutter." antes do nome das suas variáveis.
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        val token = prefs.getString("flutter.USER_TOKEN", "") ?: ""
        val deviceId = prefs.getString("flutter.DEVICE_ID_V2", "") ?: ""
        val email = prefs.getString("flutter.USER_EMAIL", "") ?: ""

        if (token.isEmpty() || email.isEmpty()) {
            Log.e("SmsService", "Aplicativo não está logado no Flutter. SMS ignorado.")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // 🚀 Roda a conexão com o Google em uma Thread secundária
        Thread {
            // 👇 NOVO BLOCO: SALVA O LOG PARA O FLUTTER LER 👇
            try {
                val historyStr = prefs.getString("flutter.SMS_HISTORY", "[]") ?: "[]"
                val historyArray = org.json.JSONArray(historyStr)
                
                val newSms = org.json.JSONObject()
                newSms.put("remetente", sender)
                newSms.put("mensagem", body)
                val sdf = java.text.SimpleDateFormat("dd/MM HH:mm", java.util.Locale.getDefault())
                newSms.put("hora", sdf.format(java.util.Date()))
                
                historyArray.put(newSms)
                
                // Mantém apenas os últimos 15 para não pesar a memória
                val limitedArray = org.json.JSONArray()
                val start = if (historyArray.length() > 15) historyArray.length() - 15 else 0
                for (i in start until historyArray.length()) {
                    limitedArray.put(historyArray.get(i))
                }
                prefs.edit().putString("flutter.SMS_HISTORY", limitedArray.toString()).apply()
            } catch (e: Exception) {
                Log.e("SmsService", "Erro ao salvar log: ", e)
            }
            // 👆 FIM DO NOVO BLOCO 👆

            Log.i("SmsService", "Enviando SMS capturado para a nuvem...")
            val sucesso = NetworkLayer.sendSmsData(token, deviceId, body, sender, email)
            
            if (sucesso) Log.i("SmsService", "✅ SMS sincronizado!")
            stopSelf(startId) 
        }.start()

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}