import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/incoming_call_policy.dart';

void main() {
  group('shouldRingForIncomingCall', () {
    test('đổ chuông khi mình là người được gọi', () {
      expect(
        shouldRingForIncomingCall(
          currentUserId: 'u-me',
          initiatorUserId: 'u-other',
          targetUserId: 'u-me',
        ),
        isTrue,
      );
    });

    test('không đổ chuông khi mình là người gọi (thiết bị khác)', () {
      expect(
        shouldRingForIncomingCall(
          currentUserId: 'u-me',
          initiatorUserId: 'u-me',
          targetUserId: 'u-other',
        ),
        isFalse,
      );
    });

    test('không đổ chuông khi người được gọi là người khác', () {
      expect(
        shouldRingForIncomingCall(
          currentUserId: 'u-me',
          initiatorUserId: 'u-a',
          targetUserId: 'u-b',
        ),
        isFalse,
      );
    });

    test('thiếu id người dùng thì giữ hành vi cũ', () {
      expect(
        shouldRingForIncomingCall(
          currentUserId: null,
          initiatorUserId: 'u-a',
          targetUserId: 'u-b',
        ),
        isTrue,
      );
      expect(
        shouldRingForIncomingCall(
          currentUserId: ' ',
          initiatorUserId: 'u-a',
          targetUserId: 'u-b',
        ),
        isTrue,
      );
    });

    test('máy chủ không trả người được gọi thì không chặn', () {
      expect(
        shouldRingForIncomingCall(
          currentUserId: 'u-me',
          initiatorUserId: 'u-a',
          targetUserId: '',
        ),
        isTrue,
      );
    });
  });
}
