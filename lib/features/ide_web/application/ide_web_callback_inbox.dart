/// Nơi trao callback đăng nhập IDE từ deep link cho màn IDE, chỉ trong bộ nhớ
/// (không qua `location` của router nên mã không lộ qua nhật ký điều hướng).
final class IdeWebCallbackInbox {
  Uri? _pending;
  void Function(Uri uri)? _listener;

  /// `true` khi chưa có màn nào nhận: bên gọi phải mở màn IDE (một lần, kể cả
  /// khi hệ điều hành phát cùng một link hai lần).
  bool deliver(Uri uri) {
    final listener = _listener;
    if (listener != null) {
      listener(uri);
      return false;
    }
    final needsScreen = _pending == null;
    _pending = uri;
    return needsScreen;
  }

  /// Màn IDE nhận callback từ giờ; callback tới trước (mở lạnh) lấy ở [take].
  void Function() listen(void Function(Uri uri) listener) {
    _listener = listener;
    return () {
      if (identical(_listener, listener)) _listener = null;
    };
  }

  Uri? take() {
    final uri = _pending;
    _pending = null;
    return uri;
  }

  /// Phiên kết thúc khi chưa màn nào kịp nhận: không giữ lại mã.
  void clear() => _pending = null;
}
