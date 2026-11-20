import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/notifications/native_incoming_call_service.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/call_connection_policy.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';

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

  group('callerRecoveryShouldWait', () {
    test('offer khởi động lại đã gửi được, đang chờ answer: nhường', () {
      expect(
        callerRecoveryShouldWait(
          iceRestartRunning: false,
          awaitingAnswer: true,
          lastOfferSendFailed: false,
        ),
        isTrue,
      );
    });

    test('gửi offer lỗi (vừa đổi mạng): không nhường, tạo offer mới', () {
      expect(
        callerRecoveryShouldWait(
          iceRestartRunning: false,
          awaitingAnswer: true,
          lastOfferSendFailed: true,
        ),
        isFalse,
      );
    });

    test('đang xếp / chạy khởi động lại ICE: luôn nhường', () {
      expect(
        callerRecoveryShouldWait(
          iceRestartRunning: true,
          awaitingAnswer: false,
          lastOfferSendFailed: true,
        ),
        isTrue,
      );
      expect(
        callerRecoveryShouldWait(
          iceRestartRunning: false,
          awaitingAnswer: false,
          lastOfferSendFailed: false,
        ),
        isFalse,
      );
    });
  });

  group('callerRenegotiateAction', () {
    test('ice_restart: khởi động lại ICE dù máy này chưa thấy mất kết nối', () {
      for (final reconnecting in [false, true]) {
        expect(
          callerRenegotiateAction(
            reason: callRenegotiateIceRestartReason,
            reconnecting: reconnecting,
          ),
          CallRenegotiateAction.iceRestart,
        );
      }
    });

    test('video: thương lượng lại, kể cả khi đang khôi phục (không nuốt)', () {
      for (final reconnecting in [false, true]) {
        expect(
          callerRenegotiateAction(reason: 'video', reconnecting: reconnecting),
          CallRenegotiateAction.renegotiate,
        );
      }
    });

    test('bản cũ không có lý do: như cũ, đang khôi phục thì làm cả hai', () {
      expect(
        callerRenegotiateAction(reason: null, reconnecting: false),
        CallRenegotiateAction.renegotiate,
      );
      expect(
        callerRenegotiateAction(reason: ' ', reconnecting: true),
        CallRenegotiateAction.renegotiateAndIceRestart,
      );
    });
  });

  group('callAbortTerminatesServerCall', () {
    test('cuộc gọi đến chưa nhận trên máy này: không từ chối hộ', () {
      expect(
        callAbortTerminatesServerCall(incoming: true, acceptedHere: false),
        isFalse,
      );
    });

    test('đã nhận / cuộc gọi đi: kết thúc trên máy chủ', () {
      expect(
        callAbortTerminatesServerCall(incoming: true, acceptedHere: true),
        isTrue,
      );
      expect(
        callAbortTerminatesServerCall(incoming: false, acceptedHere: false),
        isTrue,
      );
    });
  });

  group('incomingLookupFailureAction', () {
    test('chưa bấm nghe native: giữ chuông', () {
      expect(
        incomingLookupFailureAction(
          nativeAccepted: false,
          hasCallContext: true,
          retriesUsed: 0,
        ),
        IncomingLookupFailureAction.keepRinging,
      );
    });

    test('đã bấm nghe native, đủ thông tin: mở màn gọi luôn', () {
      expect(
        incomingLookupFailureAction(
          nativeAccepted: true,
          hasCallContext: true,
          retriesUsed: incomingNativeAcceptMaxRetries,
        ),
        IncomingLookupFailureAction.openCallScreen,
      );
    });

    test('đã bấm nghe native, thiếu thông tin: thử lại có giới hạn', () {
      expect(
        incomingLookupFailureAction(
          nativeAccepted: true,
          hasCallContext: false,
          retriesUsed: 0,
        ),
        IncomingLookupFailureAction.retryLater,
      );
      expect(
        incomingLookupFailureAction(
          nativeAccepted: true,
          hasCallContext: false,
          retriesUsed: incomingNativeAcceptMaxRetries,
        ),
        IncomingLookupFailureAction.giveUp,
      );
    });
  });

  test('tải ICE servers khi khôi phục có hạn ngắn, trong hạn kết thúc', () {
    expect(
      CallRecoveryPolicy.iceServersFetchTimeout,
      lessThan(CallRecoveryPolicy.retryInterval),
    );
    expect(
      CallRecoveryPolicy.actionDelay +
          CallRecoveryPolicy.iceServersFetchTimeout,
      lessThan(CallRecoveryPolicy.giveUpAfter(incoming: false)),
    );
  });

  group('CallStatePolling', () {
    test(
      'màn gọi hỏi máy chủ 5 giây một lần, vẫn trong cửa sổ bận 90 giây',
      () {
        expect(
          CallStatePolling.callScreenSyncInterval,
          const Duration(seconds: 5),
        );
        // Máy chủ ghi `last_active_at` tối đa 10 giây một lần, coi còn bận
        // trong 90 giây: nhịp hỏi phải dày hơn nhiều.
        expect(
          CallStatePolling.callScreenSyncInterval,
          lessThanOrEqualTo(const Duration(seconds: 10)),
        );
        expect(
          CallStatePolling.durationTickInterval,
          const Duration(seconds: 1),
        );
      },
    );

    test('hộp "Cuộc gọi đến" hỏi máy chủ mỗi 2 nhịp, lượt đầu sau 1 giây', () {
      final checked = [
        for (var tick = 1; tick <= 30; tick++)
          if (CallStatePolling.incomingDialogShouldCheck(tick)) tick,
      ];
      expect(checked.first, 1);
      expect(checked.take(4), [1, 3, 5, 7]);
      expect(checked, hasLength(15));
      expect(CallStatePolling.incomingDialogShouldCheck(0), isFalse);
    });
  });

  group('callElapsed', () {
    final start = DateTime.utc(2026, 11, 19, 8);

    test('chưa bắt đầu thì 0', () {
      expect(callElapsed(startedAt: null, now: start), Duration.zero);
    });

    test('tính theo giờ bắt đầu, chạy mỗi giây không cần hỏi máy chủ', () {
      expect(
        callElapsed(
          startedAt: start,
          now: start.add(const Duration(seconds: 1)),
        ),
        const Duration(seconds: 1),
      );
      expect(
        callElapsed(
          startedAt: start,
          now: start.add(const Duration(minutes: 2, seconds: 7)),
        ),
        const Duration(minutes: 2, seconds: 7),
      );
    });

    test('giờ máy lệch (bắt đầu "trong tương lai") thì 0, không âm', () {
      expect(
        callElapsed(
          startedAt: start,
          now: start.subtract(const Duration(seconds: 3)),
        ),
        Duration.zero,
      );
    });

    test('giờ địa phương và UTC cho cùng kết quả', () {
      expect(
        callElapsed(
          startedAt: start.toLocal(),
          now: start.add(const Duration(seconds: 42)),
        ),
        const Duration(seconds: 42),
      );
    });
  });

  group('reconcileCallStatus', () {
    test('lượt hỏi cũ báo "ringing" không kéo lùi trạng thái đã nhận', () {
      expect(
        reconcileCallStatus(
          local: CallStatus.accepted,
          server: CallStatus.ringing,
        ),
        CallStatus.accepted,
      );
    });

    test('các trường hợp khác theo máy chủ', () {
      expect(
        reconcileCallStatus(
          local: CallStatus.ringing,
          server: CallStatus.accepted,
        ),
        CallStatus.accepted,
      );
      expect(
        reconcileCallStatus(
          local: CallStatus.ringing,
          server: CallStatus.ringing,
        ),
        CallStatus.ringing,
      );
      expect(
        reconcileCallStatus(
          local: CallStatus.accepted,
          server: CallStatus.ended,
        ),
        CallStatus.ended,
      );
    });
  });

  group('callRealtimeLifecycleAction', () {
    CallRealtimeLifecycleAction action(
      ConversationRealtimeEventType type, {
      String? eventCallId = 'call-1',
      bool incoming = false,
      bool fromCurrentUser = false,
      String? answeredDeviceId,
      String? localDeviceId = 'device-a',
    }) {
      return callRealtimeLifecycleAction(
        type: type,
        eventCallId: eventCallId,
        callId: 'call-1',
        incoming: incoming,
        fromCurrentUser: fromCurrentUser,
        answeredDeviceId: answeredDeviceId,
        localDeviceId: localDeviceId,
      );
    }

    test(
      'realtime nối lại: hỏi máy chủ ngay (sự kiện không có mã cuộc gọi)',
      () {
        expect(
          action(ConversationRealtimeEventType.reconnected, eventCallId: null),
          CallRealtimeLifecycleAction.resync,
        );
        expect(
          action(ConversationRealtimeEventType.reconnected, incoming: true),
          CallRealtimeLifecycleAction.resync,
        );
      },
    );

    test('gọi đi: bên kia nhận máy thì chuyển trạng thái ngay', () {
      expect(
        action(
          ConversationRealtimeEventType.callAccepted,
          answeredDeviceId: 'device-callee',
        ),
        CallRealtimeLifecycleAction.accepted,
      );
    });

    test('gọi đi: bỏ sự kiện nhận máy của cuộc gọi khác / của chính mình', () {
      expect(
        action(
          ConversationRealtimeEventType.callAccepted,
          eventCallId: 'call-2',
        ),
        CallRealtimeLifecycleAction.none,
      );
      expect(
        action(
          ConversationRealtimeEventType.callAccepted,
          fromCurrentUser: true,
        ),
        CallRealtimeLifecycleAction.none,
      );
    });

    test(
      'gọi đến: đã nghe ở máy khác thì đóng màn (kể cả sự kiện của mình)',
      () {
        for (final type in [
          ConversationRealtimeEventType.callAnsweredElsewhere,
          ConversationRealtimeEventType.callAccepted,
        ]) {
          expect(
            action(
              type,
              incoming: true,
              fromCurrentUser: true,
              answeredDeviceId: 'device-b',
            ),
            CallRealtimeLifecycleAction.answeredElsewhere,
            reason: '$type',
          );
        }
      },
    );

    test('gọi đến: chính máy này nhận / thiếu mã máy thì không đóng màn', () {
      expect(
        action(
          ConversationRealtimeEventType.callAnsweredElsewhere,
          incoming: true,
          answeredDeviceId: 'device-a',
        ),
        CallRealtimeLifecycleAction.none,
      );
      expect(
        action(
          ConversationRealtimeEventType.callAccepted,
          incoming: true,
          fromCurrentUser: true,
          answeredDeviceId: 'device-a',
        ),
        CallRealtimeLifecycleAction.none,
      );
      expect(
        action(
          ConversationRealtimeEventType.callAnsweredElsewhere,
          incoming: true,
        ),
        CallRealtimeLifecycleAction.none,
      );
      expect(
        action(
          ConversationRealtimeEventType.callAnsweredElsewhere,
          incoming: true,
          answeredDeviceId: 'device-b',
          localDeviceId: null,
        ),
        CallRealtimeLifecycleAction.none,
      );
    });

    test(
      'gọi đến: không đổi trạng thái theo CallAccepted (máy này tự nhận)',
      () {
        expect(
          action(
            ConversationRealtimeEventType.callAccepted,
            incoming: true,
            answeredDeviceId: null,
          ),
          CallRealtimeLifecycleAction.none,
        );
      },
    );

    test('đã nghe ở máy khác của cuộc gọi khác: bỏ qua', () {
      expect(
        action(
          ConversationRealtimeEventType.callAnsweredElsewhere,
          eventCallId: 'call-2',
          incoming: true,
          answeredDeviceId: 'device-b',
        ),
        CallRealtimeLifecycleAction.none,
      );
    });

    test('gọi đi: CallAnsweredElsewhere không đóng màn', () {
      expect(
        action(
          ConversationRealtimeEventType.callAnsweredElsewhere,
          answeredDeviceId: 'device-b',
        ),
        CallRealtimeLifecycleAction.none,
      );
    });

    test('tín hiệu WebRTC / sự kiện kết thúc: không có việc riêng', () {
      for (final type in [
        ConversationRealtimeEventType.callOffer,
        ConversationRealtimeEventType.callEnded,
        ConversationRealtimeEventType.callCancelled,
      ]) {
        expect(action(type), CallRealtimeLifecycleAction.none, reason: '$type');
      }
    });
  });
}
