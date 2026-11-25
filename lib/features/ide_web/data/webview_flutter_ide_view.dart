import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../application/ide_web_view.dart';
import '../domain/ide_web_failure.dart';
import '../domain/ide_web_host_policy.dart';
import '../domain/ide_web_launch.dart';
import 'method_channel_ide_web_host.dart';

/// Thân form mở WebView (mã nằm trong thân, không trong URL).
Uint8List ideWebEnterBody(IdeWebEntry entry) => utf8.encode(
  Uri(
    queryParameters: {
      'gate_token': entry.gateToken,
      'open_code': entry.openCode,
    },
  ).query,
);

/// WebView thật. Nơi DUY NHẤT của app import `webview_flutter*`.
final class WebViewFlutterIdeView implements IdeWebView {
  WebViewFlutterIdeView(
    this._policy, {
    MethodChannelIdeWebHost host = const MethodChannelIdeWebHost(),
  }) : _host = host {
    _controller = WebViewController.fromPlatformCreationParams(
      _creationParams(),
      onPermissionRequest: _onPermission,
    );
  }

  final IdeWebHostPolicy _policy;
  final MethodChannelIdeWebHost _host;
  late final WebViewController _controller;
  final _events = StreamController<IdeWebViewEvent>.broadcast();
  StreamSubscription<IdeWebViewEvent>? _hostEvents;
  late final int _id = _webViewId();
  late final Widget _widget = WebViewWidget(controller: _controller);
  bool _disposed = false;

  /// Đang cố ý ở trang trống.
  bool _blank = false;

  /// Trang chính đang tải / đang hiện, để nhận đúng lỗi HTTP của khung chính.
  String? _mainUrl;
  String? _landingUrl;
  final _requestedUrls = <String>{};
  ({String url, int status})? _earlyHttpError;

  static PlatformWebViewControllerCreationParams _creationParams() {
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      return WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    return const PlatformWebViewControllerCreationParams();
  }

  int _webViewId() => switch (_controller.platform) {
    final AndroidWebViewController c => c.webViewIdentifier,
    final WebKitWebViewController c => c.webViewIdentifier,
    _ => throw UnsupportedError('WebView'),
  };

