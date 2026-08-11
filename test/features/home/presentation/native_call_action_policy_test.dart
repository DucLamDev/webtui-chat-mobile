import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';
import 'package:webtui_chat/features/home/presentation/screens/home_shell_screen.dart';

void main() {
  test(
    'late decline and timeout never hang up a cross-device accepted call',
    () {
      expect(
        nativeRejectActionIsStaleAfterAcceptance(
          reason: 'declined',
          currentStatus: CallStatus.accepted,
        ),
        isTrue,
      );
      expect(
        nativeRejectActionIsStaleAfterAcceptance(
          reason: 'timeout',
          currentStatus: CallStatus.accepted,
        ),
        isTrue,
      );
    },
  );

  test('decline still rejects a call that remains ringing', () {
    expect(
      nativeRejectActionIsStaleAfterAcceptance(
        reason: 'declined',
        currentStatus: CallStatus.ringing,
      ),
      isFalse,
    );
  });

  test('explicit ended action still terminates an accepted call', () {
    expect(
      nativeRejectActionIsStaleAfterAcceptance(
        reason: 'ended',
        currentStatus: CallStatus.accepted,
      ),
      isFalse,
    );
  });
}
