import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ide_web_bridge_protocol.dart';
import '../domain/ide_web_failure.dart';
import '../domain/ide_web_launch.dart';
import 'ide_web_bridge_dispatcher.dart';
import 'ide_web_mic_guard.dart';
import 'ide_web_prompter.dart';
import 'ide_web_rate_limiter.dart';
import 'ide_web_view.dart';

/// Một phiên màn IDE đang mở: nối WebView với cầu nối và bộ canh micro.
final class IdeWebViewSession {
  IdeWebViewSession({
    required this.view,
    required this.mic,
    required IdeWebBridgeDispatcher dispatcher,
    required IdeWebPrompter prompter,
    required IdeWebRateLimiter limiter,
    required Future<void> Function() disposeFiles,
    required Future<bool> Function(Uri uri) openExternal,
    required void Function(IdeWebFailureKind kind) onFailed,
    required IdeWebScreenStatus Function() status,
  }) : _dispatcher = dispatcher,
       _prompter = prompter,
       _limiter = limiter,
       _disposeFiles = disposeFiles,
       _openExternal = openExternal,
       _onFailed = onFailed,
       _status = status;

  final IdeWebView view;
  final IdeWebMicGuard mic;
  final IdeWebBridgeDispatcher _dispatcher;
  final IdeWebPrompter _prompter;
  final IdeWebRateLimiter _limiter;
  final Future<void> Function() _disposeFiles;
  final Future<bool> Function(Uri uri) _openExternal;
  final void Function(IdeWebFailureKind kind) _onFailed;
  final IdeWebScreenStatus Function() _status;

  StreamSubscription<IdeWebViewEvent>? _events;
  bool _askingExternal = false;
  bool _background = false;
  bool _bridge = false;
  Future<void>? _closing;

  ValueListenable<bool> get capturing => mic.capturing;

  bool get isClosed => _closing != null;

  /// Gắn lớp native rồi mới tải. `false` = thiếu cầu nối an toàn mà máy chủ bật.
  Future<bool> start(IdeWebEntry entry) async {
    _events = view.events.listen(_onEvent);
    final supported = await view.attach(bridgeEnabled: entry.bridgeEnabled);
    if (entry.bridgeEnabled && !supported) return false;
    if (isClosed) return true;
    _bridge = entry.bridgeEnabled;
    await view.open(entry);
    return true;
  }

  void _onEvent(IdeWebViewEvent event) {
    if (isClosed) {
      if (event is IdeWebPermissionAsked) {
        unawaited(event.resolve(granted: false));
      }
      return;
    }
    switch (event) {
      case IdeWebPageStarted():
        _dispatcher.onNavigation();
      case IdeWebPageFailed(:final kind):
        _onFailed(kind);
      case IdeWebRenderGone():
        _onFailed(IdeWebFailureKind.expired);
      case IdeWebCaptureChanged(:final active, :final any):
        mic.onCaptureChanged(active: active, any: any);
      case IdeWebBridgeMessage():
        unawaited(_onMessage(event));
      case IdeWebExternalLink(:final uri):
        unawaited(_onExternal(uri));
      case IdeWebPermissionAsked():
        unawaited(_onPermission(event));
    }
  }

  Future<void> _onMessage(IdeWebBridgeMessage message) async {
    final reply = !_bridge
        ? encodeBridgeError(
            peekBridgeRequestId(message.json),
            BridgeErrorCode.unsupported,
            '',
          )
        : await _dispatcher.handle(
            raw: message.json,
            isMainFrame: message.isMainFrame,
            messageOrigin: message.origin,
          );
    // Đã đóng: `detach` của lớp native trả `cancelled` cho mọi lượt còn chờ.
    if (isClosed) return;
    try {
      await view.reply(message.replyId, reply);
    } on Object {
      // Trang đã đi nơi khác.
    }
  }

  Future<void> _onExternal(Uri uri) async {
    // Lớp native không báo được cử chỉ người dùng: luôn hỏi, một hộp một lúc,
    // có hạn để trang không giữ người dùng trong chuỗi hộp hỏi.
    if (_askingExternal || !_status().active || !ideWebAllowPrompt(_limiter)) {
      return;
    }
    _askingExternal = true;
    try {
      if (await _prompter.confirm(IdeWebExternalLinkPrompt(uri)) && !isClosed) {
        await _openExternal(uri);
      }
    } finally {
      _askingExternal = false;
    }
  }

  Future<void> _onPermission(IdeWebPermissionAsked event) async {
    final granted = await mic.decide(
      microphoneOnly: event.microphoneOnly,
      mainUrl: event.mainUrl,
    );
    try {
      await event.resolve(granted: granted && !isClosed);
    } on Object {
      // Trang đã bỏ yêu cầu.
    }
  }

  /// Gọi khi màn / app / khoá / cuộc gọi đổi trạng thái.
  Future<void> onStatusChanged() async {
    if (isClosed) return;
    final status = _status();
    if (!status.micAllowed) unawaited(mic.stop());
    if (status.locked || !status.resumed) _prompter.dismiss();
    if (status.inCall) {
      try {
        await view.pauseMedia();
      } on Object {
        // Trang chưa sẵn sàng.
      }
    }
    if (status.micAllowed) {
      try {
        await mic.resume();
      } on Object {
        _onFailed(IdeWebFailureKind.expired);
      }
    }
  }

  Future<void> onAppBackground() async {
    if (_background) return;
    _background = true;
    await _emit(BridgeEvent.background);
  }

  Future<void> onAppForeground() async {
    if (!_background) return;
    _background = false;
    await _emit(BridgeEvent.foreground);
  }

  Future<void> _emit(BridgeEvent event) async {
    if (!_bridge) return;
    try {
      await view.emit(encodeBridgeEvent(event));
    } on Object {
      // Trang chưa sẵn sàng.
    }
  }

  /// Đóng màn: chỉ ngắt người xem, không kết thúc phiên IDE ở máy chủ.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _dispatcher.close();
    _prompter.dismiss();
    await _emit(BridgeEvent.closing);
    try {
      await mic.stop().timeout(const Duration(seconds: 2));
    } on Object {
      // Huỷ WebView bên dưới cũng dừng micro.
    }
    mic.dispose();
    unawaited(_events?.cancel());
    try {
      await view.dispose();
    } on Object {
      // WebView đã hỏng.
    }
    try {
      await _disposeFiles();
    } on Object {
      // Hệ điều hành tự dọn thư mục tạm.
    }
  }
}
