package com.hesapmakinesi.hesap_makinesi

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

object NudgeVibration {
    // --....  ~0.5s; tıklar kısa, aralıklar açık ki 6 tane ayrılsın
    private val timings = longArrayOf(
        0, 52, 64, 52, 64, 22, 64, 22, 64, 22, 64, 22,
    )
    private val amplitudes = intArrayOf(
        0, 140, 0, 140, 0, 140, 0, 140, 0, 140, 0, 140,
    )

    fun play(context: Context) {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wake = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hm:nudge")
        wake.setReferenceCounted(false)
        wake.acquire(800)

        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(timings, amplitudes, -1),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(timings, -1)
        }
    }

    fun isBatteryUnrestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestBatteryUnrestricted(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pkg = Uri.parse("package:${context.packageName}")
        try {
            context.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = pkg
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        } catch (_: Exception) {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = pkg
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        }
    }
}
