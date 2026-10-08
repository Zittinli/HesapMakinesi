package com.hesapmakinesi.hesap_makinesi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class NudgeMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val type = message.data["type"]
        if (type == "nudge") {
            val sent = message.sentTime
            if (sent > 0 && System.currentTimeMillis() - sent > 8_000) {
                return
            }
            NudgeVibration.play(this)
            maybeNotifyNudge(message.data["fromName"])
            return
        }
        if (type == "forceLock") {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .edit()
                .putBoolean("flutter.force_lock_pending", true)
                .apply()
            super.onMessageReceived(message)
            return
        }
        super.onMessageReceived(message)
    }

    private fun maybeNotifyNudge(rawName: String?) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val look = prefs.getString("flutter.notification_look", "cover")
        if (look == "off") return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    "hm_alert",
                    "Kayıtlar",
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }
        val name = rawName?.trim().orEmpty().ifEmpty { "Birisi" }
        val notification = NotificationCompat.Builder(this, "hm_alert")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(name)
            .setContentText("Sizi dürttü.")
            .setAutoCancel(true)
            .build()
        manager.notify(name.hashCode(), notification)
    }
}
