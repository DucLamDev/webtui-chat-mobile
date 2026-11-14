import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_display.dart';

SharedFile _file(
  String name,
  String mime, {
  int size = 1024,
  DateTime? at,
  int? durationMs,
}) {
  return SharedFile(
    id: name,
    name: name,
    mimeType: mime,
    byteSize: size,
    createdAt: at ?? DateTime(2026, 11, 14, 14, 20),
    durationMs: durationMs,
  );
}

void main() {
  group('tên gọn', () {
    test('tên máy tự đặt của ảnh / video / ghi âm thành tên loại', () {
      expect(
        sharedFileTitle(_file('voice-1794306033034.webm', 'audio/webm')),
        'Ghi âm',
      );
      expect(
        sharedFileTitle(_file('voice_1793111961123.m4a', 'audio/mp4')),
        'Ghi âm',
      );
      expect(
        sharedFileTitle(
          _file('2aOboRBTenkGvwCSX2aIPP00HPyEVKoZTia3WLxo.mp4', 'video/mp4'),
        ),
        'Video',
      );
      expect(
        sharedFileTitle(
          _file('image_picker_088CD997-F56F-43CC-9DEC-AFE1.mp4', 'video/mp4'),
        ),
        'Video',
      );
      expect(
        sharedFileTitle(_file('IMG_20261110_1415.jpg', 'image/jpeg')),
        'Ảnh',
      );
    });

    test('tên người đặt và tài liệu giữ nguyên', () {
      expect(
        sharedFileTitle(_file('anh-san-pham.png', 'image/png')),
        'anh-san-pham.png',
      );
      expect(
        sharedFileTitle(_file('Họp tuần.m4a', 'audio/mp4')),
        'Họp tuần.m4a',
      );
      expect(
        sharedFileTitle(_file('fix1.docx', 'application/msword')),
        'fix1.docx',
      );
      // Tài liệu tên lạ vẫn giữ tên (người xem cần biết tệp nào).
      expect(
        sharedFileTitle(
          _file('a8F3kL0pQ2wE9rT5yU1iO7pA3sD.pdf', 'application/pdf'),
        ),
        'a8F3kL0pQ2wE9rT5yU1iO7pA3sD.pdf',
      );
    });
  });

  test('thời lượng', () {
    expect(sharedFileDurationText(42000), '0:42');
    expect(sharedFileDurationText(605400), '10:05');
    expect(sharedFileDurationText(3723000), '1:02:03');
    expect(sharedFileDurationText(0), '0:00');
  });

  group('dòng phụ', () {
    final now = DateTime(2026, 11, 14, 15);
    test('tài liệu có đuôi; nhóm gần đây hiện giờ', () {
      expect(
        sharedFileSubtitle(
          _file('fix1.docx', 'application/msword', size: 363 * 1024),
          showTime: true,
          now: now,
        ),
        'DOCX · 363 KB · 14:20',
      );
    });

    test(
      'video có thời lượng; ngày bỏ năm khi cùng năm, khác năm thì có năm',
      () {
        expect(
          sharedFileSubtitle(
            _file(
              'clip.mp4',
              'video/mp4',
              size: 4 * 1024 * 1024,
              at: DateTime(2026, 11, 11, 9),
              durationMs: 42000,
            ),
            showTime: false,
            now: now,
          ),
          '0:42 · 4,0 MB · 11/11',
        );
        expect(
          sharedFileSubtitle(
            _file('a.png', 'image/png', at: DateTime(2025, 8, 25)),
            showTime: false,
            now: now,
          ),
          '1,0 KB · 25/08/2025',
        );
      },
    );
  });

  test(
    'nhóm theo thời gian: mới nhất trước, Hôm nay / Hôm qua / Tháng này / tháng cũ',
    () {
      final now = DateTime(2026, 11, 14, 15);
      final sections = groupSharedFiles([
        _file('cu.pdf', 'application/pdf', at: DateTime(2026, 10, 3)),
        _file('homnay.png', 'image/png', at: DateTime(2026, 11, 14, 8)),
        _file('homqua.png', 'image/png', at: DateTime(2026, 11, 13, 23)),
        _file('dauthang.png', 'image/png', at: DateTime(2026, 11, 2)),
        _file('namngoai.png', 'image/png', at: DateTime(2025, 12, 31)),
        _file('homnay2.png', 'image/png', at: DateTime(2026, 11, 14, 9)),
      ], now);
      expect(sections.map((s) => s.title), [
        'Hôm nay',
        'Hôm qua',
        'Tháng này',
        'Tháng 10/2026',
        'Tháng 12/2025',
      ]);
      expect(sections.first.files.map((f) => f.name), [
        'homnay2.png',
        'homnay.png',
      ]);
      expect(sections.first.showTime, isTrue);
      expect(sections[2].showTime, isFalse);
      expect(groupSharedFiles(const [], now), isEmpty);
      // Lưới Ảnh / Video: chỉ chia theo tháng để mỗi hàng đủ ô.
      final monthly = groupSharedFiles(
        [
          _file('homnay.png', 'image/png', at: DateTime(2026, 11, 14, 8)),
          _file('homqua.png', 'image/png', at: DateTime(2026, 11, 13, 23)),
          _file('cu.png', 'image/png', at: DateTime(2026, 10, 3)),
        ],
        now,
        byMonth: true,
      );
      expect(monthly.map((s) => s.title), ['Tháng này', 'Tháng 10/2026']);
      expect(monthly.first.files, hasLength(2));
    },
  );

  test('đếm theo loại', () {
    final counts = countSharedFilesByKind([
      _file('a.png', 'image/png'),
      _file('b.png', 'image/png'),
      _file('c.mp4', 'video/mp4'),
    ]);
    expect(counts[SharedFileKind.image], 2);
    expect(counts[SharedFileKind.video], 1);
    expect(counts[SharedFileKind.audio], isNull);
  });
}
