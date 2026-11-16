import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/router/notification_locations.dart';
import 'package:webtui_chat/core/notifications/scoped_local_notification_service.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/meeting_calendar/application/meeting_calendar_providers.dart';
import 'package:webtui_chat/features/meeting_calendar/presentation/controllers/meeting_calendar_controllers.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

import 'meeting_calendar_fakes.dart';

const _instanceId = '7b0f8f3e-5c1a-4d2b-9e8f-1a2b3c4d5e6f';

Map<String, Object?> _push(String type, {String? meetingId = 'm1'}) => {
  'instance_id': _instanceId,
  'workspace_id': 'ws-1',
  'notification_id': 'n-$type',
  'type': type,
  'channel_id': 'ch-1',
  'meeting_id': ?meetingId,
  if (type == 'meeting_reminder') ...{
    'starts_at': '2026-11-18T02:00:00Z',
    'minutes_before': '15',
  },
  if (type == 'meeting_updated') 'change': 'rescheduled',
  'title': 'Sắp họp: «Họp tuần»',
  'body': 'Bắt đầu lúc 09:00',
};

void main() {
  group('thông báo đẩy họp', () {
    for (final type in const ['meeting_reminder', 'meeting_updated']) {
      test('$type: bấm mở chi tiết cuộc họp', () {
        final target = NotificationTarget.fromPayload(
          workspaceId: 'ws-1',
          data: _push(type),
        );
        expect(target.isMeeting, isTrue);
        expect(target.meetingId, 'm1');
        expect(
          locationForNotificationTarget(target),
          '/meetings/m1?workspaceId=ws-1&channelId=ch-1',
        );
      });
    }

    test('thiếu meeting_id: mở phòng chat như thông báo thường', () {
      final target = NotificationTarget.fromPayload(
        workspaceId: 'ws-1',
        data: _push('meeting_reminder', meetingId: null),
      );
      expect(target.isMeeting, isFalse);
      expect(
        locationForNotificationTarget(target),
        startsWith('/conversations/ch-1'),
      );
    });

    test('thông báo khác không bị coi là họp dù có meeting_id', () {
      final target = NotificationTarget.fromPayload(
        workspaceId: 'ws-1',
        data: {..._push('meeting_reminder'), 'type': 'message'},
      );
      expect(target.isMeeting, isFalse);
    });

    test('thông báo hiện trên máy (app tắt) giữ đủ thông tin để mở họp', () {
      final routing = scopedNotificationRoutingData(_push('meeting_reminder'));
      expect(routing, isNotNull);
      expect(routing, containsPair('type', 'meeting_reminder'));
      expect(routing, containsPair('meeting_id', 'm1'));
      expect(routing, containsPair('channel_id', 'ch-1'));

      final local = ScopedLocalNotification.fromData(_push('meeting_reminder'));
      expect(local.canQuickReply, isFalse, reason: 'không trả lời nhanh');
      final decoded = decodeScopedNotificationRoutingPayload(
        local.encodedRoutingPayload,
      )!;
      final reopened = NotificationTarget.fromPayload(
        workspaceId: 'ws-1',
        data: decoded,
      );
      expect(
        locationForNotificationTarget(reopened),
        '/meetings/m1?workspaceId=ws-1&channelId=ch-1',
      );
    });
  });

  group('sự kiện MeetingUpdated', () {
    test('đọc từ WebSocket, giữ payload', () {
      final event = ConversationRealtimeEventMapper.fromSocketData(
        jsonEncode({
          'type': 'MeetingUpdated',
          'room': 'user:u1',
          'payload': {
            'workspace_id': 'w1',
            'channel_id': 'c1',
            'meeting_id': 'm1',
            'series_id': null,
            'change': 'cancelled',
          },
        }),
        fallbackWorkspaceId: 'w1',
        fallbackChannelId: '',
      )!;
      expect(event.type, ConversationRealtimeEventType.meetingUpdated);
      expect(event.channelId, 'c1');
      expect(event.payload['meeting_id'], 'm1');
      expect(event.payload['change'], 'cancelled');
    });

    test('làm mới danh sách và chi tiết đang mở', () async {
      final repository = FakeMeetingCalendarRepository(
        meetings: [fakeMeeting('m1', startsAt: DateTime(2026, 11, 18, 9))],
      );
      final container = ProviderContainer(
        overrides: [
          meetingCalendarRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final rangeKey = (
        workspaceId: 'ws',
        from: DateTime(2026, 11, 16),
        to: DateTime(2026, 11, 23),
      );
      const detailKey = (workspaceId: 'ws', channelId: 'c1', meetingId: 'm1');
      final range = container.listen(meetingRangeProvider(rangeKey), (_, _) {});
      final detail = container.listen(
        meetingDetailProvider(detailKey),
        (_, _) {},
      );
      addTearDown(range.close);
      addTearDown(detail.close);
      await container.read(meetingRangeProvider(rangeKey).future);
      await container.read(meetingDetailProvider(detailKey).future);
      expect(repository.calls, ['list', 'get:c1/m1']);

      const other = ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.channelUpdated,
        workspaceId: 'ws',
        channelId: 'c1',
      );
      expect(
        handleMeetingRealtimeEvent(read: container.read, event: other),
        isFalse,
      );
      const event = ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.meetingUpdated,
        workspaceId: 'ws',
        channelId: 'c1',
      );
      expect(
        handleMeetingRealtimeEvent(read: container.read, event: event),
        isTrue,
      );
      await container.read(meetingRangeProvider(rangeKey).future);
      await container.read(meetingDetailProvider(detailKey).future);
      expect(repository.calls, ['list', 'get:c1/m1', 'list', 'get:c1/m1']);
    });
  });
}
