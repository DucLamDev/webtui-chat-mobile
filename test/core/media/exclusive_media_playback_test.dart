import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/media/exclusive_media_playback.dart';

void main() {
  tearDown(ExclusiveMediaPlayback.resetForTest);

  test('phát tin thoại B thì tin thoại A đang phát tự tạm dừng', () async {
    final paused = <String>[];
    final a = Object();
    final b = Object();
    ExclusiveMediaPlayback.claim(a, () async => paused.add('a'));
    ExclusiveMediaPlayback.claim(b, () async => paused.add('b'));
    await Future<void>.delayed(Duration.zero);

    expect(paused, ['a']);
    expect(ExclusiveMediaPlayback.currentOwner, same(b));
  });

  test('phát lại chính nó không tự dừng', () async {
    final paused = <String>[];
    final a = Object();
    ExclusiveMediaPlayback.claim(a, () async => paused.add('a'));
    ExclusiveMediaPlayback.claim(a, () async => paused.add('a2'));
    await Future<void>.delayed(Duration.zero);
    expect(paused, isEmpty);
  });

  test(
    'nguồn đã dừng / huỷ thì không bị dừng nữa; cuộc gọi dừng mọi nguồn',
    () async {
      final paused = <String>[];
      final a = Object();
      final b = Object();
      ExclusiveMediaPlayback.claim(a, () async => paused.add('a'));
      ExclusiveMediaPlayback.release(a);
      ExclusiveMediaPlayback.claim(b, () async => paused.add('b'));
      await Future<void>.delayed(Duration.zero);
      expect(paused, isEmpty);

      // Nguồn cũ release muộn không xoá nguồn mới.
      ExclusiveMediaPlayback.release(a);
      expect(ExclusiveMediaPlayback.currentOwner, same(b));

      await ExclusiveMediaPlayback.pauseAll();
      expect(paused, ['b']);
      expect(ExclusiveMediaPlayback.currentOwner, isNull);
    },
  );

  test(
    'nguồn bị huỷ giữa chừng (dừng ném lỗi) không làm hỏng nguồn mới',
    () async {
      final a = Object();
      final b = Object();
      ExclusiveMediaPlayback.claim(a, () async => throw StateError('disposed'));
      ExclusiveMediaPlayback.claim(b, () async {});
      await Future<void>.delayed(Duration.zero);
      expect(ExclusiveMediaPlayback.currentOwner, same(b));
    },
  );

  test(
    'tin đang tải dở không tự phát chen ngang khi người dùng đã bấm phát cái khác',
    () {
      final tokenA = ExclusiveMediaPlayback.beginRequest();
      // Tin B đã có sẵn trên máy: bấm là phát ngay.
      ExclusiveMediaPlayback.claim(Object(), () async {});
      expect(ExclusiveMediaPlayback.isLatestRequest(tokenA), isFalse);

      final tokenC = ExclusiveMediaPlayback.beginRequest();
      expect(ExclusiveMediaPlayback.isLatestRequest(tokenC), isTrue);
    },
  );

  test('bắt đầu cuộc gọi thì tin / video đang tải dở không tự phát', () async {
    final pending = ExclusiveMediaPlayback.beginRequest();
    final resume = ExclusiveMediaPlayback.currentRequest;
    await ExclusiveMediaPlayback.pauseAll();
    expect(ExclusiveMediaPlayback.isLatestRequest(pending), isFalse);
    expect(ExclusiveMediaPlayback.isLatestRequest(resume), isFalse);
  });

  test('chỉ một lượt bấm thì tải xong vẫn được phát', () {
    final token = ExclusiveMediaPlayback.beginRequest();
    expect(ExclusiveMediaPlayback.isLatestRequest(token), isTrue);
  });
}
