package com.suportvips.milhasalert.milhas_alert

import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object NetworkLayer {
    // 🚀 A SUA URL DO GOOGLE APPS SCRIPT
    private const val SCRIPT_URL = "https://script.google.com/macros/s/AKfycbw6U1f8ccnH3V5_Vw386g6aSGRF7sTJdFGDU24wBl66aoHNcd1oDwIfcYXcS1_H-2qI/exec"

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

            // Monta o JSON nativamente, igual fazíamos no Postman
            val jsonParam = JSONObject()
            jsonParam.put("action", "RECEIVE_SMS") // Compatibilidade com o novo router no Apps Script
            jsonParam.put("license_key", licenseKey)
            jsonParam.put("device_id", deviceId)
            jsonParam.put("sms_content", smsContent)
            jsonParam.put("sender_number", senderNumber)
            jsonParam.put("target_email", targetEmail)

            // Escreve e envia os dados
            val out = OutputStreamWriter(connection.outputStream)
            out.write(jsonParam.toString())
            out.close()

            val responseCode = connection.responseCode
            Log.d("NetworkLayer", "Código de Resposta do Google: $responseCode")
            
            // O Google Apps Script geralmente retorna 200, 302 ou 303 quando o POST dá certo
            responseCode == HttpURLConnection.HTTP_OK || responseCode == HttpURLConnection.HTTP_MOVED_TEMP || responseCode == 303
        } catch (e: Exception) {
            Log.e("NetworkLayer", "Erro fatal ao enviar SMS pela rede", e)
            false
        }
    }
}