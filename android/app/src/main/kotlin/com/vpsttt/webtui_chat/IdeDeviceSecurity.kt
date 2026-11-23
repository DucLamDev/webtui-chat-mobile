package com.vpsttt.webtui_chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Khoá màn hình / vân tay cho mục IDE (kênh `webtui/biometric`):
 *  - authenticateDeviceOwner: mở mục IDE;
 *  - createStepKey / signWithStepKey: khoá xác nhận P-256 trong phần cứng an toàn (StrongBox,
 *    không có thì TEE), mỗi lần ký phải xác nhận bằng sinh trắc học mức mạnh (không nhận mật
 *    mã máy); thêm / xoá sinh trắc học thì khoá mất hiệu lực (`key_invalid`).
 * Dùng BiometricPrompt của framework (không cần androidx), nên giữ nguyên FlutterActivity.
 */
class IdeDeviceSecurity(private val activity: Activity) {
    companion object {
        const val REQUEST_CONFIRM_CREDENTIAL = 7411
        private const val KEYSTORE = "AndroidKeyStore"
        // BiometricPrompt.BIOMETRIC_ERROR_NEGATIVE_BUTTON (= 13) không công khai trong SDK framework.
        private const val ERROR_NEGATIVE_BUTTON = 13
        private const val AUTHENTICATORS =
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        // Khoá xác nhận: chỉ sinh trắc học mức mạnh.
        private const val STEP_AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_STRONG
    }

    private var credentialResult: MethodChannel.Result? = null

