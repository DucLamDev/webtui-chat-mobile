import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/notifications/native_incoming_call_service.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/call_connection_policy.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';

CallSession _call(CallStatus status) {
  final now = DateTime.utc(2026, 11, 18);
  return CallSession(
    id: 'call-1',
    workspaceId: 'ws-1',
    channelId: 'ch-1',
    initiatorUserId: 'u-caller',
    targetUserId: 'u-callee',
    mode: CallMode.audio,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

Result<CallSession> _failure(FailureKind kind) =>
    FailureResult<CallSession>(Failure(kind: kind, message: 'x'));

void main() {
  group('SerialTaskQueue', () {
    test('chạy lần lượt, bước sau chỉ bắt đầu khi bước trước xong', () async {
      final queue = SerialTaskQueue();
      final log = <String>[];
      final gate = Completer<void>();
      final first = queue.run(() async {
        log.add('a:start');
        await gate.future;
        log.add('a:end');
      });
      final second = queue.run(() async {
        log.add('b');
      });
      await Future<void>.delayed(Duration.zero);
      expect(log, ['a:start']);
      gate.complete();
      await Future.wait([first, second]);
      expect(log, ['a:start', 'a:end', 'b']);
    });

    test('bước lỗi chỉ trả lỗi cho chính nó, không chặn bước sau', () async {
      final queue = SerialTaskQueue();
      final failing = queue.run<void>(() async => throw StateError('hỏng'));
      final next = queue.run(() async => 42);
      await expectLater(failing, throwsStateError);
      expect(await next, 42);
    });

    test('đã đóng: bỏ các bước đang chờ và bước mới', () async {
      final queue = SerialTaskQueue();
      final gate = Completer<void>();
      var ran = false;
      final first = queue.run(() => gate.future);
      final pending = queue.run(() async => ran = true);
      queue.close();
      gate.complete();
      await first;
      expect(await pending, isNull);
      expect(await queue.run(() async => 1), isNull);
      expect(ran, isFalse);
      expect(queue.isClosed, isTrue);
    });
  });

  group('SignalResendBudget', () {
    test('cho gửi lại đúng số lần tối đa rồi dừng', () {
      final budget = SignalResendBudget(maxResends: 3);
      expect(
        [for (var i = 0; i < 5; i++) budget.tryConsume()],
        [true, true, true, false, false],
      );
      expect(budget.exhausted, isTrue);
      budget.reset();
      expect(budget.tryConsume(), isTrue);
    });

    test('nhịp gửi lại theo yêu cầu', () {
      expect(CallSignalTiming.readyResendInterval, const Duration(seconds: 3));
      expect(CallSignalTiming.readyMaxResends, 5);
      expect(CallSignalTiming.offerAnswerTimeout, const Duration(seconds: 5));
      expect(CallSignalTiming.offerMaxResends, 3);
      expect(
        CallSignalTiming.iceRestartAnswerTimeout,
        const Duration(seconds: 4),
      );
      expect(CallSignalTiming.iceRestartMaxResends, 3);
      expect(CallSignalTiming.candidateMaxAttempts, 2);
    });
  });

  group('CallRecoveryPolicy', () {
    test('bên nhận chờ 30 giây, lâu hơn bên gọi', () {
      expect(
        CallRecoveryPolicy.giveUpAfter(incoming: true),
        const Duration(seconds: 30),
      );
      expect(
        CallRecoveryPolicy.giveUpAfter(incoming: false) <
            CallRecoveryPolicy.giveUpAfter(incoming: true),
        isTrue,
      );
    });

    test('mọi lượt thử khôi phục nằm trong hạn kết thúc', () {
      final lastAttempt =
          CallRecoveryPolicy.actionDelay +
          CallRecoveryPolicy.retryInterval *
              (CallRecoveryPolicy.maxRecoveryActions - 1);
      expect(
        lastAttempt < CallRecoveryPolicy.giveUpAfter(incoming: false),
        isTrue,
      );
      expect(CallRecoveryPolicy.actionDelay, const Duration(seconds: 3));
    });
  });

  group('callHeaderPhase', () {
    test('máy chủ đã nhận nhưng WebRTC chưa thông: vẫn "Đang kết nối"', () {
      expect(
        callHeaderPhase(
          serverAccepted: true,
          mediaConnectedOnce: false,
          reconnecting: false,
        ),
        CallHeaderPhase.connecting,
      );
      // Lỗi trước lần nối đầu tiên không hiện "Đang khôi phục".
      expect(
        callHeaderPhase(
          serverAccepted: true,
          mediaConnectedOnce: false,
          reconnecting: true,
        ),
        CallHeaderPhase.connecting,
      );
    });

    test('đã thông: hiện thời lượng; mất kết nối: đang khôi phục', () {
      expect(
        callHeaderPhase(
          serverAccepted: true,
          mediaConnectedOnce: true,
          reconnecting: false,
        ),
        CallHeaderPhase.active,
      );
      expect(
        callHeaderPhase(
          serverAccepted: true,
          mediaConnectedOnce: true,
          reconnecting: true,
        ),
        CallHeaderPhase.reconnecting,
      );
    });
  });

  group('classifyCallLookup', () {
    test('lỗi mạng / hết giờ / máy chủ 5xx là tạm thời', () {
      for (final kind in [
        FailureKind.network,
        FailureKind.timeout,
        FailureKind.server,
        FailureKind.rateLimited,
      ]) {
        expect(
          classifyCallLookup(_failure(kind)),
          CallLookupOutcome.transientError,
          reason: kind.name,
        );
      }
    });

    test('404 / 403 / trạng thái kết thúc là đã kết thúc', () {
      expect(
        classifyCallLookup(_failure(FailureKind.notFound)),
        CallLookupOutcome.gone,
      );
      expect(
        classifyCallLookup(_failure(FailureKind.forbidden)),
        CallLookupOutcome.gone,
      );
      for (final status in [
        CallStatus.ended,
        CallStatus.cancelled,
        CallStatus.missed,
        CallStatus.rejected,
      ]) {
        expect(
          classifyCallLookup(Success(_call(status))),
          CallLookupOutcome.gone,
        );
      }
    });

    test('còn đổ chuông / đã nhận', () {
      expect(
        classifyCallLookup(Success(_call(CallStatus.ringing))),
        CallLookupOutcome.ringing,
      );
      expect(
        classifyCallLookup(Success(_call(CallStatus.accepted))),
        CallLookupOutcome.accepted,
      );
    });
  });

  group('Tắt tiếng từ CallKit', () {
    test('đọc sự kiện ACTION_CALL_TOGGLE_MUTE', () {
      final change = NativeIncomingCallService.muteChangeFromCallkitEvent(
        const CallEventActionCallToggleMute('ABC-123', true),
      );
      expect(change, isNotNull);
      expect(change!.muted, isTrue);
      // iOS có thể trả mã chữ hoa.
      expect(change.matches('abc-123'), isTrue);
      expect(change.matches('khac'), isFalse);
    });

    test('bỏ qua sự kiện khác hoặc thiếu mã', () {
      expect(
        NativeIncomingCallService.muteChangeFromCallkitEvent(
          const CallEventActionCallToggleMute('  ', false),
        ),
        isNull,
      );
      expect(
        NativeIncomingCallService.muteChangeFromCallkitEvent(
          const CallEventActionCallToggleHold('call-1', true),
        ),
        isNull,
      );
      expect(
        NativeIncomingCallService.muteChangeFromCallkitEvent(null),
        isNull,
      );
    });
  });
}
