import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/bounded_image_request_pool.dart';

void main() {
  test('deduplicates the same request and bounds concurrent loaders', () async {
    final pool = BoundedImageRequestPool(maxConcurrent: 2);
    final releases = <Completer<Uint8List?>>[];
    var active = 0;
    var peak = 0;
    var calls = 0;

    Future<Uint8List?> loader() {
      calls++;
      active++;
      if (active > peak) peak = active;
      final release = Completer<Uint8List?>();
      releases.add(release);
      return release.future.whenComplete(() => active--);
    }

    final first = pool.load(key: 'same', maxBytes: 16, loader: loader);
    final duplicate = pool.load(key: 'same', maxBytes: 16, loader: loader);
    final second = pool.load(key: 'second', maxBytes: 16, loader: loader);
    final third = pool.load(key: 'third', maxBytes: 16, loader: loader);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);
    expect(peak, 2);
    releases[0].complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 3);
    releases[1].complete(Uint8List.fromList([2]));
    releases[2].complete(Uint8List.fromList([3]));

    expect(await first, [1]);
    expect(await duplicate, [1]);
    expect(await second, [2]);
    expect(await third, [3]);
  });

  test('LRU cache stays within its byte budget', () async {
    final pool = BoundedImageRequestPool(
      maxConcurrent: 1,
      maxEntries: 2,
      maxCacheBytes: 4,
    );
    var loads = 0;
    Future<Uint8List?> load(String key, List<int> value) {
      return pool.load(
        key: key,
        maxBytes: 4,
        loader: () async {
          loads++;
          return Uint8List.fromList(value);
        },
      );
    }

    await load('a', [1, 1]);
    await load('b', [2, 2]);
    await load('a', [9, 9]);
    await load('c', [3, 3]);
    await load('b', [8, 8]);

    expect(loads, 4, reason: 'a was reused; least-recent b was evicted');
  });

  test(
    'clear prevents an old in-flight request from repopulating cache',
    () async {
      final pool = BoundedImageRequestPool(maxConcurrent: 1);
      final oldResponse = Completer<Uint8List?>();
      var freshLoads = 0;

      final old = pool.load(
        key: 'scope-a',
        maxBytes: 8,
        loader: () => oldResponse.future,
      );
      await Future<void>.delayed(Duration.zero);
      pool.clear();
      oldResponse.complete(Uint8List.fromList([1]));
      await old;

      final fresh = await pool.load(
        key: 'scope-a',
        maxBytes: 8,
        loader: () async {
          freshLoads++;
          return Uint8List.fromList([2]);
        },
      );

      expect(freshLoads, 1);
      expect(fresh, [2]);
    },
  );
}
