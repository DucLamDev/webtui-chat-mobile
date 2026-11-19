package com.kasem.receive_sharing_intent

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.util.UUID


object FileDirectory {

    /**
     * WebTUI patch: chỉ nhận URI `content://` và luôn chép nội dung qua
     * ContentResolver vào thư mục chia sẻ tạm
     * `cacheDir/receive_sharing_intent/<ngẫu nhiên>/<tên đã làm sạch>`.
     * URI `file://` và các scheme khác không được nhận (trả về null), app chỉ
     * đọc dữ liệu mà bên chia sẻ đã cấp quyền qua URI.
     */
    fun getAbsolutePath(context: Context, uri: Uri): String? {
        if (!"content".equals(uri.scheme, ignoreCase = true) || uri.authority == null) {
            return null
        }
        return try {
            copyToShareCache(context, uri)
        } catch (exception: Exception) {
            Log.w("FileDirectory", "Không chép được tệp chia sẻ", exception)
            null
        }
    }

    private fun copyToShareCache(context: Context, uri: Uri): String? {
        val resolver = context.contentResolver
        val mimeType = resolver.getType(uri)
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        val fileName = SharedFileNames.sanitize(queryDisplayName(context, uri), extension)

        val shareRoot = File(context.cacheDir, SharedFileNames.SHARE_CACHE_DIR)
        val targetDir = SharedFileNames.confinedChild(shareRoot, UUID.randomUUID().toString())
                ?: return null
        if (!targetDir.mkdirs() && !targetDir.isDirectory) return null
        val targetFile = SharedFileNames.confinedChild(targetDir, fileName) ?: return null

        val input = resolver.openInputStream(uri) ?: return null
        input.use { source ->
            FileOutputStream(targetFile).use { fileOut ->
                source.copyTo(fileOut)
            }
        }
        return targetFile.path
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = context.contentResolver.query(
                    uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } catch (exception: Exception) {
            null
        } finally {
            cursor?.close()
        }
    }
}
