package com.vpsttt.webtui_chat

import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowInsets
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewDatabase
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ScriptHandler
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.lang.ref.WeakReference
import java.util.UUID
import org.json.JSONException
import org.json.JSONObject

/**
 * Cầu nối giữa trang VPSTTT IDE trong WebView và app (kênh `webtui/ide_web_host`, sự kiện
 * `webtui/ide_web_host/events`). Chỉ khung chính đúng origin được gửi yêu cầu; nội dung do phần Dart
 * kiểm và xử lý. Mọi hàm chạy ở luồng giao diện; không ghi nhật ký nội dung.
 */
class IdeWebHost : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private companion object {
        const val NATIVE_OBJECT = "__AppChatNative"
        // `file.save` tối đa 14 MB; phần Dart kiểm hạn chặt hơn cho từng hàm.
        const val MAX_MESSAGE_CHARS = 14 * 1024 * 1024
        const val MAX_PENDING_REPLIES = 32
        const val CLEAR_TIMEOUT_MS = 10_000L
        val MESSAGE_ID = Regex("\"id\"\\s*:\\s*\"([A-Za-z0-9_-]{1,64})\"")
        val HOST = Regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$")

        fun bridgeScript(origin: String) = """
(function () {
  'use strict';
  if (window !== window.top || location.origin !== ${jsString(origin)}) return;
  if (Object.prototype.hasOwnProperty.call(window, 'AppChatBridge')) return;
  var native = window.$NATIVE_OBJECT;
  if (!native) return;
  var pending = Object.create(null);
  native.onmessage = function (event) {
    var reply;
    try { reply = JSON.parse(event.data); } catch (e) { return; }
    if (!reply || typeof reply.id !== 'string') return;
    var resolve = pending[reply.id];
    if (!resolve) return;
    delete pending[reply.id];
    resolve(reply);
  };
  function newId() {
    var bytes = crypto.getRandomValues(new Uint8Array(16)), id = '';
    for (var i = 0; i < bytes.length; i++) id += ('0' + bytes[i].toString(16)).slice(-2);
    return id;
  }
  var bridge = Object.create(null);
  bridge.request = function (method, params) {
    return new Promise(function (resolve) {
      var id = newId();
      pending[id] = resolve;
      try {
        native.postMessage(JSON.stringify(
          { v: 1, id: id, method: method, params: params === undefined ? {} : params }));
      } catch (e) {
        delete pending[id];
        resolve({ v: 1, id: id, ok: false, error: { code: 'bad_request', message: 'bad_request' } });
      }
    });
  };
  Object.defineProperty(window, 'AppChatBridge', { value: Object.freeze(bridge) });
})();
"""

        /** Theo dõi track mic của trang để app dừng được khi rời màn (Android không có hàm sẵn). */
        fun microphoneScript(origin: String) = """
(function () {
  'use strict';
  if (window !== window.top || location.origin !== ${jsString(origin)}) return;
  if (Object.prototype.hasOwnProperty.call(window, '__appChatStopCapture')) return;
  // Vá ở prototype: vá riêng đối tượng thì trang gọi thẳng hàm gốc của prototype là lách được.
  var proto = window.MediaDevices && MediaDevices.prototype;
  var tracks = new Set(), generation = 0;
  function watch(track) {
    tracks.add(track);
    track.addEventListener('ended', function () { tracks.delete(track); });
    return track;
  }
  function stop(track) { try { track.stop(); } catch (e) {} tracks.delete(track); }
  function stopped() { return new DOMException('Capture stopped', 'AbortError'); }
  // true: luồng còn hợp lệ; false: đã có lệnh dừng trong lúc chờ cấp quyền.
  function accept(stream, started) {
    stream.getTracks().forEach(watch);
    if (started === generation) return true;
    stream.getTracks().forEach(stop);
    return false;
  }
  if (proto && proto.getUserMedia) {
    var original = proto.getUserMedia;
    Object.defineProperty(proto, 'getUserMedia', { value: function (constraints) {
      var started = generation;
      return original.call(this, constraints).then(function (stream) {
        if (!accept(stream, started)) throw stopped();
        return stream;
      });
    } });
  }
  // Hàm kiểu cũ (gọi lại thay vì Promise).
  ['getUserMedia', 'webkitGetUserMedia'].forEach(function (name) {
    var legacy = Navigator.prototype[name];
    if (typeof legacy !== 'function') return;
    Object.defineProperty(Navigator.prototype, name, { value: function (constraints, ok, fail) {
      var started = generation;
      return legacy.call(this, constraints, function (stream) {
        if (accept(stream, started)) { if (ok) ok(stream); } else if (fail) { fail(stopped()); }
      }, fail);
    } });
  });
  var cloneTrack = MediaStreamTrack.prototype.clone;
  MediaStreamTrack.prototype.clone = function () {
    var copy = cloneTrack.call(this);
    return tracks.has(this) ? watch(copy) : copy;
  };
  var cloneStream = MediaStream.prototype.clone;
  MediaStream.prototype.clone = function () {
    var captured = this.getTracks().some(function (track) { return tracks.has(track); });
    var copy = cloneStream.call(this);
    if (captured) copy.getTracks().forEach(watch);
    return copy;
  };
  Object.defineProperty(window, '__appChatStopCapture', { value: function () {
    generation += 1;
    Array.from(tracks).forEach(stop);
  } });
})();
"""

