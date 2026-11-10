import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/notifications/native_incoming_call_service.dart';
import 'package:webtui_chat/features/conversations/data/datasources/call_remote_data_source.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_device_routing.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

void main() {
  test('máy khác bỏ qua tín hiệu, VoIP vẫn là cùng máy', () {
    expect(
      callAnsweredOnAnotherDevice(
        answeredDeviceId: 'phone',
        localDeviceId: 'web',
      ),
      isTrue,
    );
    expect(
      callAnsweredOnThisDevice(
        answeredDeviceId: 'phone',
        localDeviceId: 'phone:voip',
      ),
      isTrue,
    );
    expect(
      callAnsweredOnAnotherDevice(
        answeredDeviceId: null,
        localDeviceId: 'phone',
      ),
      isFalse,
    );
    expect(
      callSignalTargetsAnotherDevice(
        targetDeviceId: 'phone',
        localDeviceId: 'web',
      ),
      isTrue,
    );
    expect(
      callSignalTargetsAnotherDevice(
        targetDeviceId: 'phone',
        localDeviceId: null,
      ),
      isTrue,
    );
    expect(
      callSignalTargetsAnotherDevice(
        targetDeviceId: null,
        localDeviceId: 'web',
      ),
      isFalse,
    );
  });

  test('push nhận ở máy khác dừng chuông nhưng giữ máy đang nghe', () {
    final target = NotificationTarget.fromPayload(
      workspaceId: 'ws',
      data: {
        'target_type': 'call',
        'call_id': 'call',
        'event_type': 'call_answered_elsewhere',
        'status': 'accepted',
        'answered_device_id': 'phone',
      },
    );
    expect(
      NativeIncomingCallService.isTerminalCallTarget(
        target,
        localDeviceId: 'web',
      ),
      isTrue,
    );
    expect(
      NativeIncomingCallService.isTerminalCallTarget(
        target,
        localDeviceId: 'phone',
      ),
      isFalse,
    );
    expect(
      NativeIncomingCallService.isTerminalCallTarget(
        target,
        localDeviceId: 'phone:voip',
      ),
      isFalse,
    );
  });

  test(
    'accept gửi mã máy, đọc máy đã nhận và vẫn đọc được máy chủ cũ',
    () async {
      final transport = _Transport();
      final source = CallRemoteDataSource(transport);
      final call = await source.changeStatus(
        workspaceId: 'ws',
        callId: 'call',
        action: 'accept',
        deviceId: ' phone ',
      );
      expect(transport.path, '/api/v1/workspaces/ws/calls/call/accept');
      expect(transport.body, {'device_id': 'phone'});
      expect(call.answeredDeviceId, 'phone');
      expect(call.answeredAt, DateTime.utc(2026, 11, 10));
      transport.legacy = true;
      final old = await source.changeStatus(
        workspaceId: 'ws',
        callId: 'call',
        action: 'accept',
      );
      expect(transport.body, isEmpty);
      expect(old.answeredDeviceId, isNull);
    },
  );

  test('khử trùng có giới hạn và vẫn nhận sự kiện không có mã', () {
    final seen = RecentRealtimeEventIds(capacity: 2);
    expect(seen.markSeen('a'), isTrue);
    expect(seen.markSeen('a'), isFalse);
    expect(seen.markSeen(null), isTrue);
    expect(seen.markSeen(null), isTrue);
    seen.markSeen('b');
    seen.markSeen('c');
    expect(seen.markSeen('a'), isTrue);
    seen.clear();
    expect(seen.markSeen('a'), isTrue);
  });
}

final class _Transport implements ApiTransport {
  String? path;
  Object? body;
  bool legacy = false;
  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    body = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data:
          {
                'data': {
                  'call': {
                    'id': 'call',
                    'workspace_id': 'ws',
                    'status': 'accepted',
                    if (!legacy) 'answered_device_id': 'phone',
                    if (!legacy) 'answered_at': '2026-11-10T00:00:00Z',
                  },
                },
              }
              as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
