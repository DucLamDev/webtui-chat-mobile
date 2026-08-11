package com.hiennv.flutter_callkit_incoming

import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.ConcurrentHashMap

/** Bridges Dart's durable acknowledgement back to the owning WorkManager job. */
internal object CallkitActionCompletionRegistry {
    private val completions = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()

    fun prepare(actionId: String): CompletableDeferred<Boolean> {
        return completions.computeIfAbsent(actionId) { CompletableDeferred() }
    }

    fun complete(actionId: String) {
        completions.remove(actionId)?.complete(true)
    }

    fun release(actionId: String) {
        completions.remove(actionId)?.cancel()
    }
}
