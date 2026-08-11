package com.vpsttt.webtui_chat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private lateinit var deepLinkChannel: MethodChannel
    private var pendingDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingDeepLink = intent?.dataString
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "webtui/deeplink"
        )
        deepLinkChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUrl" -> {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "webtui/biometric"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isBiometricAvailable())
                "authenticate" -> authenticateBiometric(
                    (call.arguments as? Map<*, *>)?.get("reason") as? String,
                    result
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "webtui/privacy"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureScreen" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "webtui/launcher"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val url = arguments?.get("url") as? String
                    val parsedUrl = url?.let(Uri::parse)
                    val scheme = parsedUrl?.scheme?.lowercase()
                    if (url.isNullOrBlank() || (scheme != "https" && scheme != "http")) {
                        result.error("INVALID_URL", "A valid HTTP(S) URL is required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, parsedUrl).apply {
                            addCategory(Intent.CATEGORY_BROWSABLE)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = intent.dataString ?: return
        if (::deepLinkChannel.isInitialized) {
            deepLinkChannel.invokeMethod("url", url)
        } else {
            pendingDeepLink = url
        }
    }

    @Suppress("DEPRECATION")
    private fun isBiometricAvailable(): Boolean {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) {
            return false
        }
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                getSystemService(BiometricManager::class.java)
                    ?.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                val manager = getSystemService(FINGERPRINT_SERVICE) as? FingerprintManager
                manager?.isHardwareDetected == true && manager.hasEnrolledFingerprints()
            }
            else -> false
        }
    }

    private fun authenticateBiometric(reason: String?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !isBiometricAvailable()) {
            result.success(false)
            return
        }
        val completed = AtomicBoolean(false)
        val finish: (Boolean) -> Unit = { success ->
            if (completed.compareAndSet(false, true)) {
                result.success(success)
            }
        }
        val prompt = BiometricPrompt.Builder(this)
            .setTitle("Mở khóa WebTUI Chat")
            .setSubtitle(reason?.takeIf { it.isNotBlank() } ?: "Xác thực sinh trắc học")
            .setNegativeButton("Dùng mã PIN", mainExecutor) { _, _ -> finish(false) }
            .build()
        prompt.authenticate(
            CancellationSignal(),
            mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult
                ) {
                    finish(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finish(false)
                }
            }
        )
    }
}
