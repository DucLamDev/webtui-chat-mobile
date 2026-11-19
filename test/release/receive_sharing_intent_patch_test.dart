import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pluginDir = 'third_party/receive_sharing_intent';
const _kotlinDir =
    '$_pluginDir/android/src/main/kotlin/com/kasem/receive_sharing_intent';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('pubspec dùng bản receive_sharing_intent 1.8.1 đã vá trong repo', () {
    final pubspec = source('pubspec.yaml');
    final lock = source('pubspec.lock');
    final plugin = source('$_pluginDir/pubspec.yaml');

    expect(pubspec, contains('path: third_party/receive_sharing_intent'));
    expect(pubspec, isNot(contains('receive_sharing_intent: 1.8.1')));
    expect(lock, contains('path: "third_party/receive_sharing_intent"'));
    expect(plugin, contains('version: 1.8.1+webtui.1'));
    expect(File('$_pluginDir/WEBTUI_PATCH.md').existsSync(), isTrue);
    expect(File('$_pluginDir/LICENSE').existsSync(), isTrue);
  });

  test(
    'Android chỉ chép content:// vào thư mục chia sẻ tạm, tên đã làm sạch',
    () {
      final fileDirectory = source('$_kotlinDir/FileDirectory.kt');

      expect(
        fileDirectory,
        contains(
          'if (!"content".equals(uri.scheme, ignoreCase = true) || '
          'uri.authority == null) {',
        ),
      );
      expect(
        fileDirectory,
        contains(
          'SharedFileNames.sanitize(queryDisplayName(context, uri), extension)',
        ),
      );
      expect(
        fileDirectory,
        contains('File(context.cacheDir, SharedFileNames.SHARE_CACHE_DIR)'),
      );
      expect(
        fileDirectory,
        contains('SharedFileNames.confinedChild(targetDir, fileName)'),
      );
      expect(fileDirectory, contains('resolver.openInputStream(uri)'));
      // Không còn tự dựng đường dẫn bộ nhớ ngoài / trả thẳng đường dẫn URI.
      expect(fileDirectory, isNot(contains('getExternalStorageDirectory')));
      expect(fileDirectory, isNot(contains('return uri.path')));
      expect(
        fileDirectory,
        isNot(contains('File(context.cacheDir, fileName)')),
      );
      expect(fileDirectory, isNot(contains('"_data"')));
    },
  );

  test('hàm làm sạch tên chỉ giữ phần tên tệp và kiểm canonical path', () {
    final names = source('$_kotlinDir/SharedFileNames.kt');

    expect(names, contains('.replace(\'\\\\\', \'/\')'));
    expect(names, contains(".substringAfterLast('/')"));
    expect(names, contains(".trimStart('.')"));
    expect(names, contains(r'Regex("[\\u0000-\\u001F\\u007F:*?\"<>|]")'));
    expect(names, contains('val parentPath = parent.canonicalFile'));
    expect(
      names,
      contains('val target = File(parentPath, child).canonicalFile'),
    );
    expect(
      names,
      contains('return if (target.parentFile == parentPath) target else null'),
    );
  });

  test(
    'tệp không chép được thì bị bỏ, ảnh xem trước nằm trong thư mục chia sẻ',
    () {
      final plugin = source('$_kotlinDir/ReceiveSharingIntentPlugin.kt');

      expect(plugin, contains('if (uri != null && path == null) {'));
      expect(
        plugin,
        contains('SharedFileNames.confinedChild(it, "\${source.name}.png")'),
      );
      expect(
        plugin,
        isNot(
          contains('File(applicationContext.cacheDir, "\${File(path).name}'),
        ),
      );
    },
  );

  test('phòng chat kiểm tệp chia sẻ trước khi đính kèm', () {
    final chatRoom = source(
      'lib/features/conversations/presentation/screens/chat_room_screen.dart',
    );

    expect(chatRoom, contains('final check = await guard.check(shared.path);'));
    expect(chatRoom, contains('ref.read(sharedFilePathGuardProvider.future)'));
    expect(chatRoom, contains('path: path,'));
  });
}
