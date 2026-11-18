import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:webtui_chat/features/conversations/data/files/media_disk_cache.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media-disk-cache-test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  File fileIn(String name) => File(path.join(root.path, 'media', name));

  Future<File> writeBytes(File file, int length) async {
    await file.parent.create(recursive: true);
    return file.writeAsBytes(List<int>.filled(length, 7));
  }

  test(
    'lookup misses when the file is absent, empty or the wrong size',
    () async {
      final cache = MediaDiskCache();
      final target = fileIn('a.mp4');

      expect(await cache.lookup(target), isNull);
      await writeBytes(target, 0);
      expect(await cache.lookup(target), isNull);
      await writeBytes(target, 10);
      expect(await cache.lookup(target, expectedBytes: 12), isNull);
      expect(
        (await cache.lookup(target, expectedBytes: 10))?.path,
        target.path,
      );
      expect((await cache.lookup(target))?.path, target.path);
    },
  );

  test('lookup marks the file as just viewed', () async {
    final now = DateTime(2026, 11, 18, 9);
    final cache = MediaDiskCache(clock: () => now);
    final target = await writeBytes(fileIn('a.jpg'), 4);
    await target.setLastModified(DateTime(2026, 1, 1));

    await cache.lookup(target);

    expect(
      (await target.lastModified()).difference(now).inSeconds.abs(),
      lessThan(2),
    );
  });

  test('obtain reuses a complete cached file without downloading', () async {
    final cache = MediaDiskCache();
    final target = await writeBytes(fileIn('a.jpg'), 5);
    var downloads = 0;

    final result = await cache.obtain(
      target,
      expectedBytes: 5,
      download: (_) async {
        downloads++;
        return target;
      },
    );

    expect(result.path, target.path);
    expect(downloads, 0);
  });

  test('concurrent obtain shares one download and fans out progress', () async {
    final cache = MediaDiskCache();
    final target = fileIn('a.mp4');
    final release = Completer<void>();
    var downloads = 0;
    final firstProgress = <int>[];
    final secondProgress = <int>[];

    Future<File> download(void Function(int, int) report) async {
      downloads++;
      await release.future;
      report(3, 6);
      return writeBytes(target, 6);
    }

    final first = cache.obtain(
      target,
      expectedBytes: 6,
      onProgress: (received, _) => firstProgress.add(received),
      download: download,
    );
    await Future<void>.delayed(Duration.zero);
    final second = cache.obtain(
      target,
      expectedBytes: 6,
      onProgress: (received, _) => secondProgress.add(received),
      download: download,
    );
    // Đang tải dở thì không coi là có sẵn.
    expect(await cache.lookup(target), isNull);
    release.complete();

    expect((await first).path, target.path);
    expect((await second).path, target.path);
    expect(downloads, 1);
    expect(firstProgress, [3]);
    expect(secondProgress, [3]);
  });

  test(
    'a failed download reaches every waiter and the next call retries',
    () async {
      final cache = MediaDiskCache();
      final target = fileIn('a.mp4');
      var downloads = 0;

      await expectLater(
        cache.obtain(
          target,
          download: (_) async {
            downloads++;
            throw const FileSystemException('network');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      final result = await cache.obtain(
        target,
        download: (_) async {
          downloads++;
          return writeBytes(target, 2);
        },
      );
      expect(result.path, target.path);
      expect(downloads, 2);
    },
  );

  test('trim removes least recently viewed files beyond the limit', () async {
    final cache = MediaDiskCache(maxBytes: 25);
    final oldest = await writeBytes(fileIn('oldest.jpg'), 10);
    final middle = await writeBytes(fileIn('middle.jpg'), 10);
    final newest = await writeBytes(fileIn('newest.jpg'), 10);
    final kept = await writeBytes(fileIn('kept.mp4'), 10);
    final partial = await writeBytes(fileIn('x.mp4.part-1'), 10);
    await oldest.setLastModified(DateTime(2026, 1, 1));
    await middle.setLastModified(DateTime(2026, 1, 2));
    await newest.setLastModified(DateTime(2026, 1, 3));
    await kept.setLastModified(DateTime(2025, 1, 1));
    await partial.setLastModified(DateTime(2025, 1, 1));

    await cache.trim(oldest.parent, keep: kept.path);

    // Tổng 50 → phải ≤ 25; tệp vừa tải và tệp đang tải dở (20) không được xoá nên xoá hết phần còn lại.
    expect(await oldest.exists(), isFalse);
    expect(await middle.exists(), isFalse);
    expect(await newest.exists(), isFalse);
    expect(await kept.exists(), isTrue);
    expect(await partial.exists(), isTrue);
  });

  test('trim leaves the folder alone while under the limit', () async {
    final cache = MediaDiskCache(maxBytes: 100);
    final a = await writeBytes(fileIn('a.jpg'), 10);
    final b = await writeBytes(fileIn('b.jpg'), 10);

    await cache.trim(a.parent);

    expect(await a.exists(), isTrue);
    expect(await b.exists(), isTrue);
  });
}
