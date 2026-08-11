import 'dart:async';

/// Serializes active-instance commits with token compare-and-set mutations.
final class InstanceSessionMutationLock {
  InstanceSessionMutationLock._();

  static Future<void> _tail = Future<void>.value();

  static Future<T> runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
