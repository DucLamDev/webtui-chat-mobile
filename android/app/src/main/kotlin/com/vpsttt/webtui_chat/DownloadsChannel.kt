package com.vpsttt.webtui_chat

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * Kênh `webtui/downloads`: chép tệp đã tải (thư mục tạm của app) vào thư mục
 * Tải về của máy. Chỉ Android 10+ (MediaStore, không cần quyền lưu trữ);
 * bản cũ trả false để phía Dart mở tệp bằng ứng dụng khác.
 */
class DownloadsChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    init {
        MethodChannel(messenger, "webtui/downloads").setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val args = call.arguments as? Map<*, *>
                    val path = args?.get("path") as? String
                    val name = args?.get("name") as? String
                    val mime = (args?.get("mime") as? String)?.ifBlank { null }
                        ?: "application/octet-stream"
                    if (path == null || name == null) {
                        result.error("BAD_ARGS", "Thiếu path hoặc name", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val outcome = runCatching { save(path, name, mime) }
                        android.os.Handler(context.mainLooper).post {
                            outcome.fold(
                                { result.success(it) },
                                {
                                    if (it is BadPathException) {
                                        result.error("BAD_PATH", "Tệp không nằm trong thư mục tạm của app.", null)
                                    } else {
                                        result.error("SAVE_FAILED", it.message, null)
                                    }
                                },
                            )
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Bỏ đường dẫn, ký tự điều khiển / định dạng Unicode (Cf: U+202E, U+200B...), cắt độ dài giữ đuôi. */
    private fun safeName(raw: String): String {
        var s = raw.substringAfterLast('/').substringAfterLast('\\')
            .filter {
                val t = Character.getType(it)
                it.code >= 32 && it.code != 127 &&
                    t != Character.FORMAT.toInt() &&
                    t != Character.CONTROL.toInt() &&
                    t != Character.LINE_SEPARATOR.toInt() &&
                    t != Character.PARAGRAPH_SEPARATOR.toInt() &&
                    it !in "<>:\"|?*"
            }
            .trim().trimStart('.').trimEnd('.')
        if (s.length > 120) {
            val dot = s.lastIndexOf('.')
            val ext = if (dot > 0 && s.length - dot <= 12) s.substring(dot) else ""
            s = s.substring(0, 120 - ext.length) + ext
        }
        return s.ifEmpty { "tep-tai-ve" }
    }

    private fun save(path: String, rawName: String, mime: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val source = File(path)
        // Chỉ nhận tệp trong thư mục tạm / dữ liệu của chính app.
        val allowed = listOf(context.cacheDir, context.filesDir)
            .any { source.canonicalPath.startsWith(it.canonicalPath + File.separator) }
        if (!allowed || !source.isFile) {
            throw BadPathException()
        }
        val name = safeName(rawName)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return false
        try {
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(source).use { it.copyTo(out) }
            } ?: throw IllegalStateException("Không mở được nơi lưu")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return true
    }
}

/** Đường dẫn ngoài thư mục app: trả lỗi BAD_PATH (như iOS). */
private class BadPathException : Exception()
