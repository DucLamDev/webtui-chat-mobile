import 'dart:async';

/// Chạy lần lượt từng việc; việc trước lỗi không chặn việc sau.
final class IdeWebSerial {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