        /** Chuỗi JS an toàn từ chuỗi bất kỳ. */
        fun jsString(value: String): String =
            JSONObject.quote(value).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")

        /** `https://host` (cổng 443, không phần khác) hoặc null. */
        fun canonicalOrigin(raw: String?): String? {
            val uri = raw?.let(Uri::parse) ?: return null
            val host = uri.host?.lowercase() ?: return null
            if (uri.scheme?.lowercase() != "https" || !HOST.matches(host)) return null
            if (uri.port != -1 && uri.port != 443) return null
            if (uri.userInfo != null || uri.query != null || uri.fragment != null) return null
            if (!uri.path.isNullOrEmpty() && uri.path != "/") return null
            return "https://$host"
        }

        fun errorReply(json: String?, code: String): String {
            // Chỉ dò mã yêu cầu ở đầu chuỗi: không đọc cả thân lớn chỉ để báo lỗi.
            val id = json?.take(512)?.let { MESSAGE_ID.find(it)?.groupValues?.get(1) } ?: ""
            return JSONObject()
                .put("v", 1)
                .put("id", id)
                .put("ok", false)
                .put("error", JSONObject().put("code", code).put("message", code))
                .toString()
        }
    }

    private class PendingReply(val proxy: JavaScriptReplyProxy, val requestHead: String)

    private class Attachment(val webViewId: Long, webView: WebView, val origin: String) {
        val webView = WeakReference(webView)
        var bridgeInstalled = false
        val scripts = mutableListOf<ScriptHandler>()
        val replies = LinkedHashMap<String, PendingReply>()
        var guard: IdeWebRenderGuardClient? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private val attachments = HashMap<Long, Attachment>()
    private var audio: AudioManager? = null
    private var captureActive = false
    private var captureAny = false

    private val recordingCallback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>?) {
            updateCapture(configs)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        methods = MethodChannel(binding.binaryMessenger, "webtui/ide_web_host").also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, "webtui/ide_web_host/events").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attachments.keys.toList().forEach(::detach)
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        sink = null
        this.binding = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val id = (args?.get("webViewId") as? Number)?.toLong()
        try {
            when (call.method) {
                "attach" -> attach(
                    id,
                    args?.get("allowedOrigin") as? String,
                    args?.get("bridgeEnabled") as? Boolean ?: false,
                    result
                )
                "detach" -> {
                    if (id != null) detach(id)
                    result.success(null)
                }
                "postReply" -> {
                    postReply(id, args?.get("replyId") as? String, args?.get("payload") as? String)
                    result.success(null)
                }
                "emit" -> emit(id, args?.get("payload") as? String, result)
                "captureState" ->
                    result.success(mapOf("active" to captureActive, "any" to captureAny))
                "stopCapture" -> {
                    attachments[id]?.let { stopCapture(it) }
                    result.success(null)
                }
                "clearAllData" -> clearAllData(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("failed", e.javaClass.simpleName, null)
        }
    }

    // ---- gắn / gỡ ----

    private fun attach(
        id: Long?,
        rawOrigin: String?,
        bridgeEnabled: Boolean,
        result: MethodChannel.Result
    ) {
        val origin = canonicalOrigin(rawOrigin)
        val webView = id?.let { webViewId ->
            binding?.let { WebViewFlutterAndroidExternalApi.getWebView(it, webViewId) }
        }
        if (id == null || origin == null || webView == null) {
            result.error("failed", "invalid web view or origin", null)
            return
        }
        detach(id)
        val attachment = Attachment(id, webView, origin)
        harden(webView)
        // Cần cả hai: kênh gửi có origin và script đầu tài liệu. Không lùi về addJavascriptInterface.
        val supported = WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        // Đưa vào bảng trước: bước dưới lỗi thì `detach` vẫn dọn được phần đã cài.
        attachments[id] = attachment
        try {
            if (supported) {
                attachment.scripts += WebViewCompat.addDocumentStartJavaScript(
                    webView,
                    microphoneScript(origin),
                    setOf(origin)
                )
                if (bridgeEnabled) installBridge(webView, attachment)
            }
            guardRenderer(webView, attachment)
            watchCapture()
        } catch (e: Exception) {
            detach(id)
            throw e
        }
        result.success(mapOf("supported" to supported))
    }

    private fun installBridge(webView: WebView, attachment: Attachment) {
        WebViewCompat.addWebMessageListener(
            webView,
            NATIVE_OBJECT,
            setOf(attachment.origin)
        ) { _, message, sourceOrigin, isMainFrame, replyProxy ->
            onPageMessage(attachment, message, sourceOrigin, isMainFrame, replyProxy)
        }
        attachment.bridgeInstalled = true
        attachment.scripts += WebViewCompat.addDocumentStartJavaScript(
            webView,
            bridgeScript(attachment.origin),
            setOf(attachment.origin)
        )
    }

    private fun harden(webView: WebView) {
        webView.settings.apply {
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setGeolocationEnabled(false)
            @Suppress("DEPRECATION")
            allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            allowUniversalAccessFromFileURLs = false
            // Gói mở WebView tạm cho `window.open` / `target=_blank`, không có chính sách điều hướng và
            // không có lớp canh tiến trình dựng trang: tắt để liên kết đó mở trong khung chính.
            setSupportMultipleWindows(false)
        }
        // Gói coi tải tệp là một lần điều hướng và tải lại đúng địa chỉ đó, lặp không dừng. Lưu tệp đi
        // qua cầu nối `file.save`.
        webView.setDownloadListener { _, _, _, _, _ -> }
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        // Thanh trên của app đã chừa thanh trạng thái, nhưng WebView (Chromium 136+) vẫn chuyển inset hệ
        // thống vào `env(safe-area-inset-*)` nên trang IDE chừa thêm một dải trống ở đầu. Nuốt inset để
        // trang nhận 0; bàn phím vẫn đẩy nội dung lên vì Scaffold phía Flutter tự thu nhỏ khung.
        webView.setOnApplyWindowInsetsListener { _, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsets.CONSUMED
            } else {
                @Suppress("DEPRECATION")
                insets.consumeSystemWindowInsets()
            }
        }
        webView.requestApplyInsets()
        val flags = webView.context.applicationInfo.flags
        WebView.setWebContentsDebuggingEnabled(flags and ApplicationInfo.FLAG_DEBUGGABLE != 0)
    }

    /** Tiến trình dựng trang chết mà không ai nhận thì Android đóng cả app: nhận và báo Dart. */
    private fun guardRenderer(webView: WebView, attachment: Attachment) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val current = webView.webViewClient
        val guard = current as? IdeWebRenderGuardClient ?: IdeWebRenderGuardClient(current)
        guard.onGone = {
            if (attachments[attachment.webViewId] === attachment) {
                detach(attachment.webViewId)
                sink?.success(mapOf("type" to "render_gone"))
            }
        }
        attachment.guard = guard
        if (guard !== current) webView.webViewClient = guard
    }

    private fun detach(id: Long) {
        val attachment = attachments.remove(id) ?: return
        // Lớp canh vẫn ở lại (gỡ ra thì tiến trình chết sẽ kéo theo app), nhưng không giữ tham chiếu.
        attachment.guard?.onGone = null
        attachment.scripts.forEach {
            try {
                it.remove()
            } catch (_: Exception) {
                // WebView đã bị huỷ.
            }
        }
        attachment.scripts.clear()
        failPending(attachment)
        val webView = attachment.webView.get()
        if (webView != null && attachment.bridgeInstalled) {
            try {
                WebViewCompat.removeWebMessageListener(webView, NATIVE_OBJECT)
            } catch (_: Exception) {
                // WebView đã bị huỷ.
            }
        }
        if (attachments.isEmpty()) unwatchCapture()
    }

    // ---- tin từ trang ----

    private fun onPageMessage(
        attachment: Attachment,
        message: WebMessageCompat,
        sourceOrigin: Uri,
        isMainFrame: Boolean,
        replyProxy: JavaScriptReplyProxy
    ) {
        val json = if (message.type == WebMessageCompat.TYPE_STRING) message.data else null
        val origin = canonicalOrigin(sourceOrigin.toString())
        val reject = when {
            attachments[attachment.webViewId] !== attachment -> "failed"
            !isMainFrame || origin != attachment.origin -> "forbidden_origin"
            json == null -> "bad_request"
            json.length > MAX_MESSAGE_CHARS -> "too_large"
            sink == null -> "failed"
            else -> null
        }
        if (reject != null || json == null) {
            post(replyProxy, errorReply(json, reject ?: "bad_request"))
            return
        }
        // Trả lời bị bỏ (trang đã đổi) không được chiếm chỗ mãi: đầy thì huỷ lượt cũ nhất.
        while (attachment.replies.size >= MAX_PENDING_REPLIES) {
            val oldest = attachment.replies.remove(attachment.replies.keys.first()) ?: break
            post(oldest.proxy, errorReply(oldest.requestHead, "busy"))
        }
        val replyId = UUID.randomUUID().toString()
        attachment.replies[replyId] = PendingReply(replyProxy, json.take(512))
        sink?.success(
            mapOf(
                "type" to "message",
                "webViewId" to attachment.webViewId,
                "id" to replyId,
                "json" to json,
                "isMainFrame" to true,
                "origin" to attachment.origin
            )
        )
    }

    private fun postReply(id: Long?, replyId: String?, payload: String?) {
        if (payload == null) return
        val pending = attachments[id]?.replies?.remove(replyId) ?: return
        post(pending.proxy, payload)
    }

    private fun failPending(attachment: Attachment) {
        attachment.replies.values.forEach { post(it.proxy, errorReply(it.requestHead, "cancelled")) }
        attachment.replies.clear()
    }

    private fun post(proxy: JavaScriptReplyProxy, payload: String) {
        try {
            proxy.postMessage(payload)
        } catch (_: Exception) {
            // Khung gửi không còn.
        }
    }

    private fun emit(id: Long?, payload: String?, result: MethodChannel.Result) {
        val attachment = attachments[id]
        val webView = attachment?.webView?.get()
        if (payload == null) {
            result.error("failed", "payload required", null)
            return
        }
        try {
            JSONObject(payload)
        } catch (_: JSONException) {
            result.error("failed", "payload is not JSON", null)
            return
        }
        if (webView != null && attachment.bridgeInstalled) {
            webView.evaluateJavascript(
                "if (location.origin === ${jsString(attachment.origin)}) " +
                    "window.dispatchEvent(new CustomEvent('appchat:event', " +
                    "{ detail: JSON.parse(${jsString(payload)}) }));",
                null
            )
        }
        result.success(null)
    }

    // ---- mic ----

    private fun watchCapture() {
        if (audio != null) return
        val manager = binding?.applicationContext
            ?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audio = manager
        manager.registerAudioRecordingCallback(recordingCallback, main)
        updateCapture(manager.activeRecordingConfigurations)
    }

    private fun unwatchCapture() {
        audio?.unregisterAudioRecordingCallback(recordingCallback)
        audio = null
        updateCapture(null)
    }

    private fun updateCapture(configs: List<AudioRecordingConfiguration>?) {
        // Callback đã xếp hàng trước lúc gỡ thì bỏ qua (audio == null).
        val open = if (audio == null) emptyList() else configs.orEmpty()
        val active = open.any {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !it.isClientSilenced
        }
        // `any`: luồng thu còn mở kể cả lúc hệ điều hành đang bịt tiếng (app ở nền).
        val any = open.isNotEmpty()
        if (active == captureActive && any == captureAny) return
        captureActive = active
        captureAny = any
        sink?.success(mapOf("type" to "capture", "active" to active, "any" to any))
    }

    private fun stopCapture(attachment: Attachment) {
        attachment.webView.get()?.evaluateJavascript(
            "if (typeof window.__appChatStopCapture === 'function') window.__appChatStopCapture();",
            null
        )
    }

    // ---- xoá dữ liệu ----

    private fun clearAllData(result: MethodChannel.Result) {
        val context = binding?.applicationContext
        if (context == null) {
            result.error("failed", "engine detached", null)
            return
        }
        var completed = false
        val timeout = Runnable {
            if (!completed) {
                completed = true
                result.error("failed", "timeout", null)
            }
        }
        val finish = {
            main.post {
                if (!completed) {
                    completed = true
                    main.removeCallbacks(timeout)
                    result.success(null)
                }
            }
            Unit
        }
        main.postDelayed(timeout, CLEAR_TIMEOUT_MS)
        try {
            val cookies = CookieManager.getInstance()
            val storage = WebStorage.getInstance()
            @Suppress("DEPRECATION")
            WebViewDatabase.getInstance(context).apply {
                clearHttpAuthUsernamePassword()
                clearFormData()
            }
            val clearCookies = {
                cookies.removeAllCookies {
                    cookies.flush()
                    finish()
                }
            }
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
                // Cookie, bộ nhớ (kể cả IndexedDB, service worker, Cache Storage) và cache mạng.
                WebStorageCompat.deleteBrowsingData(storage) { clearCookies() }
            } else {
                storage.deleteAllData()
                // clearCache tác động tới mọi WebView của app; chưa có thì tạo một cái tạm.
                val attached = attachments.values.firstNotNullOfOrNull { it.webView.get() }
                val webView = attached ?: WebView(context)
                webView.clearCache(true)
                if (attached == null) webView.destroy()
                clearCookies()
            }
        } catch (e: Exception) {
            // Không có WebView trên máy, hoặc đang nâng cấp.
            if (!completed) {
                completed = true
                main.removeCallbacks(timeout)
                result.error("failed", e.javaClass.simpleName, null)
            }
        }
    }
}
