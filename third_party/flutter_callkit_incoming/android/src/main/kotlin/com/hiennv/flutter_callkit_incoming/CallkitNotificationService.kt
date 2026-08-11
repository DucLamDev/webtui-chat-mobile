package com.hiennv.flutter_callkit_incoming

import android.annotation.SuppressLint
import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import androidx.core.content.ContextCompat

class CallkitNotificationService : Service() {

    companion object {

        private val ActionForeground = listOf(
            CallkitConstants.ACTION_CALL_START,
            CallkitConstants.ACTION_CALL_ACCEPT,
            CallkitConstants.ACTION_CALL_MEDIA_ACTIVE
        )


        fun startServiceWithAction(context: Context, action: String, data: Bundle?) {
            val intent = Intent(context, CallkitNotificationService::class.java).apply {
                this.action = action
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && intent.action in ActionForeground) {
                data?.let {
                    if(it.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, true)) {
                        ContextCompat.startForegroundService(context, intent)
                    }else {
                        context.startService(intent)
                    }
                }
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, CallkitNotificationService::class.java)
            context.stopService(intent)
        }

        /**
         * Android 14+ permits microphone/camera FGS types only while their
         * while-in-use permissions are granted and the app is visible. Keep
         * this check in native code so a Dart-side ordering bug cannot promote
         * the service before the platform permission dialog has completed.
         */
        fun canPromoteMedia(context: Context, isVideo: Boolean): Boolean {
            val processInfo = ActivityManager.RunningAppProcessInfo()
            ActivityManager.getMyMemoryState(processInfo)
            val visible =
                processInfo.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                    processInfo.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
            if (!visible) return false

            val microphoneGranted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            val cameraGranted = !isVideo || ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
            return microphoneGranted && cameraGranted
        }

    }

    /**
     * A notification action can recreate this service before any FlutterEngine
     * attaches. The FGS must still synchronously build its notification and
     * call startForeground within Android's deadline. Reuse the plugin manager
     * when available (so its ringtone is stopped), otherwise use a manager
     * owned by the service process.
     */
    private fun getCallkitNotificationManager(): CallkitNotificationManager {
        return CallkitNotificationManagerProvider.get(applicationContext)
    }


    override fun onCreate() {
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == CallkitConstants.ACTION_CALL_START) {
            intent.getBundleExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
                ?.let {
                    if(it.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, true)) {
                        getCallkitNotificationManager().createNotificationChanel(it)
                        showOngoingCallNotification(
                            it,
                            it.getBoolean(CallkitConstants.EXTRA_CALLKIT_MEDIA_ACTIVE, false)
                        )
                    }else {
                        stopSelf()
                    }
                }
        }
        if (intent?.action == CallkitConstants.ACTION_CALL_ACCEPT) {
            intent.getBundleExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
                ?.let {
                    getCallkitNotificationManager().clearIncomingNotification(it, true)
                    if (it.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, true)) {
                        // Accept can happen from a lock-screen notification,
                        // before the Flutter activity has requested media
                        // permissions. The initial FGS must therefore remain
                        // phoneCall-only.
                        showOngoingCallNotification(it, false)
                    }else {
                        stopSelf()
                    }
                }
        }
        if (intent?.action == CallkitConstants.ACTION_CALL_MEDIA_ACTIVE) {
            intent.getBundleExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
                ?.let {
                    if (it.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, true)) {
                        getCallkitNotificationManager().createNotificationChanel(it)
                        showOngoingCallNotification(it, true)
                    } else {
                        stopSelf()
                    }
                }
        }
        return START_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun showOngoingCallNotification(bundle: Bundle, mediaActive: Boolean) {

        val callkitNotification =
            getCallkitNotificationManager().getOnGoingCallNotification(bundle, false)
        if (callkitNotification != null) {
            val typeCall = bundle.getInt(CallkitConstants.EXTRA_CALLKIT_TYPE, -1)
            startPhoneCallForeground(
                callkitNotification.id,
                callkitNotification.notification
            )
            if (mediaActive) {
                promoteMediaForeground(
                    callkitNotification.id,
                    callkitNotification.notification,
                    typeCall > 0
                )
            }
        }
    }

    private fun startPhoneCallForeground(notificationId: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(notificationId, notification)
        }
    }

    private fun promoteMediaForeground(
        notificationId: Int,
        notification: Notification,
        isVideo: Boolean
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (!canPromoteMedia(this, isVideo)) return

        var mask = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        if (isVideo) {
            mask = mask or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        startForeground(notificationId, notification, mask)
    }


    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onBind(p0: Intent?): IBinder? {
        return null
    }


    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Don't kill the FGS. The app might be closed by user but the call is still ongoing
    }
}
