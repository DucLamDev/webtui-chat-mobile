package com.hiennv.flutter_callkit_incoming

import android.content.Context

/**
 * Supplies notifications to Android entry points that may run before Flutter
 * attaches. The fallback retains only the application context and is shared by
 * the service and broadcast receiver for the lifetime of this process.
 */
internal object CallkitNotificationManagerProvider {
    @Volatile
    private var processManager: CallkitNotificationManager? = null

    fun get(context: Context): CallkitNotificationManager {
        // Once a cold-process fallback has started a ringtone it must remain
        // the authority for this process. Switching to the plugin-owned sound
        // player after Flutter attaches can leave the fallback ringtone alive.
        processManager?.let { return it }

        FlutterCallkitIncomingPlugin.getInstance()
            ?.getCallkitNotificationManager()
            ?.let { return it }

        return synchronized(this) {
            processManager ?: createProcessManager(context).also {
                processManager = it
            }
        }
    }

    private fun createProcessManager(context: Context): CallkitNotificationManager {
        val applicationContext = context.applicationContext
        return CallkitNotificationManager(
            applicationContext,
            CallkitSoundPlayerManager(applicationContext)
        )
    }
}
