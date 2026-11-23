import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_project.dart';

void main() {
  test('phân tích projects.list: kiểu, dự án riêng, máy đích, quyền', () {
    final list = parseIdeProjectList({
      'items': [
        {
          'name': 'chat-hub',
          'root': '/home/a/projects/chat-hub',
          'kind': 'git',
          'branch': 'main',
          'can': {'merge': true, 'deploy': false},
          'targets': [
            {'name': 'prod', 'label': 'Web chính'},
            {'name': ''},
            'rác',
          ],
        },
        {'name': 'my:blog', 'root': '/home/a/my/blog', 'kind': 'vps'},
        {'name': 'cu', 'root': '/x', 'git': true, 'type': 'git'},
        {'name': 'thieu-root'},
        'rác',
      ],
    });
    expect(list, hasLength(3));
    expect(list[0].kind, IdeProjectKind.git);
    expect(list[0].canMerge, isTrue);
    expect(list[0].canDeploy, isFalse);
    expect(list[0].canManage, isNull);
    expect(list[0].targets.single.title, 'Web chính');
    expect(list[1].my, isTrue);
    expect(list[1].title, 'blog');
    expect(list[1].kind, IdeProjectKind.vps);
    expect(list[2].isGit, isTrue);
    expect(parseIdeProjectList(null), isEmpty);
  });
}
