package com.hiennv.flutter_callkit_incoming

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

object CallkitBackgroundExecutor {
    private const val TAG = "CallkitBGExecutor"
    private const val CHANNEL = "flutter_callkit_incoming_background"

    @Volatile
    private var backgroundFlutterEngine: FlutterEngine? = null

    private var backgroundChannel: MethodChannel? = null
    private var dartReady = false
    private val pendingEvents = mutableListOf<Pair<String, Map<String, Any?>>>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val idleShutdown = Runnable {
        synchronized(this) {
            if (pendingEvents.isEmpty()) {
                destroyLocked("bounded idle timeout")
            }
        }
    }

    val registered: Boolean
        get() = backgroundFlutterEngine != null

    @Synchronized
    fun start(context: Context, pluginCallbackHandle: Long) {
        if (backgroundFlutterEngine != null) {
            Log.d(TAG, "Background engine already running")
            return
        }

        val appCtx = context.applicationContext

        val loader: FlutterLoader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(appCtx)
        loader.ensureInitializationComplete(appCtx, null)

        backgroundFlutterEngine = FlutterEngine(appCtx)

        val callbackInfo =
            FlutterCallbackInformation.lookupCallbackInformation(pluginCallbackHandle)

        val args = DartExecutor.DartCallback(
            appCtx.assets,
            loader.findAppBundlePath(),
            callbackInfo
        )

        backgroundChannel = MethodChannel(
            backgroundFlutterEngine!!.dartExecutor.binaryMessenger,
            CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "initialized") {
                    synchronized(this) {
                        dartReady = true
                        flushLocked()
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
        }
        // Install the native half of the readiness handshake before starting
        // Dart. A fast callback isolate can now never emit `initialized`
        // between executeDartCallback and MethodChannel registration.
        backgroundFlutterEngine!!.dartExecutor.executeDartCallback(args)

        Log.d(TAG, "Background engine started")
    }

    /**
     * Buffer first, then lazily recreate the Dart executor from the callback
     * handle persisted during normal app bootstrap. `initialized` is an
     * explicit readiness handshake, so an OEM-cold process cannot race the
     * Dart MethodChannel handler and drop the first action.
     */
    @Synchronized
    fun send(context: Context, event: String, body: Map<String, Any?>) {
        mainHandler.removeCallbacks(idleShutdown)
        pendingEvents.add(event to body)
        if (backgroundFlutterEngine == null) {
            val callbackHandle = getPluginCallbackHandle(context) ?: 0L
            if (callbackHandle <= 0L) {
                Log.w(TAG, "No persisted background callback; queued $event for app replay")
                pendingEvents.clear()
                return
            }
            start(context.applicationContext, callbackHandle)
        }
        flushLocked()
    }

    @Synchronized
    fun stopIfIdle(context: Context) {
        mainHandler.postDelayed({
            synchronized(this) {
                if (CallkitPendingActionStore.pending(context).isNotEmpty() ||
                    pendingEvents.isNotEmpty()
                ) {
                    return@synchronized
                }
                destroyLocked("durable queue drained")
            }
        }, 1000L)
    }

    private fun flushLocked() {
        if (!dartReady) return
        val channel = backgroundChannel ?: return
        if (pendingEvents.isEmpty()) return
        val events = pendingEvents.toList()
        pendingEvents.clear()
        events.forEach { (event, body) ->
            channel.invokeMethod(event, body)
        }
        // Failed authenticated actions remain in the durable native queue, but
        // the auxiliary engine must not live forever. Dart performs bounded
        // retries inside this window; a later app/process start replays again.
        mainHandler.removeCallbacks(idleShutdown)
        mainHandler.postDelayed(idleShutdown, 90_000L)
    }

    private fun destroyLocked(reason: String) {
        mainHandler.removeCallbacks(idleShutdown)
        backgroundChannel?.setMethodCallHandler(null)
        backgroundChannel = null
        backgroundFlutterEngine?.destroy()
        backgroundFlutterEngine = null
        dartReady = false
        Log.d(TAG, "Background engine stopped: $reason")
    }

    @Synchronized
    internal fun resetForTesting() {
        pendingEvents.clear()
        dartReady = false
        backgroundChannel = null
        backgroundFlutterEngine = null
    }
}
