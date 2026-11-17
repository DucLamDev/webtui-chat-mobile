import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/call_tone_player.dart';
import 'package:webtui_chat/features/conversations/application/call_end_cue.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';

void main() {
  test('mình gác máy: tiếng kết thúc (gọi đi lẫn gọi đến)', () {
    for (final incoming in [true, false]) {
      expect(
        callEndCue(incoming: incoming, status: null, localHangup: true),
        CallCue.ended,
      );
    }
  });

  test('gọi đi hết giờ không ai bắt máy: lời báo không liên lạc được', () {
    expect(
      callEndCue(incoming: false, status: CallStatus.missed),
      CallCue.unreachable,
    );
    expect(callEndCue(incoming: true, status: CallStatus.missed), isNull);
  });

  test('kết thúc / bị từ chối / bị huỷ: tiếng kết thúc', () {
    for (final status in [
      CallStatus.ended,
      CallStatus.rejected,
      CallStatus.cancelled,
    ]) {
      expect(callEndCue(incoming: false, status: status), CallCue.ended);
      expect(callEndCue(incoming: true, status: status), CallCue.ended);
    }
  });

  test('lỗi kỹ thuật hoặc chưa kết thúc: im', () {
    expect(callEndCue(incoming: false, status: null), isNull);
    expect(callEndCue(incoming: false, status: CallStatus.ringing), isNull);
    expect(callEndCue(incoming: true, status: CallStatus.accepted), isNull);
  });
}