    fun handles(method: String) =
        method == "authenticateDeviceOwner" || method == "createStepKey" ||
            method == "signWithStepKey" || method == "deleteStepKey" ||
            method == "uptimeMs"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "authenticateDeviceOwner" ->
                authenticateDeviceOwner(args?.get("reason") as? String, result)
            "createStepKey" -> createStepKey(args?.get("alias") as? String, result)
            "deleteStepKey" -> deleteStepKey(args?.get("alias") as? String, result)
            // Đồng hồ tính cả lúc máy ngủ, người dùng không chỉnh được (đo thời gian nền).
            "uptimeMs" -> result.success(SystemClock.elapsedRealtime())
            "signWithStepKey" -> signWithStepKey(
                args?.get("alias") as? String,
                args?.get("data") as? String,
                args?.get("reason") as? String,
                result
            )
            else -> result.notImplemented()
        }
    }

    private fun keyguard() = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager

    private fun deviceSecure(): Boolean = keyguard()?.isDeviceSecure == true

    private fun title(reason: String?) = reason?.takeIf { it.isNotBlank() } ?: "Xác nhận để dùng IDE"

    // ---- mở mục: vân tay hoặc mã khoá màn hình ----

    private fun authenticateDeviceOwner(reason: String?, result: MethodChannel.Result) {
        if (!deviceSecure()) {
            result.success("notEnrolled")
            return
        }
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                val manager = activity.getSystemService(BiometricManager::class.java)
                when (manager?.canAuthenticate(AUTHENTICATORS)) {
                    BiometricManager.BIOMETRIC_SUCCESS -> Unit
                    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> {
                        result.success("notEnrolled")
                        return
                    }
                    else -> {
                        result.success("unavailable")
                        return
                    }
                }
                val completed = AtomicBoolean(false)
                val finish: (String) -> Unit = { value ->
                    if (completed.compareAndSet(false, true)) result.success(value)
                }
                val prompt = BiometricPrompt.Builder(activity)
                    .setTitle(title(reason))
                    .setAllowedAuthenticators(AUTHENTICATORS)
                    .build()
                prompt.authenticate(
                    CancellationSignal(),
                    activity.mainExecutor,
                    ownerCallback(finish)
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                val completed = AtomicBoolean(false)
                val finish: (String) -> Unit = { value ->
                    if (completed.compareAndSet(false, true)) result.success(value)
                }
                @Suppress("DEPRECATION")
                val prompt = BiometricPrompt.Builder(activity)
                    .setTitle(title(reason))
                    .setDeviceCredentialAllowed(true)
                    .build()
                prompt.authenticate(
                    CancellationSignal(),
                    activity.mainExecutor,
                    ownerCallback(finish)
                )
            }
            else -> confirmWithKeyguard(reason, result)
        }
    }

    private fun ownerCallback(finish: (String) -> Unit) =
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                finish("ok")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                finish(errorToResult(errorCode))
            }
        }

    private fun errorToResult(code: Int): String = when (code) {
        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
        BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
        ERROR_NEGATIVE_BUTTON -> "cancelled"
        BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS,
        BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL -> "notEnrolled"
        else -> "unavailable"
    }

    /** Máy < API 29: hộp nhập mã khoá màn hình của hệ thống (KeyguardManager). */
    @Suppress("DEPRECATION")
    private fun confirmWithKeyguard(reason: String?, result: MethodChannel.Result) {
        val intent = keyguard()?.createConfirmDeviceCredentialIntent(title(reason), null)
        if (intent == null) {
            result.success("unavailable")
            return
        }
        credentialResult?.success("cancelled")
        credentialResult = result
        activity.startActivityForResult(intent, REQUEST_CONFIRM_CREDENTIAL)
    }

    /** MainActivity chuyển `onActivityResult` vào đây; trả true nếu đã xử lý. */
    fun onActivityResult(requestCode: Int, resultCode: Int, @Suppress("UNUSED_PARAMETER") data: Intent?): Boolean {
        if (requestCode != REQUEST_CONFIRM_CREDENTIAL) return false
        val pending = credentialResult
        credentialResult = null
        pending?.success(if (resultCode == Activity.RESULT_OK) "ok" else "cancelled")
        return true
    }

    // ---- khoá xác nhận P-256 ----

    /** Xoá khoá xác nhận (gắn lại thành công thì xoá khoá cũ, gắn hỏng thì xoá khoá mới). */
    private fun deleteStepKey(alias: String?, result: MethodChannel.Result) {
        if (alias.isNullOrBlank()) {
            result.error("unavailable", "alias required", null)
            return
        }
        try {
            val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            if (store.containsAlias(alias)) store.deleteEntry(alias)
            result.success(null)
        } catch (e: Exception) {
            result.error("unavailable", e.javaClass.simpleName, null)
        }
    }

    private fun createStepKey(alias: String?, result: MethodChannel.Result) {
        if (alias.isNullOrBlank()) {
            result.error("unavailable", "alias required", null)
            return
        }
        // Ký cần BiometricPrompt (API 28+): máy cũ hơn không gắn được IDE.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("unsupported", "android < 9", null)
            return
        }
        if (!deviceSecure()) {
            result.error("notEnrolled", "no secure lock screen", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val manager = activity.getSystemService(BiometricManager::class.java)
            when (manager?.canAuthenticate(STEP_AUTHENTICATORS)) {
                BiometricManager.BIOMETRIC_SUCCESS -> Unit
                BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> {
                    result.error("biometricRequired", "no strong biometric enrolled", null)
                    return
                }
                BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> {
                    result.error("unsupported", "no strong biometric hardware", null)
                    return
                }
                else -> {
                    result.error("unavailable", "biometric not ready", null)
                    return
                }
            }
        }
        try {
            val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            if (store.containsAlias(alias)) store.deleteEntry(alias)
            val pair = try {
                // StrongBox trước; máy không có (hoặc từ chối) thì lùi về TEE.
                try {
                    generateStepKey(alias, strongBox = true)
                } catch (e: StrongBoxUnavailableException) {
                    if (store.containsAlias(alias)) store.deleteEntry(alias)
                    generateStepKey(alias, strongBox = false)
                }
            } catch (e: Exception) {
                // Máy chưa đăng ký sinh trắc học: Keystore từ chối tạo khoá gắn sinh trắc
                // (InvalidAlgorithmParameterException / IllegalStateException).
                if (e is java.security.InvalidAlgorithmParameterException || e is IllegalStateException) {
                    result.error("biometricRequired", "no biometric enrolled", null)
                    return
                }
                throw e
            }
            // Khoá phải nằm trong phần cứng an toàn và đúng chính sách; không thì xoá, báo lỗi.
            if (!keyMeetsPolicy(pair.private as PrivateKey)) {
                store.deleteEntry(alias)
                result.error("unsupported", "key not in secure hardware", null)
                return
            }
            // `encoded` của khoá công khai là SubjectPublicKeyInfo DER.
            result.success(Base64.encodeToString(pair.public.encoded, Base64.NO_WRAP))
        } catch (e: Exception) {
            result.error("unavailable", e.javaClass.simpleName, null)
        }
    }

    private fun generateStepKey(alias: String, strongBox: Boolean): KeyPair {
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            // Thêm / xoá sinh trắc học: khoá mất hiệu lực, phải gắn lại.
            .setInvalidatedByBiometricEnrollment(true)
            .setIsStrongBoxBacked(strongBox)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Hỏi mỗi lần ký (thời hạn 0), chỉ sinh trắc học mức mạnh, không nhận mật mã máy.
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        }
        // API 28–29: không đặt thời hạn xác thực thì khoá chỉ mở bằng sinh trắc học qua
        // CryptoObject, mỗi lần ký.
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
        generator.initialize(builder.build())
        return generator.generateKeyPair()
    }

    /** Khoá nằm trong phần cứng an toàn (TEE / StrongBox), ký mỗi lần phải xác thực, mất hiệu lực khi
     *  đổi sinh trắc học. Khoá tạo bởi bản cũ (nhận mật mã máy) cũng không đạt. */
    private fun keyMeetsPolicy(key: PrivateKey): Boolean {
        val info = try {
            KeyFactory.getInstance(key.algorithm, KEYSTORE).getKeySpec(key, KeyInfo::class.java)
        } catch (e: Exception) {
            return false
        }
        val secureHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        } else {
            @Suppress("DEPRECATION")
            info.isInsideSecureHardware
        }
        if (!secureHardware || !info.isUserAuthenticationRequired) return false
        if (!info.isInvalidatedByBiometricEnrollment) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (info.userAuthenticationType != KeyProperties.AUTH_BIOMETRIC_STRONG) return false
            if (info.userAuthenticationValidityDurationSeconds > 0) return false
        } else {
            @Suppress("DEPRECATION")
            if (info.userAuthenticationValidityDurationSeconds > 0) return false
        }
        return true
    }

    private fun signWithStepKey(
        alias: String?,
        dataBase64: String?,
        reason: String?,
        result: MethodChannel.Result
    ) {
        if (alias.isNullOrBlank() || dataBase64 == null) {
            result.error("unavailable", "alias and data required", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("unsupported", "android < 9", null)
            return
        }
        val data = try {
            Base64.decode(dataBase64, Base64.DEFAULT)
        } catch (e: IllegalArgumentException) {
            result.error("unavailable", "bad data", null)
            return
        }
        val signature = try {
            val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val key = store.getKey(alias, null) as? PrivateKey
            if (key == null) {
                result.error("key_missing", "no key", null)
                return
            }
            // Khoá cũ (nhận cả mật mã máy, không mất hiệu lực khi đổi sinh trắc): coi như
            // đã mất hiệu lực, phải gắn lại.
            if (!keyMeetsPolicy(key)) {
                result.error("key_invalid", "key policy outdated", null)
                return
            }
            Signature.getInstance("SHA256withECDSA").apply { initSign(key) }
        } catch (e: KeyPermanentlyInvalidatedException) {
            result.error("key_invalid", "key invalidated", null)
            return
        } catch (e: Exception) {
            result.error("unavailable", e.javaClass.simpleName, null)
            return
        }
        val completed = AtomicBoolean(false)
        val fail: (String) -> Unit = { code ->
            if (completed.compareAndSet(false, true)) result.error(code, code, null)
        }
        val builder = BiometricPrompt.Builder(activity).setTitle(title(reason))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(STEP_AUTHENTICATORS)
        }
        // Không nhận mật mã máy nên hộp cần nút Huỷ riêng.
        builder.setNegativeButton("Huỷ", activity.mainExecutor) { _, _ -> fail("cancelled") }
        builder.build().authenticate(
            BiometricPrompt.CryptoObject(signature),
            CancellationSignal(),
            activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                    try {
                        val sig = r.cryptoObject?.signature
                        if (sig == null) {
                            fail("unavailable")
                            return
                        }
                        sig.update(data)
                        val der = sig.sign()
                        if (completed.compareAndSet(false, true)) {
                            result.success(Base64.encodeToString(der, Base64.NO_WRAP))
                        }
                    } catch (e: Exception) {
                        fail("unavailable")
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    fail(
                        when (errorToResult(errorCode)) {
                            "cancelled" -> "cancelled"
                            "notEnrolled" -> "notEnrolled"
                            else -> "unavailable"
                        }
                    )
                }
            }
        )
    }
}
