package com.suportvips.milhasalert.milhas_alert

import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.io.BufferedReader
import java.io.InputStreamReader

object NetworkLayer {
    // 🚨 ATENÇÃO: Verifique se esta URL é exatamente a URL ativa do seu GAS atual!
    private const val SCRIPT_URL = "https://script.google.com/macros/s/AKfycbyRZTj0zpin7ACze3FhyL9GbNvIeloNPzPlr-a7U0TlHFDaviIzs3y1QLwJzaOyzuti/exec"

    fun sendSmsData(
        licenseKey: String,
        deviceId: String,
        smsContent: String,
        senderNumber: String,
        targetEmail: String
    ): Boolean {
        return try {
            val url = URL(SCRIPT_URL)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
            connection.doOutput = true

            val jsonParam = JSONObject()
            jsonParam.put("action", "RECEIVE_SMS") 
            jsonParam.put("license_key", licenseKey)
            jsonParam.put("device_id", deviceId)
            jsonParam.put("sms_content", smsContent)
            jsonParam.put("sender_number", senderNumber)
            jsonParam.put("target_email", targetEmail)

            Log.d("NetworkLayer", "📦 PACOTE ENVIADO -> Email: $targetEmail | Token: $licenseKey | DeviceID: $deviceId")

            val out = OutputStreamWriter(connection.outputStream)
            out.write(jsonParam.toString())
            out.close()

            val responseCode = connection.responseCode
            
            // 🚀 A MÁGICA: Lê o texto exato que o Google Apps Script devolveu!
            val stream = if (responseCode in 200..299) connection.inputStream else connection.errorStream
            val responseBody = if (stream != null) {
                BufferedReader(InputStreamReader(stream)).use { it.readText() }
            } else "Sem corpo de resposta"

            Log.d("NetworkLayer", "🌐 Código HTTP: $responseCode")
            Log.d("NetworkLayer", "📝 Resposta do GAS: $responseBody")
            
            // Só considera sucesso se o JSON de resposta contiver "success"
            responseBody.contains("\"status\":\"success\"") || responseBody.contains("\"status\": \"success\"")
            
        } catch (e: Exception) {
            Log.e("NetworkLayer", "❌ Erro fatal de rede", e)
            false
        }
    }
}