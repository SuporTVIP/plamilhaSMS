package com.suportvips.milhasalert.milhas_alert

import android.util.Log

object AppLog {
    // 🚀 A CHAVE MESTRA DO ANDROID
    private const val IS_DEBUG = false // Mude para 'false' para silenciar o app todo no Logcat

    fun i(tag: String, msg: String) {
        if (IS_DEBUG) Log.i(tag, msg)
    }

    fun e(tag: String, msg: String, tr: Throwable? = null) {
        if (IS_DEBUG) Log.e(tag, msg, tr)
    }
    
    fun d(tag: String, msg: String) {
        if (IS_DEBUG) Log.d(tag, msg)
    }
}