  void _add(IdeWebViewEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  @override
  Widget build() => _widget;

  @override
  Stream<IdeWebViewEvent> get events => _events.stream;

  @override
  Future<bool> attach({required bool bridgeEnabled}) async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: _onPageStarted,
        onUrlChange: (change) {
          final url = change.url;
          if (url == null || !_policy.isInternalText(url)) return;
          _mainUrl = url;
          _rememberLanding(url);
        },
        onHttpError: _onHttpError,
        onWebResourceError: _onResourceError,
        onSslAuthError: (error) {
          // Lỗi chứng chỉ không bao giờ cho qua.
          unawaited(error.cancel());
          _add(const IdeWebPageFailed(IdeWebFailureKind.unavailable));
        },
      ),
    );
    if (_controller.platform case final AndroidWebViewController android) {
      await android.setAllowFileAccess(false);
      await android.setAllowContentAccess(false);
      await android.setGeolocationEnabled(false);
      await android.setMixedContentMode(MixedContentMode.neverAllow);
      await android.setMediaPlaybackRequiresUserGesture(false);
      await android.setOnShowFileSelector(_pickFiles);
    }
    if (_controller.platform case final WebKitWebViewController webKit) {
      await webKit.setInspectable(kDebugMode);
    }
    // Nghe trước khi gắn và tải; không đặt lại delegate sau `attach`.
    _hostEvents = _host.events(_id).listen(_add, onError: (Object _) {});
    return _host.attach(
      webViewId: _id,
      allowedOrigin: _policy.origin,
      bridgeEnabled: bridgeEnabled,
    );
  }

  @override
  Future<void> open(IdeWebEntry entry) {
    _blank = false;
    return _controller.loadRequest(
      entry.enterUrl,
      method: LoadRequestMethod.post,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: ideWebEnterBody(entry),
    );
  }

  @override
  Future<void> reloadHome() {
    _blank = false;
    return _controller.loadRequest(_policy.homeUri);
  }

  @override
  Future<void> loadBlank() {
    _blank = true;
    return _controller.loadRequest(Uri.parse('about:blank'));
  }

  @override
  Future<void> reply(String replyId, String payload) =>
      _host.postReply(webViewId: _id, replyId: replyId, payload: payload);

  @override
  Future<void> emit(String payload) =>
      _host.emit(webViewId: _id, payload: payload);

  @override
  Future<bool> captureActive() => _host.captureActive();

  @override
  Future<void> stopCapture() => _host.stopCapture(_id);

  @override
  Future<void> pauseMedia() => _controller.runJavaScript(
    "document.querySelectorAll('audio,video').forEach(function(m){m.pause();});",
  );

  @override
  Future<bool> goBack() async {
    final url = await _controller.currentUrl();
    // Trước trang đầu chỉ còn trang chuyển mã: không lùi vào đó.
    if (_landingUrl == null ||
        url == null ||
        url == _landingUrl ||
        !await _controller.canGoBack()) {
      return false;
    }
    await _controller.goBack();
    return true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _blank = true;
    await _hostEvents?.cancel();
    await _events.close();
    try {
      await _host.detach(_id);
    } on Object {
      // Vẫn tải trang trống để trang cũ ngừng chạy.
    }
    await _controller.loadRequest(Uri.parse('about:blank'));
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    final kind = _policy.classifyText(request.url);
    if (kind == IdeWebUrlClass.internal) {
      if (request.isMainFrame) _rememberRequest(request.url);
      return NavigationDecision.navigate;
    }
    if (request.isMainFrame) {
      if (_blank && request.url == 'about:blank') {
        return NavigationDecision.navigate;
      }
      if (kind == IdeWebUrlClass.external) {
        _add(IdeWebExternalLink(Uri.parse(request.url)));
      }
    }
    // Khung phụ ra ngoài địa chỉ IDE luôn bị chặn (Android: gói không báo
    // khung phụ; máy chủ gửi CSP `frame-src 'none'`).
    return NavigationDecision.prevent;
  }

  void _rememberRequest(String url) {
    if (_requestedUrls.length > 16) _requestedUrls.clear();
    _requestedUrls.add(url);
  }

  void _rememberLanding(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    if (_landingUrl == null &&
        path.startsWith('/appchat/') &&
        path != '/appchat/open') {
      _landingUrl = url;
    }
  }

  void _onPageStarted(String url) {
    if (url == 'about:blank') {
      _add(const IdeWebPageStarted());
      if (!_blank) unawaited(_fail(IdeWebFailureKind.unavailable));
      return;
    }
    _mainUrl = url;
    // Android không hỏi trước khi điều hướng bằng POST: kiểm lại ở đây.
    if (!_policy.isInternalText(url)) {
      _add(const IdeWebPageStarted());
      unawaited(_fail(IdeWebFailureKind.unavailable));
      return;
    }
    _blank = false;
    _rememberLanding(url);
    _requestedUrls.clear();
    _add(const IdeWebPageStarted());
    final early = _earlyHttpError;
    _earlyHttpError = null;
    if (early != null && early.url == url) _reportHttp(early.status);
  }

  Future<void> _fail(IdeWebFailureKind kind) async {
    await loadBlank();
    _add(IdeWebPageFailed(kind));
  }

  void _onHttpError(HttpResponseError error) {
    final status = error.response?.statusCode ?? 0;
    final url = error.request?.uri.toString();
    // iOS chỉ báo lỗi của điều hướng và không kèm địa chỉ; Android báo cả tài
    // nguyên con nên phải đúng địa chỉ khung chính.
    if (url == null || url == _mainUrl || _requestedUrls.contains(url)) {
      _reportHttp(status);
    } else if (_policy.isInternalText(url)) {
      _earlyHttpError = (url: url, status: status);
    }
  }

  void _reportHttp(int status) {
    // Gói không đưa header `X-AppChat-Gate` ra Dart: chỉ xét mã HTTP.
    final kind = ideWebFailureKindOfGate(status, null);
    if (kind != null) _add(IdeWebPageFailed(kind));
  }

  void _onResourceError(WebResourceError error) {
    if (error.errorType == WebResourceErrorType.webContentProcessTerminated) {
      _add(const IdeWebRenderGone());
      return;
    }
    // -999: điều hướng bị thay; 102: app chặn điều hướng (iOS).
    if (error.isForMainFrame != true ||
        _blank ||
        error.errorCode == -999 ||
        error.errorCode == 102) {
      return;
    }
    _add(const IdeWebPageFailed(IdeWebFailureKind.unavailable));
  }

  Future<void> _onPermission(WebViewPermissionRequest request) async {
    if (_disposed || !_events.hasListener) {
      await request.deny();
      return;
    }
    final url = await _controller.currentUrl();
    if (_disposed || !_events.hasListener) {
      await request.deny();
      return;
    }
    _add(
      IdeWebPermissionAsked(
        microphoneOnly:
            request.types.length == 1 &&
            request.types.first == WebViewPermissionResourceType.microphone,
        mainUrl: url,
        resolve: ({required granted}) =>
            granted ? request.grant() : request.deny(),
      ),
    );
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    final url = await _controller.currentUrl();
    if (_disposed || !_policy.isInternalText(url)) return const [];
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
      );
      return [
        for (final file in result?.files ?? const <PlatformFile>[])
          if (file.path case final path?) Uri.file(path).toString(),
      ];
    } on Object {
      return const [];
    }
  }
}
