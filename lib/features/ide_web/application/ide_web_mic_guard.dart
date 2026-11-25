import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ide_web_host_policy.dart';
import '../domain/ide_web_ports.dart';
import 'ide_web_prompter.dart';
import 'ide_web_rate_limiter.dart';
import 'ide_web_view.dart';

/// Điều kiện hiện thời của màn IDE.
final class IdeWebScreenStatus {
  const IdeWebScreenStatus({
    required this.visible,
    required this.resumed,
    required this.locked,
    required this.inCall,
  });

  final bool visible;
  final bool resumed;
  final bool locked;
  final bool inCall;

  bool get active => visible && resumed && !locked;
  bool get micAllowed => active && !inCall;
}

/// Cấp / dừng micro cho trang IDE: chỉ micro, đúng địa chỉ, màn đang hiện, app ở
/// trước, không khoá, không có cuộc gọi, người dùng đã đồng ý (một lần mỗi phiên
/// màn) và hệ điều hành cho phép.
final class IdeWebMicGuard {
  IdeWebMicGuard({
    required IdeWebView view,
    required IdeWebHostPolicy policy,
    required IdeWebPrompter prompter,
    required IdeWebMicPermission permission,
    required IdeWebRateLimiter limiter,
    required IdeWebScreenStatus Function() status,
    this.stopGrace = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _view = view,
       _policy = policy,
       _prompter = prompter,
       _permission = permission,
       _limiter = limiter,
       _status = status,
       _clock = clock ?? DateTime.now;

  final IdeWebView _view;
  final IdeWebHostPolicy _policy;
  final IdeWebPrompter _prompter;
  final IdeWebMicPermission _permission;
  final IdeWebRateLimiter _limiter;
  final IdeWebScreenStatus Function() _status;

  /// Vừa cấp trong khoảng này thì lượt thu mới được coi là của trang.
  static const recentGrant = Duration(seconds: 5);

  /// Chờ trang dừng thu trước khi tải trang trống.
  final Duration stopGrace;

  final _capturing = ValueNotifier<bool>(false);
  bool _agreed = false;
  bool _asking = false;
  final DateTime Function() _clock;
  DateTime? _grantedAt;

  /// Trang đã mở luồng thu mà chưa thấy máy báo hết (kể cả lúc bị bịt tiếng).
  bool _holding = false;
  bool _blanked = false;
  bool _disposed = false;
  Future<void>? _stopping;

  /// Chỉ báo "Đang thu" trên thanh tiêu đề.
  ValueListenable<bool> get capturing => _capturing;

  /// Đã phải tải trang trống để chắc chắn dừng micro.
  bool get blanked => _blanked;

  Future<bool> decide({
    required bool microphoneOnly,
    required String? mainUrl,
  }) async {
    bool allowed() => !_disposed && _status().micAllowed;
    if (!microphoneOnly ||
        !_policy.isInternalText(mainUrl) ||
        !allowed() ||
        _asking) {
      return false;
    }
    _asking = true;
    try {
      if (!_agreed) {
        if (!ideWebAllowPrompt(_limiter) ||
            !await _prompter.confirm(const IdeWebMicrophonePrompt())) {
          return false;
        }
        _agreed = true;
      }
      if (!await _permission.request()) return false;
      // Hộp hỏi có thể kéo dài: kiểm lại mọi điều kiện.
      if (!allowed()) return false;
      _grantedAt = _clock();
      return true;
    } on Object {
      return false;
    } finally {
      _asking = false;
    }
  }

  void onCaptureChanged({required bool active, required bool any}) {
    if (_disposed) return;
    if (!any || _grantedAt == null) {
      _holding = false;
      _capturing.value = false;
      return;
    }
    if (_status().micAllowed) {
      if (active) _holding = true;
      _capturing.value = active && _holding;
      return;
    }
    // Android báo mọi nơi thu của hệ thống. Lúc không được phép, trang không xin
    // được micro mới: luồng thu là của trang khi trang còn giữ hoặc vừa được cấp,
    // còn lại là cuộc gọi / tin thoại.
    if (_holding || _clock().difference(_grantedAt!) < recentGrant) {
      _holding = true;
      _capturing.value = active;
      unawaited(stop());
    } else {
      unawaited(_stopQuietly());
    }
  }

  Future<void> _stopQuietly() async {
    try {
      await _view.stopCapture();
    } on Object {
      // Bên gọi kiểm lại bằng trạng thái thật.
    }
  }

  /// Dừng thu. Trang không chịu dừng sau [stopGrace] thì tải trang trống.
  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);

  Future<void> _stop() async {
    if (_grantedAt == null) return;
    final held = _holding;
    await _stopQuietly();
    if (!held) return;
    await Future<void>.delayed(stopGrace);
    // Đã báo hết, hoặc đã quay lại màn và được thu tiếp.
    if (_disposed || !_holding || _status().micAllowed) return;
    var open = true;
    try {
      open = await _view.captureOpen();
    } on Object {
      // Không đọc được: coi như còn thu.
    }
    if (_disposed || _status().micAllowed) return;
    if (open) {
      _blanked = true;
      _grantedAt = null;
      try {
        await _view.loadBlank();
      } on Object {
        // WebView đã hỏng: controller nhận sự kiện render_gone.
      }
    }
    if (_disposed) return;
    _holding = false;
    _capturing.value = false;
    // Quay lại đúng lúc đang tải trang trống: `onStatusChanged` đã chạy trước đó.
    if (_status().micAllowed) {
      try {
        await resume();
      } on Object {
        // Trang báo lỗi tải qua sự kiện của WebView.
      }
    }
  }

  /// Quay lại màn sau khi đã tải trang trống: mở lại trang chính.
  Future<void> resume() async {
    if (_disposed || !_blanked || !_status().micAllowed) return;
    _blanked = false;
    await _view.reloadHome();
  }

  void dispose() {
    _disposed = true;
    _capturing.dispose();
  }
}
