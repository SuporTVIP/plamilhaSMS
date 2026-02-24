package com.suportvips.milhasalert.milhas_alert

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.suportvips.milhasalert/sms_control"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("AppConfig", Context.MODE_PRIVATE)
            
            when (call.method) {
                "startSmsService" -> {
                    prefs.edit().putBoolean("sms_capture_enabled", true).apply()
                    result.success(true)
                }
                "stopSmsService" -> {
                    prefs.edit().putBoolean("sms_capture_enabled", false).apply()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}