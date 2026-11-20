import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_media_models.dart';

/// PNG tối thiểu: chữ ký + IHDR có rộng / cao [w] x [h] + [extra] byte thừa.
List<int> _png(int extra, {int w = 100, int h = 200}) => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
  ...[(w >> 24) & 255, (w >> 16) & 255, (w >> 8) & 255, w & 255],
  ...[(h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255],
  ...List<int>.filled(extra, 1),
];

Map<String, Object?> _frame({
  Object? w = 100,
  Object? h = 200,
  String? data,
  String mime = 'image/png',
}) => {'w': w, 'h': h, 'mime': mime, 'data': data ?? base64Encode(_png(10))};

void main() {
  group('khung Màn hình app', () {
    test('khung đúng được nhận', () {
      final f = IdeAppFrame.tryParse(_frame());
      expect(f, isNotNull);
      expect(f!.aspect, 0.5);
    });
    test('khung quá 1 MB bị bỏ', () {
      expect(
        IdeAppFrame.tryParse(
          _frame(data: base64Encode(_png(ideFrameMaxBytes))),
        ),
        isNull,
      );
    });
    test('base64 hỏng, không phải PNG, sai mime bị bỏ', () {
      expect(IdeAppFrame.tryParse(_frame(data: '@@@@')), isNull);
      expect(
        IdeAppFrame.tryParse(_frame(data: base64Encode(List.filled(20, 7)))),
        isNull,
      );
      expect(IdeAppFrame.tryParse(_frame(mime: 'image/svg+xml')), isNull);
    });
    test('bom giải nén: IHDR không khớp w / h hoặc quá 4096 thì bỏ', () {
      // IHDR nói 100x200 nhưng JSON nói khác.
      expect(IdeAppFrame.tryParse(_frame(w: 101)), isNull);
      expect(IdeAppFrame.tryParse(_frame(h: 199)), isNull);
      // Cả JSON lẫn IHDR cùng khai 30000x30000 (ảnh nhỏ, kích thước khổng lồ).
      expect(
        IdeAppFrame.tryParse(
          _frame(
            w: 30000,
            h: 30000,
            data: base64Encode(_png(10, w: 30000, h: 30000)),
          ),
        ),
        isNull,
      );
      expect(
        IdeAppFrame.tryParse(
          _frame(w: 4097, h: 10, data: base64Encode(_png(10, w: 4097, h: 10))),
        ),
        isNull,
      );
      expect(
        IdeAppFrame.tryParse(
          _frame(
            w: 4096,
            h: 4096,
            data: base64Encode(_png(10, w: 4096, h: 4096)),
          ),
        ),
        isNotNull,
      );
      // Thiếu đoạn IHDR.
      final noIhdr = _png(10)..[12] = 0x58;
      expect(IdeAppFrame.tryParse(_frame(data: base64Encode(noIhdr))), isNull);
    });
    test('w / h vô lý thì bỏ khung', () {
      for (final bad in [0, -1, double.nan, double.infinity, 1e12, 'x', null]) {
        expect(IdeAppFrame.tryParse(_frame(w: bad)), isNull, reason: '$bad');
        expect(IdeAppFrame.tryParse(_frame(h: bad)), isNull, reason: '$bad');
      }
    });
  });

  group('đường dẫn tương đối', () {
    test('hợp lệ được ghép với root', () {
      expect(
        ideMediaJoin('/srv/web', 'video/a/video.mp4'),
        '/srv/web/video/a/video.mp4',
      );
      expect(ideMediaJoin('/srv/web/', 'a.png'), '/srv/web/a.png');
    });
    test('có .., tuyệt đối, ký tự điều khiển, ổ đĩa bị chặn', () {
      for (final bad in [
        '../x',
        'a/../b',
        '/etc/passwd',
        '\\a',
        'a\nb',
        'a\u202eb',
        'C:/x',
        '~/x',
        'a%2e%2e/b',
        'a//b',
        'a/',
        './a',
        'a/./b',
        'a\uFF0E\uFF0E/b',
        'a\u2024b',
        '',
        null,
        5,
      ]) {
        expect(ideMediaJoin('/srv/web', bad), isNull, reason: '$bad');
      }
    });
    test('video.get: n âm / trùng / lạ thì dùng số thứ tự', () {
      final d = IdeVideoDetail.tryParse({
        'video': {'slug': 'a'},
        'scenes': [
          {'n': -5},
          {'n': 2},
          {'n': 2},
          {'n': 'x'},
          {'n': 1e12},
        ],
      })!;
      expect(d.scenes.map((s) => s.n).toList(), [1, 2, 3, 4, 5]);
    });
    test('video.get: ảnh cảnh không an toàn bị bỏ, error thì scenes rỗng', () {
      final d = IdeVideoDetail.tryParse({
        'video': {'slug': 'a', 'title': 'A', 'state': 'nhap'},
        'scenes': [
          {'n': 1, 'text': 't', 'caption': '', 'image': '../x.png'},
          {'n': 2, 'text': 't', 'caption': '', 'image': 'img/2.png'},
        ],
        'files': {'video': '', 'draft': '', 'cover': ''},
      })!;
      expect(d.scenes[0].image, isNull);
      expect(d.scenes[1].image, 'img/2.png');
      final e = IdeVideoDetail.tryParse({
        'video': {'slug': 'a'},
        'scenes': [
          {'n': 1},
        ],
        'error': 'video.json hỏng',
      })!;
      expect(e.scenes, isEmpty);
      expect(e.error, isNotEmpty);
    });
  });

  test('số lạ hiện "—"', () {
    expect(ideMediaDuration(double.nan), '—');
    expect(ideMediaDuration(double.infinity), '—');
    expect(ideMediaDuration(-3), '—');
    expect(ideMediaDuration(1e15), '—');
    expect(ideMediaDuration(65), '1:05');
    final r = IdeVideoRow.tryParse({
      'slug': 'a',
      'scenes': -2,
      'seconds': 1e99,
    })!;
    expect(r.scenes, isNull);
    expect(r.seconds, isNull);
  });

  test('trạng thái video: mã gạch nối của IDE, mã lạ là null', () {
    expect(IdeVideoState.parse('da-xuat'), IdeVideoState.daXuat);
    expect(IdeVideoState.parse('kich-ban'), IdeVideoState.kichBan);
    expect(
      IdeVideoState.parse(
        'nh'
        'ap',
      ),
      IdeVideoState.nhap,
    );
    expect(
      IdeVideoState.parse(
        'l'
        'oi',
      ),
      IdeVideoState.loi,
    );
    expect(IdeVideoState.parse('daXuat'), isNull);
    expect(IdeVideoState.parse(''), isNull);
  });
}
