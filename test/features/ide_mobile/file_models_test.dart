import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_files_service.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_errors.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_file_models.dart';

import 'support/rpc_env.dart';

void main() {
  test('tên không hợp lệ bị chặn', () {
    expect(ideCheckName('a.txt'), isNull);
    expect(ideCheckName(''), IdeNameError.empty);
    expect(ideCheckName('  '), IdeNameError.empty);
    expect(ideCheckName('..'), IdeNameError.dots);
    expect(ideCheckName('.'), IdeNameError.dots);
    expect(ideCheckName('a/b'), IdeNameError.slash);
    expect(ideCheckName(r'a\b'), IdeNameError.slash);
    expect(ideCheckName('a\u0000b'), IdeNameError.control);
    expect(ideCheckName('a' * 256), IdeNameError.tooLong);
  });

  test('đường dẫn: không .. và phải tuyệt đối', () {
    expect(ideIsSafePath('/srv/a/b'), isTrue);
    expect(ideIsSafePath('/srv/../etc'), isFalse);
    expect(ideIsSafePath(r'/srv\..\etc'), isFalse);
    expect(ideIsSafePath('srv/a'), isFalse);
    expect(ideJoinPath('/srv/a', 'b.txt'), '/srv/a/b.txt');
    expect(ideJoinPath('/srv/a/', 'b.txt'), '/srv/a/b.txt');
    expect(ideJoinPath('/srv/a', '..'), isNull);
    expect(ideJoinPath('/srv/../a', 'b'), isNull);
  });

  test('danh sách bỏ dòng có tên xấu', () {
    final list = parseIdeFileEntries('/srv/a', {
      'items': [
        {'name': 'ok.txt', 't': 'f', 'size': 5},
        {'name': '../x', 't': 'f'},
        {'name': 'd', 't': 'd', 'git': 'M'},
        {'name': '.env', 't': 'f', 'secret': true},
      ],
    });
    expect(list.map((e) => e.name), ['ok.txt', 'd', '.env']);
    expect(list[1].isDir, isTrue);
    expect(list[1].git, 'M');
    expect(list[2].secret, isTrue);
    expect(list[2].isHidden, isTrue);
  });

  test('breadcrumb và thư mục cha', () {
    final c = ideBreadcrumbs('/srv/p', '/srv/p/a/b', rootLabel: 'P');
    expect(c.map((e) => e.$1), ['P', 'a', 'b']);
    expect(c.last.$2, '/srv/p/a/b');
    expect(ideParentPath('/srv/p/a'), '/srv/p');
    expect(ideIsInside('/srv/p', '/srv/p2'), isFalse);
    expect(ideIsInside('/srv/p', '/srv/p/x'), isTrue);
  });

  test('kết quả tìm bỏ đường dẫn có ..', () {
    final r = parseIdeGrep({
      'items': [
        {'path': '/a/b', 'line': 3, 'text': 'x'},
        {'path': '/a/../b', 'line': 1, 'text': 'y'},
      ],
      'truncated': true,
    });
    expect(r.items, hasLength(1));
    expect(r.items.single.line, 3);
    expect(r.truncated, isTrue);
  });

  test('loại tệp và dòng diff', () {
    expect(ideFileKindOf('a.PNG'), IdeFileKind.image);
    expect(ideFileKindOf('a.docx'), IdeFileKind.office);
    expect(ideFileKindOf('a.zip'), IdeFileKind.other);
    expect(ideFileKindOf('main.dart'), IdeFileKind.code);
    expect(ideDiffLineKind('+x'), IdeDiffLineKind.add);
    expect(ideDiffLineKind('-x'), IdeDiffLineKind.remove);
    expect(ideDiffLineKind('+++ b/x'), IdeDiffLineKind.header);
    expect(ideDiffLineKind('@@ -1 +1 @@'), IdeDiffLineKind.hunk);
  });

  test('tải từ liên kết: chỉ gửi https có tên máy', () async {
    final sent = <String>[];
    final env = IdeRpcEnv((op, args) {
      sent.add('$op ${args['url']}');
      return {'job': 'j1'};
    }, ops: const ['files.fetch']);
    await env.up();
    addTearDown(env.dispose);
    final files = IdeFilesService(env.rpc);
    for (final bad in [
      'http://a.vn/x',
      'file:///etc/passwd',
      'https:///x',
      'x',
    ]) {
      await expectLater(files.fetch('/p', bad), throwsA(isA<IdeBadRequest>()));
    }
    expect(sent, isEmpty);
    expect(await files.fetch('/p', 'https://a.vn/x.zip'), 'j1');
    expect(sent, ['files.fetch https://a.vn/x.zip']);
  });
}
