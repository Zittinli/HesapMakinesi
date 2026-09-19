package com.hesapmakinesi.hesap_makinesi

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class NudgeMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["type"] == "nudge") {
            val sent = message.sentTime
            if (sent > 0 && System.currentTimeMillis() - sent > 8_000) {
                return
            }
            NudgeVibration.play(this)
            return
        }
        super.onMessageReceived(message)
    }
}
