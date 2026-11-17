import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/call_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_busy_policy.dart';

void main() {
  group('decideIncomingCall', () {
    test('không có cuộc gọi nào đang mở thì hiện hộp Cuộc gọi đến', () {
      expect(
        decideIncomingCall(callId: 'b', activeCallIds: const {}),
        IncomingCallDecision.show,
      );
    });

    test('màn gọi của chính cuộc đó đang mở thì không hiện lại hộp', () {
      expect(
        decideIncomingCall(callId: 'b', activeCallIds: const {'b'}),
        IncomingCallDecision.alreadyHandled,
      );
      expect(
        decideIncomingCall(callId: ' b ', activeCallIds: const {'b'}),
        IncomingCallDecision.alreadyHandled,
      );
    });

    test('giao diện gốc đã bấm nghe thì không hiện hộp', () {
      expect(
        decideIncomingCall(
          callId: 'b',
          activeCallIds: const {},
          nativeAcceptPending: true,
        ),
        IncomingCallDecision.alreadyHandled,
      );
    });

    test('đang mở màn gọi cuộc khác thì tự từ chối vì bận', () {
      expect(
        decideIncomingCall(callId: 'b', activeCallIds: const {'a'}),
        IncomingCallDecision.rejectBusy,
      );
    });

    test('mã rỗng thì bỏ qua', () {
      expect(
        decideIncomingCall(callId: '  ', activeCallIds: const {}),
        IncomingCallDecision.alreadyHandled,
      );
    });
  });

  group('decideNativeAccept', () {
    test('không có luồng nào thì mở màn gọi', () {
      expect(
        decideNativeAccept(
          callId: 'b',
          activeCallIds: const {},
          inAppFlowCallId: null,
        ),
        NativeAcceptRoute.openCallScreen,
      );
    });

    test('hộp trong app đang xử lý đúng cuộc đó thì giao cho hộp', () {
      expect(
        decideNativeAccept(
          callId: 'b',
          activeCallIds: const {},
          inAppFlowCallId: 'b',
        ),
        NativeAcceptRoute.handOverToInAppFlow,
      );
    });

    test('hộp trong app của cuộc khác không chặn việc mở màn gọi', () {
      expect(
        decideNativeAccept(
          callId: 'b',
          activeCallIds: const {},
          inAppFlowCallId: 'c',
        ),
        NativeAcceptRoute.openCallScreen,
      );
    });

    test('màn gọi đã mở thì chỉ xác nhận', () {
      expect(
        decideNativeAccept(
          callId: 'b',
          activeCallIds: const {'b'},
          inAppFlowCallId: 'b',
        ),
        NativeAcceptRoute.alreadyOpen,
      );
    });

    test('đang trong cuộc gọi khác thì từ chối bận', () {
      expect(
        decideNativeAccept(
          callId: 'b',
          activeCallIds: const {'a'},
          inAppFlowCallId: null,
        ),
        NativeAcceptRoute.rejectBusy,
      );
    });
  });

  group('startCallFailureMessage', () {
    Failure conflict(String code) =>
        Failure(kind: FailureKind.conflict, message: 'máy chủ', code: code);

    test('409 người nhận bận dùng câu thống nhất', () {
      expect(
        startCallFailureMessage(conflict('CALL_TARGET_BUSY')),
        'Người nhận đang bận trong cuộc gọi khác.',
      );
    });

    test('409 chính mình đang gọi dùng câu thống nhất', () {
      expect(
        startCallFailureMessage(conflict('call_initiator_busy')),
        'Bạn đang trong một cuộc gọi khác. Hãy kết thúc cuộc gọi đó trước.',
      );
    });

    test('lỗi khác giữ câu máy chủ trả', () {
      expect(startCallFailureMessage(conflict('OTHER')), 'máy chủ');
    });
  });
}
