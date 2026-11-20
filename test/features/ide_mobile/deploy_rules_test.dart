import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_deploy.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_mergeq.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_project.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_project_info.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/projects/ide_project_picker.dart';

import 'support/project_env.dart';

IdePreviewRecord _record({
  String project = 'web',
  String target = 'prod',
  DateTime? at,
  bool used = false,
}) => IdePreviewRecord(
  jobId: 'pj1',
  project: project,
  target: target,
  at: at ?? DateTime(2026, 11, 19, 10),
  preview: const IdeDeployPreview(),
  used: used,
);

void main() {
  final now = DateTime(2026, 11, 19, 10, 5);

  group('luật xem trước → triển khai', () {
    IdeDeployBlock block(IdePreviewRecord? r, {String target = 'prod'}) =>
        ideDeployBlock(r, project: 'web', target: target, now: now);

    test('chưa xem trước thì chặn', () {
      expect(block(null), IdeDeployBlock.missing);
    });
    test('đúng dự án, đúng máy, mới, chưa dùng thì cho', () {
      expect(block(_record()), IdeDeployBlock.none);
    });
    test('khác máy / khác dự án thì chặn', () {
      expect(block(_record(), target: 'test'), IdeDeployBlock.otherTarget);
      expect(block(_record(project: 'blog')), IdeDeployBlock.otherProject);
    });
    test('đủ 15 phút thì chặn, 14 phút 59 giây còn cho', () {
      final at = DateTime(2026, 11, 19, 10);
      expect(
        ideDeployBlock(
          _record(at: at),
          project: 'web',
          target: 'prod',
          now: at.add(const Duration(minutes: 14, seconds: 59)),
        ),
        IdeDeployBlock.none,
      );
      expect(
        ideDeployBlock(
          _record(at: at),
          project: 'web',
          target: 'prod',
          now: at.add(ideDeployPreviewMaxAge),
        ),
        IdeDeployBlock.expired,
      );
    });
    test('đã dùng một lần thì chặn; đồng hồ lùi cũng chặn', () {
      expect(block(_record().markUsed()), IdeDeployBlock.used);
      expect(
        block(_record(at: DateTime(2026, 11, 19, 11))),
        IdeDeployBlock.expired,
      );
    });
  });

  group('đọc dữ liệu', () {
    test('bản xem trước chuẩn: đếm theo s, cảnh báo, delete_many', () {
      final p = IdeDeployPreview.tryParse(previewResult(deleteMany: true))!;
      expect(p.counts, {'A': 1, 'M': 1, 'N': 1, 'D': 1});
      expect(p.warnings, ['Máy chủ có tệp mới hơn']);
      expect(p.deleteMany, isTrue);
      expect(p.base!.commit, '1111111222');
      expect(IdeDeployPreview.tryParse('x'), isNull);
    });

    test('tên op theo kiểu dự án', () {
      expect(
        IdeDeployOps.of(IdeProject.tryParse(proj('a', kind: 'vps'))!).run,
        'deploy.run',
      );
      final myGit = IdeDeployOps.of(
        IdeProject.tryParse(proj('my:a', my: true))!,
      );
      expect(myGit.run, 'my.deploy');
      expect(myGit.preview, 'my.preview');
      final mySync = IdeDeployOps.of(
        IdeProject.tryParse(proj('my:b', kind: 'local', my: true))!,
      );
      expect(mySync.run, 'my.sync');
      expect(mySync.sync, isTrue);
    });

    test('kết quả pr.create / git.merge / số PR', () {
      final pr = IdePrResult.tryParse({
        'number': 12,
        'url': 'https://x/pr/12',
        'existed': true,
        'warnings': ['a', ''],
      })!;
      expect(pr.number, 12);
      expect(pr.existed, isTrue);
      expect(pr.warnings, ['a']);
      expect(IdePrResult.tryParse({'number': 0}), isNull);
      expect(IdeMergeResult.parse({'queued': true}).queued, isTrue);
      expect(ideParsePrNumber(' #42 '), 42);
      expect(ideParsePrNumber('0'), isNull);
      expect(ideParsePrNumber('1234567890'), isNull);
      expect(ideParsePrNumber('4x'), isNull);
    });

    test('đường dẫn khôi phục không được thoát khỏi dự án', () {
      expect(ideRelativePathError('src/a.php'), isNull);
      expect(ideRelativePathError(''), isNotNull);
      expect(ideRelativePathError('../etc/passwd'), isNotNull);
      expect(ideRelativePathError('a/../../b'), isNotNull);
      expect(ideRelativePathError('/etc/passwd'), isNotNull);
      expect(ideRelativePathError('a\\b'), isNotNull);
    });

    test('xin quyền máy chủ: giờ 1–8, lý do 5–300', () {
      expect(ideVpsRequestError(hours: 1, reason: 'sửa lỗi gấp'), isNull);
      expect(ideVpsRequestError(hours: 0, reason: 'sửa lỗi gấp'), 'hours');
      expect(ideVpsRequestError(hours: 9, reason: 'sửa lỗi gấp'), 'hours');
      expect(ideVpsRequestError(hours: 2, reason: ' abc '), 'reason');
      expect(ideVpsRequestError(hours: 2, reason: 'a' * 301), 'reason');
    });

    test('hàng chờ: PR đang chờ, gần đây, quyền', () {
      final v = IdeMergeView.parse({
        'hang_cho': 'web',
        'muc': 'hang-cho',
        'hang': [
          {'so': 5, 'tieu_de': 'A', 'trang_thai': 'cho', 'rut': true},
          {'so': 'x'},
        ],
        'gan_day': [
          {'so': 4, 'ket_qua': 'tra-ve', 'ghi_chu': 'lỗi'},
        ],
        'viec_nhe': [{}, {}],
        'quyen': {
          'doi_muc': ['day-du', 'tat'],
          'merge': true,
        },
      });
      expect(v.queue.single.number, 5);
      expect(v.queue.single.withdrawable, isTrue);
      expect(v.recent.single.rejected, isTrue);
      expect(v.lightCount, 2);
      expect(v.canChangeMode, isTrue);
      expect(v.canAdmin, isFalse);
    });

    test('to_git.check và targets.show', () {
      final c = IdeToGitCheck.parse({
        'rows': [
          {'level': 'ok', 'name': 'a'},
          {'level': 'bad', 'name': 'b', 'fix': 'x'},
        ],
        'ok': false,
      });
      expect(c.rows.map((r) => r.level), [IdeCheckLevel.ok, IdeCheckLevel.bad]);
      expect(c.ok, isFalse);
      expect(IdeMyTarget.parse({'target': null}), isNull);
      expect(
        IdeMyTarget.parse({
          'target': {'ref': 'vps1', 'host': 'h', 'path': '/w', 'auto': true},
        })!.auto,
        isTrue,
      );
    });
  });

  test('chọn dự án: nhóm theo kiểu và lọc theo chữ gõ', () {
    final all = [
      for (final m in [
        proj('web'),
        proj('shop', kind: 'vps'),
        proj('lab', kind: 'local'),
        proj('my:blog', my: true),
      ])
        IdeProject.tryParse(m)!,
    ];
    expect(ideGroupProjects(all, '').keys, IdeProjectGroup.values);
    expect(ideGroupProjects(all, 'SHOP').keys, [IdeProjectGroup.vps]);
    expect(ideGroupProjects(all, 'zzz'), isEmpty);
  });
}
