package com.hiennv.flutter_callkit_incoming

import android.content.Context
import android.os.Bundle
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data as WorkData
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Owns cold terminal-call delivery after BroadcastReceiver.onReceive returns.
 *
 * WorkManager keeps the process important, persists retries across process
 * death, and applies a network constraint. The actual HTTPS/auth policy stays
 * in Dart so it shares the app's secure storage and server binding rules.
 */
internal class CallkitPendingActionWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "CallkitPendingWorker"
        private const val KEY_ACTION_ID = "action_id"
        private const val KEY_EVENT = "event"
        private const val KEY_CALL_ID = "call_id"
        private const val KEY_INSTANCE_ID = "instance_id"
        private const val KEY_WORKSPACE_ID = "workspace_id"
        private const val KEY_CHANNEL_ID = "channel_id"
        private const val KEY_MODE = "mode"
        private const val KEY_SERVER_BASE_URL = "server_base_url"

        private val terminalEvents = setOf(
            CallkitConstants.ACTION_CALL_DECLINE,
            CallkitConstants.ACTION_CALL_ENDED,
            CallkitConstants.ACTION_CALL_TIMEOUT,
        )

        fun enqueue(
            context: Context,
            event: String,
            bundle: Bundle,
            actionId: String?,
        ) {
            val normalizedActionId = actionId?.trim().orEmpty()
            if (event !in terminalEvents || normalizedActionId.isEmpty()) return
            val data = try {
                Data.fromBundle(bundle)
            } catch (error: Exception) {
                Log.w(TAG, "Unable to enqueue $event: ${error.message}")
                return
            }
            val extra = data.extra
            val input = WorkData.Builder()
                .putString(KEY_ACTION_ID, normalizedActionId)
                .putString(KEY_EVENT, event)
                .putString(KEY_CALL_ID, data.id.trim())
                .putString(KEY_INSTANCE_ID, extra.stringValue("instance_id").lowercase())
                .putString(KEY_WORKSPACE_ID, extra.stringValue("workspace_id"))
                .putString(KEY_CHANNEL_ID, extra.stringValue("channel_id"))
                .putString(
                    KEY_MODE,
                    extra.stringValue("mode", if (data.type > 0) "video" else "audio"),
                )
                .putString(KEY_SERVER_BASE_URL, extra.stringValue("server_base_url"))
                .build()
            val request = OneTimeWorkRequestBuilder<CallkitPendingActionWorker>()
                .setInputData(input)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                // The receiver's bounded goAsync lease provides the prompt
                // attempt. This normal durable job avoids expedited-worker FGS
                // requirements and starts after that lease as retry/fallback.
                .setInitialDelay(10L, TimeUnit.SECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10L, TimeUnit.SECONDS)
                .addTag("webtui-call-action")
                .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                "webtui-call-action-$normalizedActionId",
                ExistingWorkPolicy.KEEP,
                request,
            )
        }

        private fun Map<String, Any?>.stringValue(
            key: String,
            fallback: String = "",
        ): String {
            val value = this[key]?.toString()?.trim()
            return if (value.isNullOrEmpty()) fallback.trim() else value
        }
    }

    override suspend fun doWork(): Result {
        val actionId = inputData.getString(KEY_ACTION_ID)?.trim().orEmpty()
        val event = inputData.getString(KEY_EVENT)?.trim().orEmpty()
        val instanceId = inputData.getString(KEY_INSTANCE_ID)?.trim()?.lowercase().orEmpty()
        if (actionId.isEmpty() || instanceId.isEmpty() || event !in terminalEvents) {
            return Result.failure()
        }
        if (!CallkitPendingActionStore.contains(applicationContext, actionId)) {
            return Result.success()
        }

        val completion = CallkitActionCompletionRegistry.prepare(actionId)
        val body = mapOf<String, Any?>(
            "id" to inputData.getString(KEY_CALL_ID).orEmpty(),
            "nameCaller" to "",
            "type" to if (inputData.getString(KEY_MODE) == "video") 1 else 0,
            "extra" to hashMapOf<String, Any?>(
                "call_id" to inputData.getString(KEY_CALL_ID).orEmpty(),
                "instance_id" to instanceId,
                "workspace_id" to inputData.getString(KEY_WORKSPACE_ID).orEmpty(),
                "channel_id" to inputData.getString(KEY_CHANNEL_ID).orEmpty(),
                "mode" to inputData.getString(KEY_MODE).orEmpty(),
                "status" to "ringing",
                "target_type" to "call",
                "event_type" to "call_invite",
                "server_base_url" to inputData.getString(KEY_SERVER_BASE_URL).orEmpty(),
            ),
        )
        withContext(Dispatchers.Main.immediate) {
            // FlutterLoader/FlutterEngine creation is main-thread-only.
            CallkitBackgroundExecutor.send(applicationContext, event, body)
        }

        val acknowledged = withTimeoutOrNull(50_000L) {
            completion.await()
        } == true
        CallkitActionCompletionRegistry.release(actionId)
        if (acknowledged || !CallkitPendingActionStore.contains(applicationContext, actionId)) {
            return Result.success()
        }
        return Result.retry()
    }
}
