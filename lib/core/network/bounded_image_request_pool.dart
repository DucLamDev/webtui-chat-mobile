import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// Deduplicates small image requests and bounds both network concurrency and
/// the amount of compressed image data retained by the shared memory cache.
final class BoundedImageRequestPool {
  BoundedImageRequestPool({
    this.maxConcurrent = 3,
    this.maxEntries = 32,
    this.maxCacheBytes = 8 * 1024 * 1024,
  }) : assert(maxConcurrent > 0),
       assert(maxEntries > 0),
       assert(maxCacheBytes > 0);

  final int maxConcurrent;
  final int maxEntries;
  final int maxCacheBytes;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Queue<Completer<void>> _waiters = Queue();
  int _active = 0;
  int _cachedBytes = 0;
  int _generation = 0;

  Future<Uint8List?> load({
    required String key,
    required int maxBytes,
    required Future<Uint8List?> Function() loader,
  }) {
    if (key.trim().isEmpty || maxBytes <= 0) {
      return Future<Uint8List?>.value();
    }
    final cached = _cache.remove(key);
    if (cached != null) {
      if (cached.lengthInBytes <= maxBytes) {
        _cache[key] = cached;
        return Future<Uint8List?>.value(cached);
      }
      _cachedBytes -= cached.lengthInBytes;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final requestGeneration = _generation;
    late final Future<Uint8List?> request;
    request = _run(maxBytes: maxBytes, loader: loader)
        .then((bytes) {
          if (requestGeneration == _generation &&
              bytes != null &&
              bytes.isNotEmpty &&
              bytes.lengthInBytes <= maxBytes) {
            _remember(key, bytes);
          }
          return bytes;
        })
        .whenComplete(() {
          if (identical(_inFlight[key], request)) {
            _inFlight.remove(key);
          }
        });
    _inFlight[key] = request;
    return request;
  }

  void clear() {
    _generation++;
    _cache.clear();
    _cachedBytes = 0;
  }

  Future<Uint8List?> _run({
    required int maxBytes,
    required Future<Uint8List?> Function() loader,
  }) async {
    await _acquire();
    try {
      final bytes = await loader();
      if (bytes == null || bytes.isEmpty || bytes.lengthInBytes > maxBytes) {
        return null;
      }
      return bytes;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }

  void _remember(String key, Uint8List bytes) {
    final previous = _cache.remove(key);
    if (previous != null) {
      _cachedBytes -= previous.lengthInBytes;
    }
    if (bytes.lengthInBytes > maxCacheBytes) return;
    while (_cache.isNotEmpty &&
        (_cache.length >= maxEntries ||
            _cachedBytes + bytes.lengthInBytes > maxCacheBytes)) {
      final oldest = _cache.keys.first;
      final removed = _cache.remove(oldest);
      if (removed != null) _cachedBytes -= removed.lengthInBytes;
    }
    _cache[key] = bytes;
    _cachedBytes += bytes.lengthInBytes;
  }
}
