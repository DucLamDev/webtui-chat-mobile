package com.vpsttt.webtui_chat

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class WebTuiApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            MESSAGE_CHANNEL_ID,
            getString(R.string.notification_channel_messages),
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = getString(R.string.notification_channel_messages_description)
            enableVibration(true)
            setShowBadge(true)
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    companion object {
        const val MESSAGE_CHANNEL_ID = "webtui_messages"
    }
}
