import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_insight_models.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_log_models.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_more_time.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_note_models.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_task_models.dart';

Map<String, Object?> _task(String id, {Object? due, String status = 'todo'}) =>
    {
      'id': id,
      'project': 'web',
      'title': 'Việc $id',
      'status': status,
      'due': due,
      'updated': 1763548800,
      'can_manage': true,
    };

void main() {
  group('hạn việc theo ngày địa phương', () {
    test('ngày chọn giữ đúng ngày ở đầu / cuối tháng, cuối năm, năm nhuận', () {
      expect(ideFormatDue(DateTime(2026, 1, 31)), '2026-01-31');
      expect(ideFormatDue(DateTime(2026, 3, 1)), '2026-03-01');
      expect(ideFormatDue(DateTime(2026, 12, 31, 23, 59, 59)), '2026-12-31');
      expect(ideFormatDue(DateTime(2028, 2, 29)), '2028-02-29');
      expect(ideFormatDue(DateTime(2026, 4, 5)), '2026-04-05');
    });

    test('chọn 00:00 / 23:59 cùng ngày vẫn ra cùng chuỗi (không qua UTC)', () {
      expect(
        ideFormatDue(DateTime(2026, 6, 30, 0, 0)),
        ideFormatDue(DateTime(2026, 6, 30, 23, 59)),
      );
      expect(ideFormatDue(DateTime(2026, 6, 30, 0, 0)), '2026-06-30');
    });

    test('đọc lại và từ chối ngày không có thật', () {
      expect(ideParseDue('2026-01-31'), DateTime(2026, 1, 31));
      expect(ideParseDue('2026-02-30'), isNull);
      expect(ideParseDue('2027-02-29'), isNull);
      expect(ideParseDue('2028-02-29'), DateTime(2028, 2, 29));
      expect(ideParseDue('31/01/2026'), isNull);
      expect(ideParseDue(null), isNull);
      expect(ideParseDue(''), isNull);
    });

    test('số ngày tới hạn qua đầu / cuối tháng', () {
      final now = DateTime(2026, 1, 31, 23, 59);
      expect(ideDueDays('2026-01-31', now), 0);
      expect(ideDueDays('2026-02-01', now), 1);
      expect(ideDueDays('2026-01-30', now), -1);
      expect(ideDueDays('2026-03-01', now), 29);
      expect(ideDueDays(null, now), isNull);
      expect(ideDueState('2026-01-31', now), IdeDueState.today);
      expect(ideDueState('2026-02-01', now), IdeDueState.soon);
      expect(ideDueState('2026-02-10', now), IdeDueState.later);
      expect(ideDueState('2026-01-30', now), IdeDueState.overdue);
      expect(ideDueState('2026-01-30', now, done: true), IdeDueState.none);
    });

    test('đổi giờ mùa hè không làm lệch một ngày', () {
      // 29/03/2026 là ngày chuyển giờ ở châu Âu; so bằng ngày lịch.
      expect(ideDueDays('2026-03-30', DateTime(2026, 3, 28, 23, 30)), 2);
      expect(ideDueDays('2026-03-29', DateTime(2026, 3, 29, 0, 5)), 0);
      expect(ideDueDays('2026-11-01', DateTime(2026, 10, 31, 12)), 1);
    });

    test('hiện dd/mm/yyyy', () {
      expect(ideDueDisplay('2026-01-05'), '05/01/2026');
      expect(ideDueDisplay('rác'), 'rác');
    });
  });

  group('giờ GĐ3 là giây Unix', () {
    test('giây → giờ địa phương, thực và nguyên', () {
      final t = ideTimeFromSeconds(1763548800)!;
      expect(t.millisecondsSinceEpoch, 1763548800 * 1000);
      expect(t.isUtc, isFalse);
      expect(
        ideTimeFromSeconds(1763548800.5)!.millisecondsSinceEpoch,
        1763548800500,
      );
      expect(ideTimeFromSeconds(0), isNull);
      expect(ideTimeFromSeconds('x'), isNull);
      expect(ideTimeFromSeconds(double.nan), isNull);
    });

    test('định dạng dd/mm HH:mm, khác năm thêm năm', () {
      final now = DateTime(2026, 11, 19);
      expect(
        ideFormatDateTime(DateTime(2026, 3, 4, 9, 5), now: now),
        '04/03 09:05',
      );
      expect(
        ideFormatDateTime(DateTime(2025, 12, 31, 23, 59), now: now),
        '31/12/2025 23:59',
      );
    });
  });

  group('việc', () {
    test('đọc việc, bỏ id sai, hạn sai thành không hạn', () {
      final ok = IdeTask.tryParse(_task('0123456789', due: '2026-02-28'))!;
      expect(ok.due, '2026-02-28');
      expect(ok.canManage, isTrue);
      expect(ok.updated, isNotNull);
      expect(IdeTask.tryParse(_task('xyz')), isNull);
      expect(IdeTask.tryParse(_task('0123456789AB')), isNull);
      expect(
        IdeTask.tryParse(_task('0123456789', due: '2026-13-01'))!.due,
        isNull,
      );
      expect(
        IdeTask.tryParse(_task('0123456789', status: 'lạ'))!.status,
        'todo',
      );
      expect(isIdeTaskId('0123456789'), isTrue);
      expect(isIdeTaskId('ABCDEF0123'), isFalse);
      expect(isIdeTaskId(null), isFalse);
    });

    test('gợi ý AI chạy nền thì còn chờ', () {
      for (final s in ['queued', 'running']) {
        expect(IdeTaskSuggestion.tryParse({'state': s})!.pending, isTrue);
      }
      expect(IdeTaskSuggestion.tryParse({'state': 'done'})!.pending, isFalse);
      expect(IdeTaskSuggestion.tryParse(null), isNull);
    });

    test('danh sách: người nhận có cả chính mình, lọc và sắp xếp', () {
      final list = IdeTaskList.parse({
        'viewer': 'lam',
        'assignable': {
          'web': {
            'members': ['an', 'binh'],
            'lead': 'chi',
            'deputies': ['dung'],
          },
        },
        'tasks': [
          _task('aaaaaaaaaa', due: '2026-05-02'),
          _task('bbbbbbbbbb', due: '2026-05-01'),
          _task('cccccccccc', status: 'done', due: '2026-04-01'),
          _task('dddddddddd'),
        ],
      });
      expect(list.projects, ['web']);
      expect(
        list.assigneesOf('web'),
        containsAll(['lam', 'an', 'binh', 'chi', 'dung']),
      );
      expect(list.assigneesOf('khac'), ['lam']);
      final all = filterAndSortTasks(list.tasks, null);
      expect(all.map((t) => t.id), [
        'bbbbbbbbbb',
        'aaaaaaaaaa',
        'dddddddddd',
        'cccccccccc',
      ]);
      expect(filterAndSortTasks(list.tasks, 'done').single.id, 'cccccccccc');
    });

    test('nội dung giao AI có tiêu đề, chi tiết, hạn', () {
      final t = IdeTask.tryParse({
        ..._task('0123456789', due: '2026-02-28'),
        'detail': 'Làm kỹ',
      })!;
      final p = ideTaskAiPrompt(t);
      expect(p, contains('Việc 0123456789'));
      expect(p, contains('Làm kỹ'));
      expect(p, contains('28/02/2026'));
    });
  });

  group('nhật ký thao tác', () {
    IdeOplogPage page(List<double> ts, {double? next}) => IdeOplogPage.parse({
      'matched': 5,
      'next': next,
      'summary': {
        'total': 9,
        'bad': 1,
        'kinds': {'git': 3},
      },
      'events': [
        for (final t in ts)
          {
            'ts': t,
            'kind': 'git',
            'action': 'push',
            'user': 'lam',
            'detail': 'd$t',
          },
      ],
    });

    test('đọc trang đầu', () {
      final p = page([30.5, 20.5], next: 20.5);
      expect(p.events.length, 2);
      expect(p.next, 20.5);
      expect(p.total, 9);
      expect(p.bad, 1);
      expect(p.kinds['git'], 3);
      expect(p.events.first.time, isNotNull);
    });

    test('nối trang sau, bỏ trùng, hết khi next null', () {
      final feed = IdeOplogFeed.first(page([30, 20], next: 20));
      expect(feed.hasMore, isTrue);
      final next = feed.append(page([20, 10], next: null));
      expect(next.events.map((e) => e.ts), [30, 20, 10]);
      expect(next.hasMore, isFalse);
    });

    test('mốc không lùi hoặc trang rỗng thì dừng, tránh lặp vô hạn', () {
      final feed = IdeOplogFeed.first(page([30, 20], next: 20));
      expect(feed.append(page([15], next: 20)).hasMore, isFalse);
      expect(feed.append(page([], next: 10)).hasMore, isFalse);
      expect(feed.append(page([15], next: 25)).hasMore, isFalse);
      expect(feed.append(page([15], next: 10)).hasMore, isTrue);
    });
  });

  group('ghi chú', () {
    test('id 12 hex', () {
      expect(isIdeNoteId('0123456789ab'), isTrue);
      expect(isIdeNoteId('0123456789'), isFalse);
      expect(isIdeNoteId('0123456789AB'), isFalse);
    });

    test('danh sách và ghi chú', () {
      final list = IdeNoteList.parse({
        'notes': [
          {
            'id': '0123456789ab',
            'title': 'A',
            'kind': 'so-do',
            'updatedAt': 1763548800,
          },
          {'id': 'sai', 'title': 'B'},
        ],
        'deleted': [
          {
            'id': 'abcdef012345',
            'title': 'C',
            'n': 3,
            'by': 'lam',
            'at': 1763548800,
          },
        ],
        'max': 50,
      });
      expect(list.notes.length, 1);
      expect(list.notes.single.isDiagram, isTrue);
      expect(list.deleted.single.n, 3);
      expect(list.isEmpty, isFalse);
      expect(IdeNote.tryParse({'id': 'sai'}), isNull);
      final n = IdeNote.tryParse({
        'id': '0123456789ab',
        'title': 'T',
        'body': 'B',
        'sha': 'f' * 64,
        'updatedByName': 'Lâm',
      })!;
      expect(n.updatedBy, 'Lâm');
      expect(n.isDiagram, isFalse);
      final v = IdeNoteVersion.parseList({
        'items': [
          {'n': 2, 'title': 'T', 'body': 'x', 'deleted': true},
          {'title': 'thiếu n'},
        ],
      });
      expect(v.single.deleted, isTrue);
    });
  });

  group('báo cáo, kiến trúc, changelog', () {
    test('báo cáo dự án riêng: số liệu + nhận xét AI', () {
      final r = IdeReport.parse({
        'generated_at': 1763548800,
        'my': true,
        'project': {
          'name': 'blog',
          'commits_7d': 4,
          'hours_total': {'today': 1.5, 'd7': 8},
        },
        'alerts': ['Chưa triển khai 10 ngày'],
        'ai': {
          'state': 'done',
          'nhan_xet': 'Ổn',
          'goi_y': ['Thêm test'],
        },
      })!;
      expect(r.my, isTrue);
      expect(
        r.facts.map((f) => '${f.label}=${f.value}'),
        containsAll([
          'Commit 7 ngày=4',
          'Giờ làm · Hôm nay=1.5',
          'Giờ làm · 7 ngày=8',
        ]),
      );
      expect(r.alerts.single, contains('10 ngày'));
      expect(r.hasAi, isTrue);
      expect(r.aiTips, ['Thêm test']);
      expect(IdeReport.parse('x'), isNull);
    });

    test('job tail', () {
      final t = IdeJobTail.parse({
        'text': 'a',
        'next': 3,
        'done': true,
        'result': {'k': 1},
      });
      expect(t.done, isTrue);
      expect(t.next, 3);
      expect(t.result, isA<Map>());
    });

    test('kiến trúc: sơ đồ, rủi ro, tiến độ theo bước', () {
      final a = IdeKientruc.parse({
        'exists': true,
        'sha': 'a' * 64,
        'data': {
          'name': 'Hệ thống',
          'zones': [
            {'id': 'z', 'name': 'Z', 'trust': 'noi-bo'},
          ],
          'nodes': [
            {'id': 'n', 'name': 'N', 'type': 'app', 'zone': 'z'},
          ],
          'edges': [],
          'risks': [
            'Lộ khoá',
            {'text': 'Không mã hoá', 'level': 'cao'},
          ],
          'steps': [
            {'name': 'B1', 'done': true},
            {'name': 'B2', 'status': 'todo'},
          ],
        },
      });
      expect(a.diagram, isNotNull);
      expect(a.risks.length, 2);
      expect(a.risks.last.level, 'cao');
      expect(a.progress, 0.5);
      expect(IdeKientruc.parse({'exists': false}).exists, isFalse);
      expect(
        IdeKientruc.parse({
          'data': {'progress': 40},
        }).progress,
        0.4,
      );
    });

    test('kiểm tra kiến trúc đếm lỗi / cảnh báo', () {
      final c = IdeKientrucCheck.parse({
        'ok': false,
        'issues': [
          {'level': 'loi', 'code': 'A', 'text': 'x', 'ref': 'n1'},
          {'level': 'canh-bao', 'code': 'B', 'text': 'y'},
        ],
        'counts': {'loi': 1, 'canh_bao': 1},
      });
      expect(c.ok, isFalse);
      expect(c.issues.first.error, isTrue);
      expect(c.warnings, 1);
    });

    test('changelog tối đa 50 mục, bỏ mục thiếu phiên bản', () {
      final log = IdeChangelog.parse({
        'version': '1.2.3',
        'items': [
          for (var i = 0; i < 60; i++)
            {
              'version': '1.0.$i',
              'date': '01/01/2026',
              'title': 't',
              'body': '- a',
            },
          {'title': 'thiếu'},
        ],
      });
      expect(log.items.length, 50);
      expect(log.version, '1.2.3');
    });
  });
}
