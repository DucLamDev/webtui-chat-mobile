import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/storage/media_disk_cache.dart';

void main() {
  late Directory root;
  late DateTime now;

  MediaDiskCache cache({int maxBytes = 1024 * 1024}) => MediaDiskCache(
    root: () async => root,
    maxBytes: maxBytes,
    now: () => now,
  );

  Future<File> writeFile(
    String name,
    int size, {
    Duration age = Duration.zero,
  }) async {
    final file = File('${root.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(size, 7));
    await file.setLastModified(now.subtract(age));
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media-disk-cache-');
    // Làm tròn giây: hệ tệp lưu giờ sửa theo giây.
    final real = DateTime.now();
    now = DateTime(
      real.year,
      real.month,
      real.day,
      real.hour,
      real.minute,
      real.second,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('ảnh đã tải được đọc lại từ máy, kể cả sau khi mở lại app', () async {
    var downloads = 0;
    Future<Uint8List> download() async {
      downloads += 1;
      return Uint8List.fromList(utf8.encode('anh-1'));
    }

    final target = File('${root.path}/acc/image/a.jpg');
    final first = await cache().ensureBytes(
      target,
      maxBytes: 1024,
      download: download,
    );
    final second = await cache().ensureBytes(
      target,
      maxBytes: 1024,
      download: download,
    );

    expect(utf8.decode(first), 'anh-1');
    expect(utf8.decode(second), 'anh-1');
    expect(
      downloads,
      1,
      reason: 'lần thứ hai (app mới) đọc từ kho, không tải lại',
    );
    expect(
      root.listSync(recursive: true).where((e) => e.path.contains('.part')),
      isEmpty,
    );
  });

  test(
    'tệp quá 7 ngày không dùng bị bỏ và tải lại; dưới 7 ngày thì dùng và tính lại hạn',
    () async {
      final old = await writeFile(
        'acc/file/old.pdf',
        10,
        age: const Duration(days: 8),
      );
      final recent = await writeFile(
        'acc/file/recent.pdf',
        10,
        age: const Duration(days: 6),
      );

      expect(await cache().lookup(old), isNull);
      expect(await old.exists(), isFalse);

      final found = await cache().lookup(recent);
      expect(found?.path, recent.path);
      expect(
        (await recent.stat()).modified,
        now,
        reason: 'dùng lại thì hạn 7 ngày tính lại từ đầu',
      );
    },
  );

  test('tệp sai cỡ so với máy chủ bị bỏ', () async {
    final file = await writeFile('acc/video/v.mp4', 10);
    expect(await cache().lookup(file, expectedBytes: 11), isNull);
    expect(await file.exists(), isFalse);
  });

  test('nhiều chỗ cùng xin một tệp thì chỉ tải một lần', () async {
    final store = cache();
    final target = File('${root.path}/acc/video/v.mp4');
    var downloads = 0;
    final gate = Completer<void>();
    Future<File> download(File into) async {
      downloads += 1;
      await gate.future;
      await into.writeAsString('video');
      return into;
    }

    final first = store.ensureFile(target, download: download);
    final second = store.ensureFile(target, download: download);
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(downloads, 1);
    expect(results.map((file) => file.path).toSet(), {target.path});
    expect(await target.readAsString(), 'video');
  });

  test('lượt tải của màn khác bị huỷ thì màn đang chờ tự tải lại', () async {
    final store = cache();
    final target = File('${root.path}/acc/voice/a.m4a');
    final gate = Completer<void>();
    final cancelled = store.ensureFile(
      target,
      download: (_) async {
        await gate.future;
        throw StateError('instance binding changed');
      },
    );
    final waiting = store.ensureFile(
      target,
      download: (into) async {
        await into.writeAsString('voice');
        return into;
      },
    );
    gate.complete();

    await expectLater(cancelled, throwsStateError);
    expect((await waiting).path, target.path);
    expect(await target.readAsString(), 'voice');
  });

  test(
    'dọn kho: bỏ tệp quá 7 ngày, tệp tải dở bị bỏ, rồi tệp lâu không dùng nhất khi vượt dung lượng',
    () async {
      final expired = await writeFile(
        'a/expired.jpg',
        10,
        age: const Duration(days: 8),
      );
      final stalePart = await writeFile(
        'a/x.jpg.part-1',
        10,
        age: const Duration(hours: 2),
      );
      final freshPart = await writeFile(
        'a/y.jpg.part-2',
        10,
        age: const Duration(minutes: 5),
      );
      final oldest = await writeFile(
        'b/oldest.mp4',
        40,
        age: const Duration(days: 3),
      );
      final middle = await writeFile(
        'b/middle.mp4',
        40,
        age: const Duration(days: 2),
      );
      final newest = await writeFile(
        'b/newest.mp4',
        40,
        age: const Duration(hours: 1),
      );

      final result = await cache(maxBytes: 100).trim();

      expect(await expired.exists(), isFalse);
      expect(await stalePart.exists(), isFalse);
      expect(
        await freshPart.exists(),
        isTrue,
        reason: 'có thể đang tải, không xoá giữa chừng',
      );
      expect(
        await oldest.exists(),
        isFalse,
        reason: 'vượt 100 byte: bỏ tệp lâu không dùng nhất',
      );
      expect(await middle.exists(), isTrue);
      expect(await newest.exists(), isTrue);
      expect(result.remainingBytes, 90);
      expect(result.deletedFiles, 3);
    },
  );

  test(
    'thư mục rỗng chỉ bị dọn khi đã cũ (thư mục mới có thể sắp có tệp tải về)',
    () async {
      final empty = Directory('${root.path}/gen-old/video123');
      await empty.create(recursive: true);
      final used = await writeFile('cache/acc/image/a.jpg', 10);

      await cache().trim();
      expect(await empty.exists(), isTrue, reason: 'vừa tạo: chưa dọn');

      // Hai tiếng sau: thư mục rỗng đã cũ thì dọn (cả thư mục cha thành rỗng),
      // thư mục còn tệp đang dùng thì giữ.
      now = now.add(const Duration(hours: 2));
      await used.setLastModified(now);
      await cache().trim();
      expect(await empty.exists(), isFalse);
      expect(await Directory('${root.path}/gen-old').exists(), isFalse);
      expect(await used.exists(), isTrue);
    },
  );

  test('tự dọn ở nền tối đa mỗi khoảng một lần', () async {
    var trims = 0;
    final store = MediaDiskCache(
      root: () async {
        trims += 1;
        return root;
      },
      now: () => now,
    );
    store.scheduleTrim();
    store.scheduleTrim();
    for (var i = 0; i < 50 && trims == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    store.scheduleTrim();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(trims, 1);

    now = now.add(const Duration(minutes: 16));
    store.scheduleTrim();
    for (var i = 0; i < 50 && trims == 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(trims, 2);
  });
}
