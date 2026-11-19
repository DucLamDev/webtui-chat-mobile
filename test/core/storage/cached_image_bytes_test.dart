import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/recent_download_failures.dart';
import 'package:webtui_chat/core/network/redirect_safe_file_downloader.dart';
import 'package:webtui_chat/core/storage/cached_image_bytes.dart';
import 'package:webtui_chat/core/storage/media_disk_cache.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cached-image-bytes-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'ảnh bị từ chối (403) không bị hỏi lại mỗi lần vẽ lại (log 17/11: 42 lần một ảnh)',
    () async {
      final cache = MediaDiskCache(root: () async => root);
      final failures = RecentDownloadFailures();
      var requests = 0;
      Future<Uint8List?> load() => loadCachedImageBytes(
        cache: cache,
        failures: failures,
        failureKey: 'server|user:a|https://server/api/v1/files/f/download',
        file: File('${root.path}/acc/avatar/a.img'),
        maxBytes: 1024,
        download: () async {
          requests += 1;
          throw const RedirectSafeDownloadException(
            'unexpected HTTP status 403',
            statusCode: 403,
          );
        },
      );

      for (var redraw = 0; redraw < 42; redraw++) {
        expect(await load(), isNull);
      }
      expect(requests, 1);
    },
  );

  test('lỗi mạng thì lần vẽ sau thử lại', () async {
    final cache = MediaDiskCache(root: () async => root);
    final failures = RecentDownloadFailures();
    var requests = 0;
    Future<Uint8List?> load() => loadCachedImageBytes(
      cache: cache,
      failures: failures,
      failureKey: 'k',
      file: File('${root.path}/acc/image/a.jpg'),
      maxBytes: 1024,
      download: () async {
        requests += 1;
        if (requests == 1) {
          throw const RedirectSafeDownloadException('download failed');
        }
        return Uint8List.fromList(utf8.encode('anh'));
      },
    );

    expect(await load(), isNull);
    expect(utf8.decode((await load())!), 'anh');
    expect(requests, 2);
  });

  test('ảnh đã tải lần sau đọc từ máy, kể cả khi app mở lại', () async {
    var requests = 0;
    Future<Uint8List?> load() => loadCachedImageBytes(
      cache: MediaDiskCache(root: () async => root),
      failures: RecentDownloadFailures(),
      failureKey: 'k',
      file: File('${root.path}/acc/avatar/b.img'),
      maxBytes: 1024,
      download: () async {
        requests += 1;
        return Uint8List.fromList(utf8.encode('avatar'));
      },
    );

    expect(utf8.decode((await load())!), 'avatar');
    expect(utf8.decode((await load())!), 'avatar');
    expect(requests, 1);
  });

  test('phiên đã đổi trong lúc tải thì không ghi ảnh vào kho', () async {
    final file = File('${root.path}/acc/avatar/c.img');
    final bytes = await loadCachedImageBytes(
      cache: MediaDiskCache(root: () async => root),
      failures: RecentDownloadFailures(),
      failureKey: 'k',
      file: file,
      maxBytes: 1024,
      download: () async => Uint8List.fromList(utf8.encode('avatar')),
      isStillCurrent: () async => false,
    );

    expect(utf8.decode(bytes!), 'avatar');
    expect(await file.exists(), isFalse);
  });
}
