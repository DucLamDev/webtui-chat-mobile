package com.hiennv.flutter_callkit_incoming

import android.content.BroadcastReceiver
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Keeps the cold receiver process important for one prompt delivery attempt.
 * WorkManager remains the persistent fallback after this strictly bounded
 * lease finishes.
 */
internal object CallkitReceiverExecutionLease {
    private const val TAG = "CallkitReceiverLease"
    private const val MAX_LEASE_MS = 9_000L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val leases = ConcurrentHashMap<String, BroadcastReceiver.PendingResult>()

    fun hold(actionId: String, pendingResult: BroadcastReceiver.PendingResult) {
        leases.put(actionId, pendingResult)?.finishSafely()
        mainHandler.postDelayed({ complete(actionId, "timeout") }, MAX_LEASE_MS)
    }

    fun complete(actionId: String, reason: String = "acknowledged") {
        val pendingResult = leases.remove(actionId) ?: return
        pendingResult.finishSafely()
        Log.d(TAG, "Finished $actionId: $reason")
    }

    private fun BroadcastReceiver.PendingResult.finishSafely() {
        try {
            finish()
        } catch (error: Exception) {
            Log.w(TAG, "PendingResult.finish failed: ${error.message}")
        }
    }
}
