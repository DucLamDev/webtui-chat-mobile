import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:webtui_chat/features/conversations/data/files/compressed_video_file_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('webtui-store-test');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('id lạ không thoát khỏi thư mục riêng', () async {
    final store = CompressedVideoFileStore(rootDirectory: () async => root);
    final dir = p.join(root.path, CompressedVideoFileStore.folderName);

    final safe = await store.pathFor('abc-123_X');
    final evil = await store.pathFor('../../etc/passwd');

    expect(safe, p.join(dir, 'abc-123_X.mp4'));
    expect(p.dirname(evil), dir);
    expect(p.basename(evil), matches(RegExp(r'^[0-9a-f]{64}\.mp4$')));
    expect(await Directory(dir).exists(), isTrue);
  });

  test('lần gọi đầu xoá tệp cũ hơn 24 giờ, giữ tệp mới', () async {
    final dir = Directory(
      p.join(root.path, CompressedVideoFileStore.folderName),
    )..createSync(recursive: true);
    final old = File(p.join(dir.path, 'cu.mp4'))..writeAsBytesSync([1]);
    final fresh = File(p.join(dir.path, 'moi.mp4'))..writeAsBytesSync([1]);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 30)));

    await CompressedVideoFileStore(
      rootDirectory: () async => root,
    ).pathFor('x');

    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });
}
