import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:webtui_chat/core/platform/shared_file_path_guard.dart';

void main() {
  late Directory sandbox;
  late String appData;
  late String cacheDir;
  late String shareCache;
  late String filesDir;
  late String documentsDir;
  late String databasesDir;
  late String outsideDir;
  late SharedFilePathGuard guard;

  String writeFile(String path, {String content = 'nội dung'}) {
    final file = File(path)..createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('shared_file_guard_');
    appData = p.join(sandbox.path, 'data', 'app');
    cacheDir = p.join(appData, 'cache');
    shareCache = p.join(cacheDir, sharedIntentCacheDirName);
    filesDir = p.join(appData, 'files');
    documentsDir = p.join(appData, 'app_flutter');
    databasesDir = p.join(appData, 'databases');
    outsideDir = p.join(sandbox.path, 'outside');
    for (final dir in [
      shareCache,
      filesDir,
      documentsDir,
      databasesDir,
      outsideDir,
    ]) {
      Directory(dir).createSync(recursive: true);
    }
    guard = SharedFilePathGuard(
      allowedRoots: [shareCache],
      privateRoots: [filesDir, documentsDir, databasesDir],
    );
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('nhận tệp plugin đã chép vào thư mục chia sẻ tạm', () async {
    final path = writeFile(p.join(shareCache, 'abc', 'ảnh.jpg'));

    final check = await guard.check(path);

    expect(check.isAccepted, isTrue);
    expect(check.path, p.normalize(File(path).resolveSymbolicLinksSync()));
    expect(check.byteSize, File(path).lengthSync());
  });

  test('từ chối tệp trong thư mục dữ liệu riêng của app', () async {
    for (final path in [
      writeFile(p.join(filesDir, 'webtui_chat.sqlite')),
      writeFile(p.join(documentsDir, 'note.txt')),
      writeFile(p.join(databasesDir, 'cache.db')),
    ]) {
      final check = await guard.check(path);
      expect(check.isAccepted, isFalse, reason: path);
      expect(check.rejection, SharedFileRejection.privateLocation);
    }
  });

  test('từ chối tệp ngoài thư mục chia sẻ tạm', () async {
    final inCacheRoot = writeFile(p.join(cacheDir, 'other.bin'));
    final outside = writeFile(p.join(outsideDir, 'x.pdf'));

    expect(
      (await guard.check(inCacheRoot)).rejection,
      SharedFileRejection.outsideShareCache,
    );
    expect(
      (await guard.check(outside)).rejection,
      SharedFileRejection.outsideShareCache,
    );
  });

  test('từ chối đường dẫn có đoạn ".."', () async {
    writeFile(p.join(filesDir, 'webtui_chat.sqlite'));
    Directory(p.join(shareCache, 'abc')).createSync();
    final escaped = [
      shareCache,
      'abc',
      '..',
      '..',
      '..',
      'files',
      'webtui_chat.sqlite',
    ].join('/');
    final stayingInside = '$shareCache/abc/../abc2/x.txt';
    writeFile(p.join(shareCache, 'abc2', 'x.txt'));

    expect(
      (await guard.check(escaped)).rejection,
      SharedFileRejection.parentSegment,
    );
    expect(
      (await guard.check(stayingInside)).rejection,
      SharedFileRejection.parentSegment,
    );
  });

  test('từ chối symlink trong thư mục chia sẻ trỏ ra ngoài', () async {
    final privateTarget = writeFile(p.join(filesDir, 'webtui_chat.sqlite'));
    final outsideTarget = writeFile(p.join(outsideDir, 'x.pdf'));
    final linkToPrivate = p.join(shareCache, 'abc', 'db.jpg');
    final linkToOutside = p.join(shareCache, 'abc', 'x.pdf');
    Directory(p.join(shareCache, 'abc')).createSync();
    Link(linkToPrivate).createSync(privateTarget);
    Link(linkToOutside).createSync(outsideTarget);
    final linkedDir = p.join(shareCache, 'linked');
    Link(linkedDir).createSync(filesDir);

    expect(
      (await guard.check(linkToPrivate)).rejection,
      SharedFileRejection.privateLocation,
    );
    expect(
      (await guard.check(linkToOutside)).rejection,
      SharedFileRejection.outsideShareCache,
    );
    expect(
      (await guard.check(p.join(linkedDir, 'webtui_chat.sqlite'))).rejection,
      SharedFileRejection.privateLocation,
    );
  });

  test(
    'từ chối đường dẫn rỗng, tương đối, không tồn tại, thư mục, tệp rỗng',
    () async {
      Directory(p.join(shareCache, 'dir')).createSync();
      final emptyFile = writeFile(p.join(shareCache, 'empty.txt'), content: '');

      expect((await guard.check('  ')).rejection, SharedFileRejection.empty);
      expect(
        (await guard.check('cache/receive_sharing_intent/a.txt')).rejection,
        SharedFileRejection.notAbsolute,
      );
      expect(
        (await guard.check(p.join(shareCache, 'missing.txt'))).rejection,
        SharedFileRejection.missing,
      );
      expect(
        (await guard.check(p.join(shareCache, 'dir'))).rejection,
        SharedFileRejection.notRegularFile,
      );
      expect(
        (await guard.check(emptyFile)).rejection,
        SharedFileRejection.emptyFile,
      );
    },
  );

  test('không có thư mục được nhận thì từ chối mọi tệp', () async {
    final path = writeFile(p.join(shareCache, 'abc', 'a.txt'));
    const closed = SharedFilePathGuard(allowedRoots: []);

    expect(
      (await closed.check(path)).rejection,
      SharedFileRejection.outsideShareCache,
    );
  });

  test('thư mục chia sẻ tạm của Android khớp tên trong plugin đã vá', () {
    final kotlin = File(
      'third_party/receive_sharing_intent/android/src/main/kotlin/com/kasem/'
      'receive_sharing_intent/SharedFileNames.kt',
    ).readAsStringSync();

    expect(
      kotlin,
      contains('const val SHARE_CACHE_DIR = "$sharedIntentCacheDirName"'),
    );
  });
}
