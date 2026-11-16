import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/conversation_realtime_reducer.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_exit.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/channel_exit_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/channel_detail_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/channel_membership_events.dart';

ConversationRealtimeEvent? _parse(Map<String, Object?> envelope) {
  return ConversationRealtimeEventMapper.fromSocketData(
    jsonEncode(envelope),
    fallbackWorkspaceId: 'w1',
    fallbackChannelId: '',
  );
}

ConversationRealtimeEvent _event(
  ConversationRealtimeEventType type, {
  String channelId = 'c1',
  String? userId,
}) {
  return ConversationRealtimeEvent(
    type: type,
    workspaceId: 'w1',
    channelId: channelId,
    userId: userId,
  );
}

void main() {
  const reducer = ConversationRealtimeReducer();

  group('đọc sự kiện từ WebSocket', () {
    test('ChannelArchived', () {
      final event = _parse({
        'type': 'ChannelArchived',
        'room': 'user:u1',
        'payload': {'workspace_id': 'w1', 'channel_id': 'c1'},
      });
      expect(event?.type, ConversationRealtimeEventType.channelArchived);
      expect(event?.workspaceId, 'w1');
      expect(event?.channelId, 'c1');
    });

    test('ChannelMemberLeft: người rời lấy từ payload.user_id', () {
      final event = _parse({
        'type': 'ChannelMemberLeft',
        'room': 'workspace:w1:channel:c1',
        // Người gửi sự kiện ở ngoài khác người rời: vẫn lấy người rời.
        'user_id': 'system',
        'payload': {'workspace_id': 'w1', 'channel_id': 'c1', 'user_id': 'u2'},
      });
      expect(event?.type, ConversationRealtimeEventType.channelMemberLeft);
      expect(event?.channelId, 'c1');
      expect(event?.userId, 'u2');
    });
  });

  group('reducer', () {
    test('hai sự kiện mới không đổi danh sách tin của phòng', () {
      final message = ChatMessage(
        id: 'm1',
        workspaceId: 'w1',
        channelId: 'c1',
        kind: 'text',
        body: 'Chào',
        createdAt: DateTime.utc(2026, 11, 16),
      );
      final state = ConversationRealtimeState(messages: [message]);
      for (final type in [
        ConversationRealtimeEventType.channelArchived,
        ConversationRealtimeEventType.channelMemberLeft,
      ]) {
        final next = reducer.reduce(
          state,
          _event(type, userId: 'u2'),
          currentUserId: 'u1',
        );
        expect(next.messages, [message]);
      }
    });

    test('ChannelArchived → archived', () {
      expect(
        reducer.membershipChange(
          _event(ConversationRealtimeEventType.channelArchived),
          currentUserId: 'u1',
        ),
        ChannelMembershipChange.archived,
      );
    });

    test(
      'ChannelMemberLeft của mình → leftByMe, của người khác → memberLeft',
      () {
        expect(
          reducer.membershipChange(
            _event(
              ConversationRealtimeEventType.channelMemberLeft,
              userId: 'u1',
            ),
            currentUserId: 'u1',
          ),
          ChannelMembershipChange.leftByMe,
        );
        expect(
          reducer.membershipChange(
            _event(
              ConversationRealtimeEventType.channelMemberLeft,
              userId: 'u2',
            ),
            currentUserId: 'u1',
          ),
          ChannelMembershipChange.memberLeft,
        );
      },
    );

    test('chưa biết mình là ai: chỉ làm mới, không tự bỏ nhóm', () {
      expect(
        reducer.membershipChange(
          _event(ConversationRealtimeEventType.channelMemberLeft, userId: 'u1'),
          currentUserId: null,
        ),
        ChannelMembershipChange.memberLeft,
      );
    });

    test('thiếu channel_id hoặc sự kiện khác → null', () {
      expect(
        reducer.membershipChange(
          _event(ConversationRealtimeEventType.channelArchived, channelId: ''),
          currentUserId: 'u1',
        ),
        isNull,
      );
      expect(
        reducer.membershipChange(
          _event(ConversationRealtimeEventType.channelUpdated),
          currentUserId: 'u1',
        ),
        isNull,
      );
    });
  });

  group('handleChannelMembershipEvent', () {
    late _FakeRepository repository;
    late ProviderContainer container;

    setUp(() {
      repository = _FakeRepository();
      container = ProviderContainer(
        overrides: [
          channelExitRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
    });

    bool handle(ConversationRealtimeEvent event) =>
        handleChannelMembershipEvent(
          read: container.read,
          exists: container.exists,
          event: event,
          currentUserId: 'u1',
        );

    test('nhóm bị xoá: báo màn đang mở đóng, bỏ khỏi bộ nhớ đệm', () async {
      expect(
        handle(_event(ConversationRealtimeEventType.channelArchived)),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);

      final signal = container.read(channelRemovalSignalProvider);
      expect(signal?.channelId, 'c1');
      expect(signal?.reason, ChannelRemovalReason.deleted);
      expect(signal?.initiatedHere, isFalse);
      expect(repository.forgotten, ['w1/c1']);
    });

    test('mình rời ở máy khác: bỏ nhóm, lý do "rời"', () async {
      handle(
        _event(ConversationRealtimeEventType.channelMemberLeft, userId: 'u1'),
      );
      await Future<void>.delayed(Duration.zero);

      final signal = container.read(channelRemovalSignalProvider);
      expect(signal?.reason, ChannelRemovalReason.left);
      expect(repository.forgotten, ['w1/c1']);
    });

    test('người khác rời: làm mới thông tin nhóm, không bỏ nhóm', () {
      handle(
        _event(ConversationRealtimeEventType.channelMemberLeft, userId: 'u2'),
      );

      expect(container.read(channelRemovalSignalProvider), isNull);
      expect(container.read(channelUpdatedTickProvider('c1')), 1);
      expect(repository.forgotten, isEmpty);
    });

    test('sự kiện khác: không xử lý', () {
      expect(
        handle(_event(ConversationRealtimeEventType.channelUpdated)),
        isFalse,
      );
      expect(container.read(channelRemovalSignalProvider), isNull);
    });

    test('hai lần báo cùng nhóm vẫn là hai tín hiệu khác nhau', () {
      handle(_event(ConversationRealtimeEventType.channelArchived));
      final first = container.read(channelRemovalSignalProvider)!.serial;
      handle(_event(ConversationRealtimeEventType.channelArchived));
      expect(container.read(channelRemovalSignalProvider)!.serial, first + 1);
    });
  });
}

final class _FakeRepository implements ChannelExitRepository {
  final forgotten = <String>[];

  @override
  Future<Result<ChannelLeaveResult>> leave({
    required String workspaceId,
    required String channelId,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> delete({
    required String workspaceId,
    required String channelId,
  }) => throw UnimplementedError();

  @override
  Future<void> forgetLocally({
    required String workspaceId,
    required String channelId,
  }) async {
    forgotten.add('$workspaceId/$channelId');
  }
}
