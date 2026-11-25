package com.vpsttt.webtui_chat

import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.fingerprint.FingerprintManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.UnrecoverableKeyException
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Khoá "possession" của VPSTTT IDE nhúng (kênh `webtui/ide_web_keys`): EC P-256 nằm trong phần cứng
 * an toàn (StrongBox, không có thì TEE), không đòi xác thực, không xuất được. Khoá sinh trắc vẫn do
 * `webtui/biometric` quản lý; ở đây chỉ xem trạng thái / xoá theo alias.
 */
class IdeWebDeviceKeys(private val context: Context, messenger: BinaryMessenger) {
    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        // Chỉ đụng khoá của IDE nhúng, không đụng khoá khác của app.
        val POSSESSION_ALIAS = Regex("^ideweb\\.p\\.[0-9a-f]{24}\\.[A-Za-z0-9_-]{16,128}$")
        val ANY_ALIAS = Regex("^ideweb\\.[pb]\\.[0-9a-f]{24}\\.[A-Za-z0-9_-]{16,128}$")
        const val MAX_DATA_BYTES = 64 * 1024
    }

    private class KeyFailure(val code: String) : Exception(code)

    private val channel = MethodChannel(messenger, "webtui/ide_web_keys")
    private val main = Handler(Looper.getMainLooper())
    // Keystore (nhất là StrongBox) có thể mất vài giây: không chạy ở luồng giao diện.
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(::handle)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val alias = args?.get("alias") as? String
        when (call.method) {
            "createPossessionKey" -> run(result) { create(checked(alias, POSSESSION_ALIAS)) }
            "signPossession" -> run(result) {
                sign(checked(alias, POSSESSION_ALIAS), args?.get("data") as? ByteArray)
            }
            "keyState" -> run(result) { state(checked(alias, ANY_ALIAS)) }
            "biometricState" -> run(result) { biometricState() }
            "deleteKey" -> run(result) {
                val store = keyStore()
                val name = checked(alias, ANY_ALIAS)
                if (store.containsAlias(name)) store.deleteEntry(name)
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun run(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            val reply: () -> Unit = try {
                val value = work()
                val success = { result.success(value) }
                success
            } catch (e: KeyFailure) {
                { result.error(e.code, e.code, null) }
            } catch (e: Exception) {
                // Chỉ tên lớp lỗi: không đưa alias, dữ liệu ký ra ngoài.
                { result.error("failed", e.javaClass.simpleName, null) }
            }
            main.post { reply() }
        }
    }

    private fun checked(alias: String?, pattern: Regex): String =
        alias?.takeIf { pattern.matches(it) } ?: throw KeyFailure("failed")

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun create(alias: String): Map<String, Any> {
        val store = keyStore()
        if (store.containsAlias(alias)) store.deleteEntry(alias)
        var completed = false
        try {
            val (pair, strongBox) = generate(alias, store)
            val hardware = hardwareLevel(pair.private, strongBox) ?: throw KeyFailure("unsupported")
            // `encoded` của khoá công khai là SubjectPublicKeyInfo DER.
            val publicKey = Base64.encodeToString(
                pair.public.encoded,
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )
            completed = true
            return mapOf("publicKey" to publicKey, "hardware" to hardware)
        } finally {
            // Khoá phần mềm hoặc tạo dở: không để lại.
            if (!completed) {
                try {
                    store.deleteEntry(alias)
                } catch (_: Exception) {
                    // Khoá chưa có thì thôi.
                }
            }
        }
    }

    private fun generate(alias: String, store: KeyStore): Pair<KeyPair, Boolean> {
        // `setUnlockedDeviceRequired` có lỗi ở một số máy Android 9–11, nên chỉ bật từ Android 12;
        // máy nào từ chối thuộc tính này thì lùi về khoá không có nó (vẫn nằm trong chip).
        val unlockedOptions =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) listOf(true, false) else listOf(false)
        var last: Exception? = null
        for (unlocked in unlockedOptions) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    return generate(alias, unlocked, strongBox = true) to true
                } catch (e: StrongBoxUnavailableException) {
                    last = e
                } catch (e: Exception) {
                    // Một số máy báo lỗi khác thay vì StrongBoxUnavailable: thử TEE.
                    last = e
                }
                if (store.containsAlias(alias)) store.deleteEntry(alias)
            }
            try {
                return generate(alias, unlocked, strongBox = false) to false
            } catch (e: Exception) {
                last = e
            }
            if (store.containsAlias(alias)) store.deleteEntry(alias)
        }
        throw last ?: KeyFailure("failed")
    }

    private fun generate(alias: String, unlocked: Boolean, strongBox: Boolean): KeyPair {
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(strongBox)
            if (unlocked) builder.setUnlockedDeviceRequired(true)
        }
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
        generator.initialize(builder.build())
        return generator.generateKeyPair()
    }

    /** `strongbox` / `tee`; null nếu khoá không nằm trong phần cứng an toàn. */
    private fun hardwareLevel(key: PrivateKey, strongBox: Boolean): String? {
        val info = KeyFactory.getInstance(key.algorithm, KEYSTORE).getKeySpec(key, KeyInfo::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                else -> null
            }
        }
        @Suppress("DEPRECATION")
        if (!info.isInsideSecureHardware) return null
        return if (strongBox) "strongbox" else "tee"
    }

    private fun sign(alias: String, data: ByteArray?): ByteArray {
        if (data == null || data.isEmpty() || data.size > MAX_DATA_BYTES) throw KeyFailure("failed")
        val key = try {
            keyStore().getKey(alias, null) as? PrivateKey
        } catch (_: UnrecoverableKeyException) {
            null
        } ?: throw KeyFailure("key_missing")
        // SHA-256 do Signature tính; chữ ký ECDSA của Keystore đã là DER.
        return try {
            Signature.getInstance("SHA256withECDSA").run {
                initSign(key)
                update(data)
                sign()
            }
        } catch (_: KeyPermanentlyInvalidatedException) {
            throw KeyFailure("key_missing")
        }
    }

    private fun state(alias: String): Map<String, Any?> {
        val none = mapOf("exists" to false, "usable" to false, "hardware" to null)
        return try {
            val store = keyStore()
            if (!store.containsAlias(alias)) return none
            val key = store.getKey(alias, null) as? PrivateKey ?: return none
            // Trước Android 12 hệ thống không cho biết khoá ở StrongBox hay TEE.
            val hardware = hardwareLevel(key, strongBox = false)
            val usable = hardware != null && try {
                Signature.getInstance("SHA256withECDSA").initSign(key)
                true
            } catch (_: Exception) {
                false
            }
            mapOf("exists" to true, "usable" to usable, "hardware" to hardware)
        } catch (_: UnrecoverableKeyException) {
            mapOf("exists" to true, "usable" to false, "hardware" to null)
        } catch (_: Exception) {
            none
        }
    }

    /** Sinh trắc mạnh, đúng điều kiện `webtui/biometric` đòi khi tạo khoá sinh trắc. */
    private fun biometricState(): Map<String, Boolean> {
        var available = false
        var enrolled = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val manager = context.getSystemService(BiometricManager::class.java)
            when (manager?.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
                BiometricManager.BIOMETRIC_SUCCESS -> {
                    available = true
                    enrolled = true
                }
                BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> available = true
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Android 9–10 không hỏi được mức mạnh: chỉ tính vân tay.
            @Suppress("DEPRECATION")
            val fingerprint = context.getSystemService(FingerprintManager::class.java)
            @Suppress("DEPRECATION")
            if (fingerprint?.isHardwareDetected == true) {
                available = true
                enrolled = fingerprint.hasEnrolledFingerprints()
            }
        }
        return mapOf("available" to available, "enrolled" to enrolled, "strong" to available)
    }
}
