import 'package:flutter/widgets.dart';

import '../domain/ide_web_failure.dart';
import '../domain/ide_web_host_policy.dart';
import '../domain/ide_web_launch.dart';

sealed class IdeWebViewEvent {
  const IdeWebViewEvent();
}

/// Khung chính bắt đầu tải trang mới (mọi yêu cầu cầu nối cũ hết hiệu lực).
final class IdeWebPageStarted extends IdeWebViewEvent {
  const IdeWebPageStarted();
}

/// Khung chính báo lỗi (HTTP, mạng, chứng chỉ, ra ngoài địa chỉ cho phép).
final class IdeWebPageFailed extends IdeWebViewEvent {
  const IdeWebPageFailed(this.kind);

  final IdeWebFailureKind kind;
}

/// Tiến trình WebView chết.
final class IdeWebRenderGone extends IdeWebViewEvent {
  const IdeWebRenderGone();
}

/// Lớp native báo trạng thái thu micro.
final class IdeWebCaptureChanged extends IdeWebViewEvent {
  const IdeWebCaptureChanged({required this.active, required this.any});

  /// Đang thu thật (có tiếng).
  final bool active;

  /// Còn luồng thu nào mở, kể cả lúc hệ điều hành đang bịt tiếng.
  final bool any;
}

final class IdeWebBridgeMessage extends IdeWebViewEvent {
  const IdeWebBridgeMessage({
    required this.replyId,
    required this.json,
    required this.isMainFrame,
    required this.origin,
  });

  final String replyId;
  final String json;
  final bool isMainFrame;
  final String origin;

  @override
  String toString() => 'IdeWebBridgeMessage(<redacted>)';
}

/// Trang muốn mở địa chỉ https khác: hỏi rồi mở ngoài app.
final class IdeWebExternalLink extends IdeWebViewEvent {
  const IdeWebExternalLink(this.uri);

  final Uri uri;
}

/// Trang chuyển tới trang đăng nhập / nâng quyền trên tên miền IDE: mở bằng
/// trình duyệt hệ thống, không hỏi. Địa chỉ mang `flow` dùng một lần.
final class IdeWebAuthLink extends IdeWebViewEvent {
  const IdeWebAuthLink(this.uri);

  final Uri uri;

  @override
  String toString() => 'IdeWebAuthLink(<redacted>)';
}

/// Liên kết tải tệp bằng vé của IDE: mở bằng trình duyệt hệ thống, không hỏi.
final class IdeWebDownloadLink extends IdeWebViewEvent {
  const IdeWebDownloadLink(this.uri);

  final Uri uri;

  @override
  String toString() => 'IdeWebDownloadLink(<redacted>)';
}

/// Trang xin quyền thiết bị; phải gọi [resolve] đúng một lần.
final class IdeWebPermissionAsked extends IdeWebViewEvent {
  const IdeWebPermissionAsked({
    required this.microphoneOnly,
    required this.mainUrl,
    required this.resolve,
  });

  /// Chỉ xin micro (camera hay thứ khác thì từ chối).
  final bool microphoneOnly;

  /// Địa chỉ khung chính lúc xin.
  final String? mainUrl;
  final Future<void> Function({required bool granted}) resolve;
}

/// WebView của VPSTTT IDE. Nơi duy nhất cài đặt là data layer.
abstract interface class IdeWebView {
  Widget build();

  Stream<IdeWebViewEvent> get events;

  /// Gắn lớp native TRƯỚC lần tải đầu. `false` = máy thiếu cầu nối an toàn.
  Future<bool> attach({required bool bridgeEnabled});

  /// Mở bằng POST thân form; mã không nằm trong URL.
  Future<void> open(IdeWebEntry entry);

  /// Tải lại trang chính của IDE bằng phiên đang có (sau khi phải tải trống).
  Future<void> reloadHome();

  Future<void> loadBlank();

  Future<void> reply(String replyId, String payload);

  Future<void> emit(String payload);

  /// Còn luồng thu nào mở, kể cả lúc hệ điều hành đang bịt tiếng.
  Future<bool> captureOpen();

  Future<void> stopCapture();

  /// Tạm dừng mọi âm thanh / video trong trang.
  Future<void> pauseMedia();

  /// Lùi một trang trong IDE; `false` khi đang ở trang đầu.
  Future<bool> goBack();

  Future<void> dispose();
}

typedef IdeWebViewFactory = IdeWebView Function(IdeWebHostPolicy policy);
