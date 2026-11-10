import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ghi nhận các cuộc gọi đang mở trên máy (màn gọi đang hiển thị).
///
/// Khoá ứng dụng đọc trạng thái này để KHÔNG khoá khi đang gọi (khoá giữa cuộc
/// gọi từng làm rớt cuộc gọi). Màn gọi gọi [begin] khi mở và [end] khi đóng.
final class ActiveCallTracker extends StateNotifier<Set<String>> {
  ActiveCallTracker() : super(const <String>{});

  bool get hasActiveCall => state.isNotEmpty;

  /// Ghi nhận ở microtask kế tiếp: màn gọi gọi hàm này trong `initState`, lúc
  /// cây widget đang dựng, Riverpod không cho đổi provider đồng bộ.
  void begin(String callId) {
    final id = callId.trim().isEmpty ? '_' : callId.trim();
    scheduleMicrotask(() {
      if (!mounted || state.contains(id)) {
        return;
      }
      state = {...state, id};
    });
  }

  /// Gỡ cuộc gọi ở microtask kế tiếp: màn gọi gọi hàm này trong `dispose`,
  /// lúc cây widget đang khoá, không được báo thay đổi đồng bộ.
  void end(String callId) {
    final id = callId.trim().isEmpty ? '_' : callId.trim();
    scheduleMicrotask(() {
      if (!mounted || !state.contains(id)) {
        return;
      }
      state = {...state}..remove(id);
    });
  }
}

final activeCallTrackerProvider =
    StateNotifierProvider<ActiveCallTracker, Set<String>>(
      (_) => ActiveCallTracker(),
    );
