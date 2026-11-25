package com.vpsttt.webtui_chat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Mở trang đăng nhập VPSTTT IDE bằng trình duyệt hệ thống (kênh `webtui/ide_web_auth`): Custom Tabs
 * (không thêm thư viện), trình duyệt không hỗ trợ thì mở như liên kết thường. Kết quả về app qua
 * deep link `webtui://ide-web/callback` (`webtui/deeplink`).
 */
class IdeWebAuth(private val activity: Activity, messenger: BinaryMessenger) {
    private companion object {
        // Hằng của androidx.browser.customtabs.CustomTabsIntent.
        const val EXTRA_SESSION = "android.support.customtabs.extra.SESSION"
        const val EXTRA_TITLE_VISIBILITY = "android.support.customtabs.extra.TITLE_VISIBILITY"
        const val EXTRA_SHARE_STATE = "androidx.browser.customtabs.extra.SHARE_STATE"
        const val SHOW_PAGE_TITLE = 1
        const val SHARE_STATE_OFF = 2
    }

    private val channel = MethodChannel(messenger, "webtui/ide_web_auth")

    init {
        channel.setMethodCallHandler(::handle)
    }

    fun dispose() = channel.setMethodCallHandler(null)

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "authenticate") {
            result.notImplemented()
            return
        }
        val args = call.arguments as? Map<*, *>
        val uri = (args?.get("url") as? String)?.let(Uri::parse)
        if (uri == null || uri.scheme?.lowercase() != "https" || uri.host.isNullOrEmpty() ||
            uri.userInfo != null
        ) {
            result.error("invalid_url", "https URL required", null)
            return
        }
        if (args["callbackScheme"] != "webtui") {
            result.error("failed", "unsupported callback scheme", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            // Extra phiên (kể cả null) là dấu hiệu để trình duyệt mở dạng Custom Tabs.
            putExtras(Bundle().apply { putBinder(EXTRA_SESSION, null) })
            putExtra(EXTRA_TITLE_VISIBILITY, SHOW_PAGE_TITLE)
            // Địa chỉ mở mang vé dùng một lần: không cho nút chia sẻ.
            putExtra(EXTRA_SHARE_STATE, SHARE_STATE_OFF)
        }
        try {
            activity.startActivity(intent)
            result.success(mapOf("mode" to "deeplink"))
        } catch (_: ActivityNotFoundException) {
            result.error("failed", "no browser", null)
        } catch (_: RuntimeException) {
            result.error("failed", "cannot open browser", null)
        }
    }
}
