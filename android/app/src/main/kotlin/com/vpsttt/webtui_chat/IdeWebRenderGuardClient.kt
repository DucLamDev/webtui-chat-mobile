package com.vpsttt.webtui_chat

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Message
import android.view.KeyEvent
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.RequiresApi

/**
 * Chuyển nguyên mọi lời gọi cho WebViewClient của webview_flutter, chỉ nhận thêm việc tiến trình
 * dựng trang chết (gói không xử lý, mặc định Android đóng cả app).
 */
@Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
class IdeWebRenderGuardClient(private val inner: WebViewClient) : WebViewClient() {
    var onGone: (() -> Unit)? = null

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        onGone?.invoke()
        return true
    }

    override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
        inner.shouldOverrideUrlLoading(view, url)

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
        inner.shouldOverrideUrlLoading(view, request)

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) =
        inner.onPageStarted(view, url, favicon)

    override fun onPageFinished(view: WebView, url: String) = inner.onPageFinished(view, url)

    override fun onLoadResource(view: WebView, url: String) = inner.onLoadResource(view, url)

    override fun onPageCommitVisible(view: WebView, url: String) =
        inner.onPageCommitVisible(view, url)

    override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? =
        inner.shouldInterceptRequest(view, url)

    override fun shouldInterceptRequest(
        view: WebView,
        request: WebResourceRequest
    ): WebResourceResponse? = inner.shouldInterceptRequest(view, request)

    override fun onTooManyRedirects(view: WebView, cancelMsg: Message, continueMsg: Message) =
        inner.onTooManyRedirects(view, cancelMsg, continueMsg)

    override fun onReceivedError(
        view: WebView,
        errorCode: Int,
        description: String?,
        failingUrl: String?
    ) = inner.onReceivedError(view, errorCode, description, failingUrl)

    override fun onReceivedError(
        view: WebView,
        request: WebResourceRequest,
        error: WebResourceError
    ) = inner.onReceivedError(view, request, error)

    override fun onReceivedHttpError(
        view: WebView,
        request: WebResourceRequest,
        errorResponse: WebResourceResponse
    ) = inner.onReceivedHttpError(view, request, errorResponse)

    override fun onFormResubmission(view: WebView, dontResend: Message, resend: Message) =
        inner.onFormResubmission(view, dontResend, resend)

    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) =
        inner.doUpdateVisitedHistory(view, url, isReload)

    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) =
        inner.onReceivedSslError(view, handler, error)

    override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) =
        inner.onReceivedClientCertRequest(view, request)

    override fun onReceivedHttpAuthRequest(
        view: WebView,
        handler: HttpAuthHandler,
        host: String,
        realm: String
    ) = inner.onReceivedHttpAuthRequest(view, handler, host, realm)

    override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent): Boolean =
        inner.shouldOverrideKeyEvent(view, event)

    override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) =
        inner.onUnhandledKeyEvent(view, event)

    override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) =
        inner.onScaleChanged(view, oldScale, newScale)

    override fun onReceivedLoginRequest(
        view: WebView,
        realm: String,
        account: String?,
        args: String
    ) = inner.onReceivedLoginRequest(view, realm, account, args)

    @RequiresApi(Build.VERSION_CODES.O_MR1)
    override fun onSafeBrowsingHit(
        view: WebView,
        request: WebResourceRequest,
        threatType: Int,
        callback: SafeBrowsingResponse
    ) = inner.onSafeBrowsingHit(view, request, threatType, callback)
}
