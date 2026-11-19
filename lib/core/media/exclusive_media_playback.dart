import 'dart:async';

import 'package:flutter/foundation.dart';

/// Chỉ một nguồn phát có tiếng (tin thoại, video trong tin nhắn) tại một thời
/// điểm, như Zalo / Messenger: bắt đầu phát cái mới thì cái đang phát tự tạm
/// dừng; bắt đầu cuộc gọi thì dừng mọi nguồn đang phát.
final class ExclusiveMediaPlayback {
  ExclusiveMediaPlayback._();

  static Object? _owner;
  static Future<void> Function()? _pauseOwner;

  /// Mã lượt yêu cầu phát mới nhất: tăng khi người dùng bấm phát, khi một nguồn
  /// bắt đầu phát và khi bắt đầu cuộc gọi.
  static int _requestEpoch = 0;

  /// Người dùng vừa bấm phát một nguồn còn phải tải: lấy mã lượt. Tải xong chỉ
  /// tự phát khi vẫn là lượt mới nhất ([isLatestRequest]): chưa bấm phát cái
  /// khác, chưa có cuộc gọi — không để tin tải xong chen ngang.
  static int beginRequest() => ++_requestEpoch;

  /// Mã lượt hiện tại (không tạo lượt mới), cho việc tự phát tiếp (vd. khôi
  /// phục video đang xem): có ai bấm phát cái khác / bắt đầu gọi thì thôi.
  static int get currentRequest => _requestEpoch;

  static bool isLatestRequest(int token) => token == _requestEpoch;

  /// [owner] sắp phát: tạm dừng nguồn khác đang phát (nếu có) rồi ghi nhớ cách
  /// dừng [owner] ([pause]).
  static void claim(Object owner, Future<void> Function() pause) {
    _requestEpoch += 1;
    final previousOwner = _owner;
    final previousPause = _pauseOwner;
    _owner = owner;
    _pauseOwner = pause;
    if (previousOwner != null &&
        !identical(previousOwner, owner) &&
        previousPause != null) {
      unawaited(_pauseSafely(previousPause));
    }
  }

  /// [owner] đã tự dừng / bị huỷ: bỏ ghi nhớ (chỉ khi nó còn là nguồn đang phát).
  static void release(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _pauseOwner = null;
    }
  }

  /// Dừng nguồn đang phát (vd. khi bắt đầu hay nhận cuộc gọi); nguồn đang tải
  /// dở cũng không tự phát khi tải xong.
  static Future<void> pauseAll() async {
    _requestEpoch += 1;
    final pause = _pauseOwner;
    _owner = null;
    _pauseOwner = null;
    if (pause != null) await _pauseSafely(pause);
  }

  @visibleForTesting
  static Object? get currentOwner => _owner;

  @visibleForTesting
  static void resetForTest() {
    _owner = null;
    _pauseOwner = null;
    _requestEpoch = 0;
  }

  static Future<void> _pauseSafely(Future<void> Function() pause) async {
    try {
      await pause();
    } on Object {
      // Nguồn phát đã bị huỷ giữa chừng: không còn gì để dừng.
    }
  }
}
