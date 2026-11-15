import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/incoming_call_ring_gate.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/call_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/call_repository.dart';

CallSession _call({
  String id = 'call-1',
  String initiator = 'u-caller',
  String target = 'u-callee',
  String? clientCallId,
  String? initiatorDeviceId,
}) {
  final now = DateTime.utc(2026, 11, 15);
  return CallSession(
    id: id,
    workspaceId: 'ws-1',
    channelId: 'ch-1',
    initiatorUserId: initiator,
    targetUserId: target,
    clientCallId: clientCallId,
    mode: CallMode.video,
    status: CallStatus.ringing,
    createdAt: now,
    updatedAt: now,
    initiatorDeviceId: initiatorDeviceId,
  );
}

IncomingCallRingGate _gate({
  required OutgoingCallRegistry registry,
  String? userId,
  String? deviceId,
  bool userIdFails = false,
}) {
  return IncomingCallRingGate(
    outgoingCalls: registry,
    resolveCurrentUserId: () async {
      if (userIdFails) throw StateError('mạng lỗi');
      return userId;
    },
    resolveLocalDeviceId: () async => deviceId,
  );
}

void main() {
  group('IncomingCallRingGate', () {
    test('người gọi trên máy tạo cuộc: không đổ chuông', () async {
      final registry = OutgoingCallRegistry()..rememberCall('call-1');
      final gate = _gate(registry: registry, userIdFails: true);
      expect(gate.isOwnOutgoingCall('call-1'), isTrue);
      expect(await gate.shouldRing(_call()), isFalse);
    });

    test('CallInvited tới trước kết quả tạo: khớp client_call_id', () async {
      final registry = OutgoingCallRegistry()..rememberClientCallId('cc-1');
      final gate = _gate(registry: registry, userIdFails: true);
      expect(await gate.shouldRing(_call(clientCallId: 'cc-1')), isFalse);
    });

    test('initiator_device_id trùng mã máy: không đổ chuông', () async {
      final gate = _gate(
        registry: OutgoingCallRegistry(),
        userIdFails: true,
        deviceId: 'dev-a',
      );
      expect(await gate.shouldRing(_call(initiatorDeviceId: 'dev-a')), isFalse);
    });

    test('người gọi trên máy khác cùng tài khoản: không đổ chuông', () async {
      final gate = _gate(
        registry: OutgoingCallRegistry(),
        userId: 'u-caller',
        deviceId: 'dev-phone',
      );
      expect(
        await gate.shouldRing(_call(initiatorDeviceId: 'dev-browser')),
        isFalse,
      );
    });

    test('người nhận: đổ chuông (mọi máy của người nhận)', () async {
      for (final device in ['dev-1', 'dev-2', null]) {
        final gate = _gate(
          registry: OutgoingCallRegistry(),
          userId: 'u-callee',
          deviceId: device,
        );
        expect(
          await gate.shouldRing(_call(initiatorDeviceId: 'dev-caller')),
          isTrue,
        );
      }
    });

    test('người nhận vẫn đổ chuông khi không lấy được id người dùng', () async {
      final gate = _gate(
        registry: OutgoingCallRegistry(),
        userIdFails: true,
        deviceId: 'dev-callee',
      );
      expect(
        await gate.shouldRing(_call(initiatorDeviceId: 'dev-caller')),
        isTrue,
      );
    });
  });

  group('OutgoingCallRegistry', () {
    test('phát call_id mới một lần và giới hạn kích thước', () async {
      final registry = OutgoingCallRegistry(limit: 2);
      final seen = <String>[];
      registry.registered.listen(seen.add);
      registry
        ..rememberCall('a')
        ..rememberCall('a')
        ..rememberCall('b')
        ..rememberCall('c');
      expect(seen, ['a', 'b', 'c']);
      expect(registry.isOutgoing(callId: 'a'), isFalse);
      expect(registry.isOutgoing(callId: 'c'), isTrue);
      await registry.dispose();
    });
  });

  group('StartCallUseCase', () {
    test('ghi client_call_id trước khi gửi và call_id sau khi tạo', () async {
      final registry = OutgoingCallRegistry();
      final repository = _RecordingCallRepository(registry);
      final useCase = StartCallUseCase(
        repository,
        uuid: const Uuid(),
        outgoingCalls: registry,
      );
      final result = await useCase.execute(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        targetUserId: 'u-callee',
        mode: CallMode.audio,
      );
      expect(result.isSuccess, isTrue);
      expect(repository.clientCallIdKnownBeforeCreate, isTrue);
      expect(registry.isOutgoing(callId: 'call-new'), isTrue);
    });
  });
}

final class _RecordingCallRepository implements CallRepository {
  _RecordingCallRepository(this._registry);

  final OutgoingCallRegistry _registry;
  bool clientCallIdKnownBeforeCreate = false;

  @override
  Future<Result<CallSession>> createCall({
    required String workspaceId,
    required String channelId,
    required String targetUserId,
    required CallMode mode,
    required String clientCallId,
    Map<String, Object?> metadata = const {},
    String? deviceId,
  }) async {
    clientCallIdKnownBeforeCreate = _registry.isOutgoing(
      clientCallId: clientCallId,
    );
    return Success(_call(id: 'call-new', clientCallId: clientCallId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
