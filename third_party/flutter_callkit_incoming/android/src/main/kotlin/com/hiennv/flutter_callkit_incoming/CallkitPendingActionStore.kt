package com.hiennv.flutter_callkit_incoming

import android.content.Context
import android.os.Bundle
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Process-death-safe delivery queue for user and Telecom call actions.
 *
 * Notification receivers and self-managed Telecom callbacks can run before a
 * Flutter engine has attached. EventChannel delivery is best-effort in that
 * state, so every backend-relevant action is committed here first and replayed
 * through the MethodChannel after the authenticated application is ready.
 */
internal object CallkitPendingActionStore {
    private const val TAG = "CallkitPendingActions"
    private const val PREFS_NAME = "flutter_callkit_incoming_pending_actions"
    private const val PREFS_KEY = "actions"
    private const val MAX_ACTIONS = 32
    private const val MAX_AGE_MS = 24L * 60L * 60L * 1000L
    private val instanceIdPattern = Regex(
        "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    )

    private val supportedEvents = setOf(
        CallkitConstants.ACTION_CALL_ACCEPT,
        CallkitConstants.ACTION_CALL_DECLINE,
        CallkitConstants.ACTION_CALL_ENDED,
        CallkitConstants.ACTION_CALL_TIMEOUT,
    )

    @Synchronized
    fun record(context: Context, event: String, bundle: Bundle): String? {
        if (event !in supportedEvents) return null
        val data = try {
            Data.fromBundle(bundle)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to persist $event: ${error.message}")
            return null
        }
        val callId = data.id.trim()
        val extra = data.extra
        val instanceId = extra.stringValue("instance_id").lowercase()
        val workspaceId = extra.stringValue("workspace_id")
        val serverBaseUrl = extra.stringValue("server_base_url")
        if (
            callId.isEmpty() ||
            !instanceIdPattern.matches(instanceId) ||
            workspaceId.isEmpty() ||
            serverBaseUrl.isEmpty()
        ) return null

        val now = System.currentTimeMillis()
        val actionId = actionId(event, instanceId, callId)
        val entry = JSONObject().apply {
            put("action_id", actionId)
            put("event", event)
            put("call_id", callId)
            put("instance_id", instanceId)
            put("workspace_id", workspaceId)
            put("channel_id", extra.stringValue("channel_id"))
            put("mode", extra.stringValue("mode", if (data.type > 0) "video" else "audio"))
            // This value is only a selector. Dart must exact-match it against
            // the authenticated secure active-server binding before attaching
            // a bearer token; it is never trusted as an arbitrary API origin.
            put("server_base_url", serverBaseUrl)
            put("created_at_ms", now)
        }

        val retained = readEntries(context, now)
            .filterNot { it.optString("action_id") == actionId }
            .toMutableList()
        retained.add(entry)
        persist(context, retained.takeLast(MAX_ACTIONS))
        Log.d(TAG, "Persisted $actionId")
        return actionId
    }

    @Synchronized
    fun pending(context: Context): List<Map<String, Any?>> {
        val now = System.currentTimeMillis()
        val entries = readEntries(context, now).takeLast(MAX_ACTIONS)
        persist(context, entries)
        return entries.map { entry ->
            buildMap {
                put("action_id", entry.optString("action_id"))
                put("event", entry.optString("event"))
                put("call_id", entry.optString("call_id"))
                put("instance_id", entry.optString("instance_id"))
                put("workspace_id", entry.optString("workspace_id"))
                put("channel_id", entry.optString("channel_id"))
                put("mode", entry.optString("mode"))
                put("server_base_url", entry.optString("server_base_url"))
                put("created_at_ms", entry.optLong("created_at_ms"))
            }
        }
    }

    @Synchronized
    fun acknowledge(context: Context, actionId: String) {
        val normalized = actionId.trim()
        if (normalized.isEmpty()) return
        val retained = readEntries(context, System.currentTimeMillis())
            .filterNot { it.optString("action_id") == normalized }
        persist(context, retained)
        Log.d(TAG, "Acknowledged $normalized")
    }

    @Synchronized
    fun contains(context: Context, actionId: String): Boolean {
        val normalized = actionId.trim()
        if (normalized.isEmpty()) return false
        return readEntries(context, System.currentTimeMillis()).any {
            it.optString("action_id") == normalized
        }
    }

    private fun actionId(event: String, instanceId: String, callId: String): String =
        "$event:$instanceId:$callId"

    private fun readEntries(context: Context, now: Long): List<JSONObject> {
        val encoded = preferences(context).getString(PREFS_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(encoded)
            buildList {
                for (index in 0 until array.length()) {
                    val entry = array.optJSONObject(index) ?: continue
                    val createdAt = entry.optLong("created_at_ms", 0L)
                    val event = entry.optString("event")
                    val callId = entry.optString("call_id").trim()
                    val instanceId = entry.optString("instance_id").trim().lowercase()
                    val expectedActionId = actionId(event, instanceId, callId)
                    if (
                        event in supportedEvents &&
                        callId.isNotEmpty() &&
                        instanceIdPattern.matches(instanceId) &&
                        entry.optString("workspace_id").isNotBlank() &&
                        entry.optString("server_base_url").isNotBlank() &&
                        entry.optString("action_id") == expectedActionId &&
                        createdAt > 0L &&
                        now - createdAt <= MAX_AGE_MS
                    ) {
                        add(entry)
                    }
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "Discarding corrupt pending action queue: ${error.message}")
            emptyList()
        }
    }

    private fun persist(context: Context, entries: List<JSONObject>) {
        val array = JSONArray()
        entries.forEach(array::put)
        // commit() is intentional: a notification process can be killed as
        // soon as onReceive returns, so an asynchronous apply() can lose the
        // exact action this queue exists to protect.
        preferences(context).edit().putString(PREFS_KEY, array.toString()).commit()
    }

    private fun preferences(context: Context) = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun Map<String, Any?>.stringValue(key: String, fallback: String = ""): String {
        val value = this[key]?.toString()?.trim()
        return if (value.isNullOrEmpty()) fallback.trim() else value
    }
}
