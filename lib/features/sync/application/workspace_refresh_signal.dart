import 'dart:async';

/// Báo cho các màn đang mở (phòng chat) rằng đồng bộ bù vừa bị đặt lại
/// (`reset_required`): phải tự tải lại tin mới nhất vì các sự kiện đã lỡ không
/// còn trên máy chủ.
final class WorkspaceRefreshSignal {
  final _resets = StreamController<String>.broadcast();

  Stream<String> resetsFor(String workspaceId) {
    final normalized = workspaceId.trim();
    return _resets.stream.where((id) => id == normalized);
  }

  void notifyReset(String workspaceId) {
    final normalized = workspaceId.trim();
    if (normalized.isEmpty || _resets.isClosed) return;
    _resets.add(normalized);
  }

  Future<void> dispose() => _resets.close();
}
