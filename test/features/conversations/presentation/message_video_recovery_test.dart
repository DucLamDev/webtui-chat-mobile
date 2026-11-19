import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_media_widgets.dart';

void main() {
  final start = DateTime(2026, 11, 18, 9);

  test('trình phát dần lỗi thì khôi phục tối đa 2 lần mỗi phút', () {
    final budget = MessageVideoRecoveryBudget();
    MessageVideoErrorAction at(Duration offset) => messageVideoErrorAction(
      streamed: true,
      budget: budget,
      now: start.add(offset),
    );

    expect(at(Duration.zero), MessageVideoErrorAction.recover);
    expect(at(const Duration(seconds: 20)), MessageVideoErrorAction.recover);
    expect(
      at(const Duration(seconds: 40)),
      MessageVideoErrorAction.fail,
      reason: 'lần thứ ba trong một phút: báo lỗi, chờ người dùng thử lại',
    );
    // Một phút sau lần đầu: được khôi phục tiếp.
    expect(at(const Duration(seconds: 61)), MessageVideoErrorAction.recover);
    expect(at(const Duration(seconds: 62)), MessageVideoErrorAction.fail);
  });

  test('tệp trên máy lỗi thì không khôi phục (không tốn lượt)', () {
    final budget = MessageVideoRecoveryBudget();
    expect(
      messageVideoErrorAction(streamed: false, budget: budget, now: start),
      MessageVideoErrorAction.fail,
    );
    expect(budget.tryAcquire(start), isTrue);
    expect(budget.tryAcquire(start), isTrue);
    expect(budget.tryAcquire(start), isFalse);
  });

  test('video lớn tới mức gửi tối đa vẫn được tải về để xem', () {
    expect(
      attachmentPreviewWithinLimit(
        1500 * 1024 * 1024,
        maxBytes: maxVideoPlaybackBytes,
      ),
      isTrue,
    );
    expect(maxImageFullscreenBytes, greaterThan(maxImagePreviewBytes));
  });
}
