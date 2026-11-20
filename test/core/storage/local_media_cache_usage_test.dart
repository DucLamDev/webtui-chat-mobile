import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:webtui_chat/core/storage/local_media_cache_usage.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local-media-cache-');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('tính tổng cỡ thư mục kho, xoá chỉ thư mục của tài khoản', () async {
    final account = Directory(path.join(temp.path, 'cache', 'tai-khoan-a'));
    final other = Directory(path.join(temp.path, 'cache', 'tai-khoan-b'));
    await File(path.join(account.path, 'image', 'a.jpg'))
        .create(recursive: true)
        .then((file) => file.writeAsBytes(List.filled(1000, 1)));
    await File(path.join(account.path, 'video', 'b.mp4'))
        .create(recursive: true)
        .then((file) => file.writeAsBytes(List.filled(2500, 1)));
    final otherFile = await File(
      path.join(other.path, 'image', 'c.jpg'),
    ).create(recursive: true);
    await otherFile.writeAsBytes(List.filled(10, 1));

    var cleared = 0;
    final usage = DirectoryMediaCacheUsage(
      directory: () async => account,
      onCleared: () async => cleared += 1,
    );

    expect(await usage.usedBytes(), 3500);
    await usage.clear();
    expect(await account.exists(), isFalse);
    expect(await otherFile.exists(), isTrue);
    expect(cleared, 1);
    expect(await usage.usedBytes(), 0);
    // Xoá lần nữa khi thư mục không còn: không lỗi.
    await usage.clear();
    expect(cleared, 2);
  });

  test('chưa đăng nhập (không có thư mục): 0 byte, không xoá gì', () async {
    final usage = DirectoryMediaCacheUsage(directory: () async => null);
    expect(await usage.usedBytes(), 0);
    await usage.clear();
  });
}
