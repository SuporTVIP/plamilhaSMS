package com.suportvips.milhasalert.milhas_alert

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.io.BufferedReader
import java.io.InputStreamReader

object NetworkLayer {

    // URL de fallback — usada apenas se o Flutter ainda não gravou a URL do Gist
    // no SharedPreferences (ex: primeira abertura offline).
    private const val FALLBACK_URL =
        "https://script.google.com/macros/s/AKfycbw6U1f8ccnH3V5_Vw386g6aSGRF7sTJdFGDU24wBl66aoHNcd1oDwIfcYXcS1_H-2qI/exec"

    /**
     * Lê a URL do GAS do SharedPreferences gravado pelo Flutter (DiscoveryService).
     * O Flutter grava a chave "flutter.DISCOVERY_GAS_URL" ao carregar o Gist.
     * Se ainda não estiver disponível, usa o FALLBACK_URL.
     */
    fun getGasUrl(context: Context): String {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val urlFromGist = prefs.getString("flutter.DISCOVERY_GAS_URL", null)
        return if (!urlFromGist.isNullOrBlank()) {
            Log.d("NetworkLayer", "🔗 URL do Gist: $urlFromGist")
            urlFromGist
        } else {
            Log.w("NetworkLayer", "⚠️ URL do Gist não disponível. Usando fallback.")
            FALLBACK_URL
        }
    }

    fun sendSmsData(
        context: Context,
        licenseKey: String,
        deviceId: String,
        smsContent: String,
        senderNumber: String,
        targetEmail: String
    ): Boolean {
        return try {
            val scriptUrl = getGasUrl(context)
            val url = URL(scriptUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
            connection.doOutput = true

            val jsonParam = JSONObject().apply {
                put("action", "RECEIVE_SMS")
                put("license_key", licenseKey)
                put("device_id", deviceId)
                put("sms_content", smsContent)
                put("sender_number", senderNumber)
                put("target_email", targetEmail)
            }

            Log.d("NetworkLayer",
                "📦 PACOTE -> Email: $targetEmail | Token: $licenseKey | DeviceID: $deviceId")

            OutputStreamWriter(connection.outputStream).use {
                it.write(jsonParam.toString())
            }

            val responseCode = connection.responseCode
            val stream = if (responseCode in 200..299) connection.inputStream
                         else connection.errorStream
            val responseBody = stream?.let {
                BufferedReader(InputStreamReader(it)).use { r -> r.readText() }
            } ?: "Sem corpo de resposta"

            Log.d("NetworkLayer", "🌐 HTTP: $responseCode | Resposta: $responseBody")

            responseBody.contains("\"status\":\"success\"") ||
            responseBody.contains("\"status\": \"success\"")

        } catch (e: Exception) {
            Log.e("NetworkLayer", "❌ Erro fatal de rede", e)
            false
        }
    }
}