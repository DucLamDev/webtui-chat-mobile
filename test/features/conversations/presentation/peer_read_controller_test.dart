import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_read_controller.dart';

const _scope = ChatRoomScope(
  workspaceId: 'ws',
  channelId: 'ch',
  title: 'Phòng',
);

ChatMessage _message(
  String id,
  DateTime at, {
  bool mine = true,
  String status = '',
  DateTime? deletedAt,
}) {
  return ChatMessage(
    id: id,
    workspaceId: 'ws',
    channelId: 'ch',
    kind: 'text',
    body: id,
    createdAt: at,
    isMine: mine,
    deletedAt: deletedAt,
    metadata: status.isEmpty ? const {} : {'delivery_status': status},
  );
}

ChannelMember _member(
  String userId, {
  DateTime? readAt,
  String status = 'active',
}) {
  return ChannelMember(
    channelId: 'ch',
    userId: userId,
    email: '$userId@example.test',
    username: userId,
    displayName: userId,
    status: status,
    joinedAt: DateTime.utc(2026, 1, 1),
    lastReadAt: readAt,
  );
}

ConversationRealtimeEvent _readEvent(
  String userId,
  String readAt, {
  String channelId = 'ch',
}) {
  return ConversationRealtimeEvent(
    type: ConversationRealtimeEventType.channelReadUpdated,
    workspaceId: 'ws',
    channelId: channelId,
    userId: userId,
    payload: {'user_id': userId, 'last_read_at': readAt},
  );
}

void main() {
  final t0 = DateTime.utc(2026, 7, 17, 8, 0);

  group('seenMessageIdFor', () {
    test('chọn tin CUỐI của mình có createdAt <= mốc đọc của người kia', () {
      final messages = [
        _message('a', t0),
        _message('b', t0.add(const Duration(minutes: 1))),
        _message('peer', t0.add(const Duration(minutes: 2)), mine: false),
        _message('c', t0.add(const Duration(minutes: 3))),
      ];
      expect(
        seenMessageIdFor(
          messages: messages,
          peerReadAt: t0.add(const Duration(minutes: 2)),
        ),
        'b',
      );
      expect(
        seenMessageIdFor(
          messages: messages,
          peerReadAt: t0.add(const Duration(minutes: 3)),
        ),
        'c',
      );
    });

    test('đúng mốc đọc vẫn tính là đã xem (biên bằng nhau)', () {
      expect(
        seenMessageIdFor(messages: [_message('a', t0)], peerReadAt: t0),
        'a',
      );
    });

    test('chưa đọc tin nào, không có mốc, hoặc không có tin của mình', () {
      final messages = [_message('a', t0.add(const Duration(minutes: 5)))];
      expect(seenMessageIdFor(messages: messages, peerReadAt: t0), isNull);
      expect(seenMessageIdFor(messages: messages, peerReadAt: null), isNull);
      expect(
        seenMessageIdFor(
          messages: [_message('p', t0, mine: false)],
          peerReadAt: t0.add(const Duration(hours: 1)),
        ),
        isNull,
      );
    });

    test('bỏ qua tin đang gửi, lỗi và tin đã xoá', () {
      final late = t0.add(const Duration(hours: 1));
      final messages = [
        _message('ok', t0),
        _message(
          'sending',
          t0.add(const Duration(minutes: 1)),
          status: 'sending',
        ),
        _message(
          'failed',
          t0.add(const Duration(minutes: 2)),
          status: 'failed',
        ),
        _message('gone', t0.add(const Duration(minutes: 3)), deletedAt: t0),
      ];
      expect(seenMessageIdFor(messages: messages, peerReadAt: late), 'ok');
    });
  });

  group('PeerReadState', () {
    test('chỉ chat đúng 2 người mới có mốc đọc của người kia', () {
      final state = PeerReadState(
        readAtByUserId: {'me': t0, 'peer': t0.add(const Duration(minutes: 1))},
        memberCount: 2,
      );
      expect(state.peerReadAt('me'), t0.add(const Duration(minutes: 1)));
      expect(state.peerReadAt(null), isNull);
      // Nhóm 3 người: không hiện "Đã xem".
      expect(
        PeerReadState(
          readAtByUserId: state.readAtByUserId,
          memberCount: 3,
        ).peerReadAt('me'),
        isNull,
      );
    });

    test('mốc đọc không bao giờ lùi', () {
      final state = const PeerReadState(memberCount: 2)
          .withRead('peer', t0)
          .withRead('peer', t0.subtract(const Duration(days: 1)));
      expect(state.readAtByUserId['peer'], t0);
    });
  });

  group('PeerReadController', () {
    test(
      'lấy mốc đọc ban đầu từ danh sách thành viên, bỏ người đã rời',
      () async {
        final events = StreamController<ConversationRealtimeEvent>.broadcast();
        final controller = PeerReadController(
          scope: _scope,
          loadMembers: () async => Success([
            _member('me', readAt: t0),
            _member('peer', readAt: t0.add(const Duration(minutes: 4))),
            _member('gone', readAt: t0, status: 'left'),
          ]),
          events: events.stream,
        );
        addTearDown(() async {
          controller.dispose();
          await events.close();
        });
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.memberCount, 2);
        expect(
          controller.state.peerReadAt('me'),
          t0.add(const Duration(minutes: 4)),
        );
      },
    );

    test(
      'ChannelReadUpdated cập nhật mốc; sự kiện kênh khác bị bỏ qua',
      () async {
        final events = StreamController<ConversationRealtimeEvent>.broadcast();
        final controller = PeerReadController(
          scope: _scope,
          loadMembers: () async => Success([_member('me'), _member('peer')]),
          events: events.stream,
        );
        addTearDown(() async {
          controller.dispose();
          await events.close();
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.peerReadAt('me'), isNull);

        events.add(
          _readEvent('peer', '2026-07-17T08:05:00Z', channelId: 'khac'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.peerReadAt('me'), isNull);

        events.add(_readEvent('peer', '2026-07-17T08:05:00Z'));
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.state.peerReadAt('me'),
          DateTime.utc(2026, 7, 17, 8, 5),
        );
      },
    );

    test('máy chủ cũ / lỗi mạng: không có mốc, không hiện Đã xem', () async {
      final events = StreamController<ConversationRealtimeEvent>.broadcast();
      final controller = PeerReadController(
        scope: _scope,
        loadMembers: () async => const FailureResult(
          Failure(kind: FailureKind.network, message: 'Mất kết nối.'),
        ),
        events: events.stream,
      );
      addTearDown(() async {
        controller.dispose();
        await events.close();
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.peerReadAt('me'), isNull);
    });
  });
}
