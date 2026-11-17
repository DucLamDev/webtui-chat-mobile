import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_presence.dart';

ConversationRealtimeEvent? _parse(Map<String, dynamic> payload) =>
    ConversationRealtimeEventMapper.fromSocketData(
      jsonEncode({
        'type': 'PresenceChanged',
        'room': 'user:u1',
        'payload': payload,
      }),
      fallbackWorkspaceId: 'ws-1',
      fallbackChannelId: '',
    );

void main() {
  final beat = DateTime.utc(2026, 11, 17, 3, 30);

  group('parse PresenceChanged', () {
    test('đọc đủ trường', () {
      final event = _parse({
        'workspace_id': 'ws-1',
        'user_id': 'u2',
        'status': 'online',
        'last_heartbeat_at': '2026-11-17T03:30:00Z',
      })!;
      expect(event.type, ConversationRealtimeEventType.presenceChanged);
      final summary = presenceFromRealtimeEvent(event)!;
      expect(summary.userId, 'u2');
      expect(summary.status, ConversationPresence.online);
      expect(summary.lastHeartbeatAt, beat);
    });

    test('thiếu trường thì bỏ sự kiện', () {
      expect(_parse({'workspace_id': 'ws-1', 'status': 'online'}), isNull);
      expect(
        _parse({
          'workspace_id': 'ws-1',
          'user_id': 'u2',
          'last_heartbeat_at': '2026-11-17T03:30:00Z',
        }),
        isNull,
      );
    });
  });

  group('provider cập nhật theo sự kiện', () {
    late _Repo repository;
    late ProviderContainer container;

    setUp(() {
      repository = _Repo([
        PresenceSummary(
          userId: 'u2',
          status: ConversationPresence.offline,
          lastHeartbeatAt: beat,
        ),
      ]);
      container = ProviderContainer(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
    });

    ConversationRealtimeEvent event(String workspace, String status) =>
        _parse({
          'workspace_id': workspace,
          'user_id': 'u2',
          'status': status,
          'last_heartbeat_at': '2026-11-17T04:00:00Z',
        })!;

    test('chấm xanh + thanh phòng chat đổi ngay, không gọi API thêm', () async {
      final list = container.listen(
        workspacePresenceProvider('ws-1'),
        (_, _) {},
      );
      final peer = container.listen(
        peerPresenceProvider((workspaceId: 'ws-1', peerUserId: 'u2')),
        (_, _) {},
      );
      addTearDown(list.close);
      addTearDown(peer.close);
      expect(
        (await container.read(workspacePresenceProvider('ws-1').future))['u2'],
        ConversationPresence.offline,
      );
      expect(repository.calls, 1, reason: 'hai provider dùng chung một lượt');

      handlePresenceRealtimeEvent(
        read: container.read,
        event: event('ws-1', 'online'),
        workspaceId: 'ws-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(workspacePresenceProvider('ws-1')).value!['u2'],
        ConversationPresence.online,
      );
      final summary = container
          .read(
            peerPresenceProvider((workspaceId: 'ws-1', peerUserId: 'u2')),
          )
          .value!;
      expect(summary.status, ConversationPresence.online);
      expect(summary.lastHeartbeatAt, DateTime.utc(2026, 11, 17, 4));
      expect(repository.calls, 1);
    });

    test('sự kiện của workspace khác bị bỏ', () async {
      final sub = container.listen(
        workspacePresenceProvider('ws-1'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(workspacePresenceProvider('ws-1').future);
      handlePresenceRealtimeEvent(
        read: container.read,
        event: event('ws-2', 'online'),
        workspaceId: 'ws-1',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(workspacePresenceProvider('ws-1')).value!['u2'],
        ConversationPresence.offline,
      );
    });

    test('refreshPresenceNow tải lại ngay', () async {
      final sub = container.listen(
        workspacePresenceProvider('ws-1'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(workspacePresenceProvider('ws-1').future);
      expect(repository.calls, 1);
      refreshPresenceNow(container.read);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, 2);
    });
  });
}

final class _Repo implements ConversationRepository {
  _Repo(this.items);

  final List<PresenceSummary> items;
  int calls = 0;

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) async {
    calls++;
    return Success(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
