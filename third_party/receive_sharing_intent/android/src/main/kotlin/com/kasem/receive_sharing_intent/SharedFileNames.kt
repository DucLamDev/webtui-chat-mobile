package com.kasem.receive_sharing_intent

import java.io.File

/**
 * WebTUI patch: làm sạch tên tệp nhận qua chia sẻ trước khi dùng làm tên tệp
 * trong thư mục chia sẻ tạm. Không phụ thuộc Android để kiểm được độc lập.
 */
object SharedFileNames {
    /** Thư mục con trong cacheDir chứa mọi tệp chép từ intent chia sẻ. */
    const val SHARE_CACHE_DIR = "receive_sharing_intent"

    private const val FALLBACK_BASE = "shared_file"
    private const val MAX_NAME_LENGTH = 120
    private const val MAX_EXTENSION_LENGTH = 16
    private val UNSAFE_CHARS = Regex("[\\u0000-\\u001F\\u007F:*?\"<>|]")
    private val SAFE_EXTENSION = Regex("^[A-Za-z0-9]{1,$MAX_EXTENSION_LENGTH}$")

    /**
     * Chỉ giữ phần tên tệp cuối cùng (bỏ mọi thư mục), bỏ ký tự điều khiển /
     * ký tự không hợp lệ, bỏ dấu chấm ở đầu; tên rỗng hoặc chỉ gồm dấu chấm
     * thì dùng tên mặc định kèm đuôi [fallbackExtension] nếu đuôi hợp lệ.
     */
    fun sanitize(displayName: String?, fallbackExtension: String?): String {
        val lastSegment = (displayName ?: "")
            .replace('\\', '/')
            .substringAfterLast('/')
        val cleaned = UNSAFE_CHARS.replace(lastSegment, "")
            .trim()
            .trimStart('.')
            .trim()
        if (cleaned.isEmpty() || cleaned.all { it == '.' }) {
            val extension = fallbackExtension?.trim()?.trimStart('.')
            return if (extension != null && SAFE_EXTENSION.matches(extension)) {
                "$FALLBACK_BASE.$extension"
            } else {
                FALLBACK_BASE
            }
        }
        return limitLength(cleaned)
    }

    /**
     * Trả về tệp đích `child` trong [parent] chỉ khi đường dẫn chuẩn hoá của
     * nó nằm ngay trong [parent]; ngược lại trả về null.
     */
    fun confinedChild(parent: File, child: String): File? {
        val parentPath = parent.canonicalFile
        val target = File(parentPath, child).canonicalFile
        return if (target.parentFile == parentPath) target else null
    }

    private fun limitLength(name: String): String {
        if (name.length <= MAX_NAME_LENGTH) return name
        val dot = name.lastIndexOf('.')
        val extension = if (dot > 0) name.substring(dot) else ""
        if (extension.length in 2..(MAX_EXTENSION_LENGTH + 1)) {
            return name.substring(0, MAX_NAME_LENGTH - extension.length) + extension
        }
        return name.substring(0, MAX_NAME_LENGTH)
    }
}
