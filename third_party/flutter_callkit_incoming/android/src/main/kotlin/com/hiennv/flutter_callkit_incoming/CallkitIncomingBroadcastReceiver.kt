package com.hiennv.flutter_callkit_incoming

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.ContextCompat

class CallkitIncomingBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallkitIncomingReceiver"
        const val EXTRA_ACTION_FROM_TELECOM =
            "com.hiennv.flutter_callkit_incoming.ACTION_FROM_TELECOM"
        var silenceEvents = false

        fun getIntent(context: Context, action: String, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                this.action = "${context.packageName}.${action}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentIncoming(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_INCOMING}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentStart(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_START}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentAccept(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_ACCEPT}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentDecline(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_DECLINE}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentEnded(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_ENDED}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentTimeout(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_TIMEOUT}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentCallback(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_CALLBACK}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentHeldByCell(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_HELD}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentUnHeldByCell(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_UNHELD}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }

        fun getIntentConnected(context: Context, data: Bundle?) =
            Intent().apply {
                setClassName(context.packageName, "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver")
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_CONNECTED}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
                `package` = context.packageName
            }
    }

    private fun getCallkitNotificationManager(context: Context): CallkitNotificationManager {
        return CallkitNotificationManagerProvider.get(context.applicationContext)
    }

    @SuppressLint("MissingPermission")
    private fun registerTelecomIncomingCall(context: Context, data: Bundle) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val parsed = try {
            Data.fromBundle(data)
        } catch (e: Exception) {
            null
        } ?: return
        if (parsed.id.isEmpty()) return
        if (CallkitConnection.find(parsed.id) != null) {
            Log.d(TAG, "Telecom call already registered id=${parsed.id} — skip")
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.MANAGE_OWN_CALLS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "MANAGE_OWN_CALLS not granted — Telecom incoming skipped")
            return
        }
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
        val manager = InAppCallManager(context.applicationContext)
        val handle = manager.getPhoneAccountHandle()
        val extras = Bundle().apply {
            putBundle(CallkitConnection.EXTRA_CALL_BUNDLE, data)
            putInt(
                TelecomManager.EXTRA_INCOMING_VIDEO_STATE,
                android.telecom.VideoProfile.STATE_AUDIO_ONLY,
            )
        }
        try {
            telecom.addNewIncomingCall(handle, extras)
            Log.d(TAG, "Telecom addNewIncomingCall id=${parsed.id}")
        } catch (e: SecurityException) {
            Log.w(TAG, "Telecom addNewIncomingCall rejected: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "Telecom addNewIncomingCall error: ${e.message}")
        }
    }

    private fun driveTelecomConnection(context: Context, data: Bundle, action: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val parsed = try {
            Data.fromBundle(data)
        } catch (e: Exception) {
            null
        } ?: return
        val conn = CallkitConnection.find(parsed.id) ?: return
        when (action) {
            CallkitConstants.ACTION_CALL_ACCEPT -> conn.markAccepted()
            CallkitConstants.ACTION_CALL_DECLINE -> conn.markDeclined(context)
            CallkitConstants.ACTION_CALL_ENDED -> conn.markEnded()
            CallkitConstants.ACTION_CALL_TIMEOUT -> conn.markMissed()
        }
    }

    private fun foregroundAcceptedTelecomCall(context: Context, data: Bundle) {
        val launchIntent = AppUtils.getAppIntent(
            context,
            CallkitConstants.ACTION_CALL_ACCEPT,
            data,
        ) ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
        )
        try {
            context.startActivity(launchIntent)
        } catch (error: Exception) {
            // Some OEM background-activity policies can reject this handoff.
            // Keep delivering/persisting the ACCEPT event so the visible app
            // can recover it on its next foreground instead of aborting the
            // receiver branch before EventChannel/durable replay.
            Log.w(TAG, "Unable to foreground accepted Telecom call: ${error.message}")
        }
    }

    @SuppressLint("MissingPermission")
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val data = intent.extras?.getBundle(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA) ?: return
        val event = action.removePrefix("${context.packageName}.")
        val fromTelecom = intent.getBooleanExtra(EXTRA_ACTION_FROM_TELECOM, false)

        // Persist before notification cleanup, FGS startup, EventChannel, or
        // any other operation that can fail. The authenticated Dart layer acks
        // only after its backend mutation succeeds.
        val pendingActionId = CallkitPendingActionStore.record(context, event, data)
        if (pendingActionId != null && event in setOf(
                CallkitConstants.ACTION_CALL_DECLINE,
                CallkitConstants.ACTION_CALL_ENDED,
                CallkitConstants.ACTION_CALL_TIMEOUT,
            )
        ) {
            CallkitReceiverExecutionLease.hold(pendingActionId, goAsync())
        }
        CallkitPendingActionWorker.enqueue(
            context,
            event,
            data,
            pendingActionId,
        )

        Log.d(TAG, action)

        when (action) {
            "${context.packageName}.${CallkitConstants.ACTION_CALL_INCOMING}" -> {
                try {
                    registerTelecomIncomingCall(context, data)
                    val incomingData = Data.fromBundle(data)
                    if (incomingData.isFullScreen) {
                        val intent = CallkitIncomingActivity.getIntent(context, data)
                        context.startActivity(intent)
                    } else {
                        getCallkitNotificationManager(context).showIncomingNotification(data)
                        sendEventFlutter(context, CallkitConstants.ACTION_CALL_INCOMING, data)
                        addCall(context, incomingData)
                    }
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_START}" -> {
                try {
                    // start service and show ongoing call when call is accepted
                    CallkitNotificationService.startServiceWithAction(
                        context,
                        CallkitConstants.ACTION_CALL_START,
                        data
                    )
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_START, data)
                    addCall(context, Data.fromBundle(data), true)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_ACCEPT}" -> {
                try {
                    if (!fromTelecom) {
                        driveTelecomConnection(context, data, CallkitConstants.ACTION_CALL_ACCEPT)
                    }
                    FlutterCallkitIncomingPlugin.notifyEventCallbacks(CallkitEventCallback.CallEvent.ACCEPT, data)
                    // start service and show ongoing call when call is accepted
                    CallkitNotificationService.startServiceWithAction(
                        context,
                        CallkitConstants.ACTION_CALL_ACCEPT,
                        data
                    )
                    if (fromTelecom) {
                        // Telecom/Bluetooth/watch accept has no
                        // TransparentActivity. Foreground the visible WebRTC
                        // flow; the headless handler deliberately never accepts
                        // or acknowledges this action.
                        foregroundAcceptedTelecomCall(context, data)
                    }
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_ACCEPT, data)
                    addCall(context, Data.fromBundle(data), true)
                    FlutterCallkitIncomingPlugin.acceptCallHandleCallback(data)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_DECLINE}" -> {
                try {
                    if (!fromTelecom) {
                        driveTelecomConnection(context, data, CallkitConstants.ACTION_CALL_DECLINE)
                    }
                    FlutterCallkitIncomingPlugin.notifyEventCallbacks(CallkitEventCallback.CallEvent.DECLINE, data)
                    // clear notification
                    getCallkitNotificationManager(context).clearIncomingNotification(data, false)
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_DECLINE, data)
                    removeCall(context, Data.fromBundle(data))
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_ENDED}" -> {
                try {
                    if (!fromTelecom) {
                        driveTelecomConnection(context, data, CallkitConstants.ACTION_CALL_ENDED)
                    }
                    FlutterCallkitIncomingPlugin.notifyEventCallbacks(CallkitEventCallback.CallEvent.END, data)
                    // clear notification and stop service
                    getCallkitNotificationManager(context).clearIncomingNotification(data, false)
                    CallkitNotificationService.stopService(context)
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_ENDED, data)
                    removeCall(context, Data.fromBundle(data))
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_TIMEOUT}" -> {
                try {
                    if (!fromTelecom) {
                        driveTelecomConnection(context, data, CallkitConstants.ACTION_CALL_TIMEOUT)
                    }
                    // clear notification and show miss notification
                    val notificationManager = getCallkitNotificationManager(context)
                    notificationManager.clearIncomingNotification(data, false)
                    notificationManager.showMissCallNotification(data)
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_TIMEOUT, data)
                    removeCall(context, Data.fromBundle(data))
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_CONNECTED}" -> {
                try {
                    // update notification on going connected
                    getCallkitNotificationManager(context).showOngoingCallNotification(data, true)
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_CONNECTED, data)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_CALLBACK}" -> {
                try {
                    getCallkitNotificationManager(context).clearMissCallNotification(data)
                    sendEventFlutter(context, CallkitConstants.ACTION_CALL_CALLBACK, data)
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                        val closeNotificationPanel = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
                        context.sendBroadcast(closeNotificationPanel)
                    }
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }
        }
    }

    private fun sendEventFlutter(context: Context, event: String, data: Bundle) {
        if (silenceEvents) return

        val android = mapOf(
            "isCustomNotification" to data.getBoolean(
                CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_NOTIFICATION,
                false
            ),
            "isCustomSmallExNotification" to data.getBoolean(
                CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_SMALL_EX_NOTIFICATION,
                false
            ),
            "ringtonePath" to data.getString(CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH, ""),
            "backgroundColor" to data.getString(
                CallkitConstants.EXTRA_CALLKIT_BACKGROUND_COLOR,
                ""
            ),
            "backgroundUrl" to data.getString(CallkitConstants.EXTRA_CALLKIT_BACKGROUND_URL, ""),
            "actionColor" to data.getString(CallkitConstants.EXTRA_CALLKIT_ACTION_COLOR, ""),
            "textColor" to data.getString(CallkitConstants.EXTRA_CALLKIT_TEXT_COLOR, ""),
            "incomingCallNotificationChannelName" to data.getString(
                CallkitConstants.EXTRA_CALLKIT_INCOMING_CALL_NOTIFICATION_CHANNEL_NAME,
                ""
            ),
            "missedCallNotificationChannelName" to data.getString(
                CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_NOTIFICATION_CHANNEL_NAME,
                ""
            ),
            "isImportant" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_IS_IMPORTANT, true),
            "isBot" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_IS_BOT, false),
        )
        val missedCallNotification = mapOf(
            "id" to data.getInt(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_ID),
            "showNotification" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_SHOW),
            "count" to data.getInt(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_COUNT),
            "subtitle" to data.getString(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_SUBTITLE),
            "callbackText" to data.getString(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_CALLBACK_TEXT),
            "isShowCallback" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_CALLBACK_SHOW),
        )
        val callingNotification = mapOf(
            "id" to data.getString(CallkitConstants.EXTRA_CALLKIT_CALLING_ID),
            "showNotification" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW),
            "subtitle" to data.getString(CallkitConstants.EXTRA_CALLKIT_CALLING_SUBTITLE),
            "callbackText" to data.getString(CallkitConstants.EXTRA_CALLKIT_CALLING_HANG_UP_TEXT),
            "isShowCallback" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_HANG_UP_SHOW),
        )
        val forwardData = mapOf(
            "id" to data.getString(CallkitConstants.EXTRA_CALLKIT_ID, ""),
            "nameCaller" to data.getString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, ""),
            "avatar" to data.getString(CallkitConstants.EXTRA_CALLKIT_AVATAR, ""),
            "number" to data.getString(CallkitConstants.EXTRA_CALLKIT_HANDLE, ""),
            "type" to data.getInt(CallkitConstants.EXTRA_CALLKIT_TYPE, 0),
            "duration" to data.getLong(CallkitConstants.EXTRA_CALLKIT_DURATION, 0L),
            "textAccept" to data.getString(CallkitConstants.EXTRA_CALLKIT_TEXT_ACCEPT, ""),
            "textDecline" to data.getString(CallkitConstants.EXTRA_CALLKIT_TEXT_DECLINE, ""),
            "acceptColor" to data.getString(CallkitConstants.EXTRA_CALLKIT_ACCEPT_COLOR, ""),
            "declineColor" to data.getString(CallkitConstants.EXTRA_CALLKIT_DECLINE_COLOR, ""),
            "extra" to data.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA),
            "missedCallNotification" to missedCallNotification,
            "callingNotification" to callingNotification,
            "android" to android
        )
        FlutterCallkitIncomingPlugin.sendEvent(context, event, forwardData)
    }
}
