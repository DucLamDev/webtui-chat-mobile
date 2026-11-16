import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';

void main() {
  test(
    'watchChannels: join phòng của danh sách chat, nhận tin mới, rời phòng bị bỏ',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final seen = <Map<String, dynamic>>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          seen.add(decoded);
        });
      });

      final origin = Uri.parse('http://${server.address.host}:${server.port}');
      final instance = InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: origin,
      );
      final repository = WebSocketConversationRealtimeRepository(
        apiBaseUri: origin,
        wsBaseUri: origin.replace(scheme: 'ws', path: '/ws'),
        instanceScope: instance,
        tokenRepository: _StaticTokenRepository(
          AuthTokenMutationGuard(
            instanceScopeId: instance.storageId,
            generation: 'generation-a',
          ),
        ),
      );
      StreamSubscription<ConversationRealtimeEvent>? userSub;
      StreamSubscription<ConversationRealtimeEvent>? watchSub;

      Future<void> waitFor(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 4));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Hết giờ chờ, đã nhận: $seen');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      bool has(String type, String room) =>
          seen.any((c) => c['type'] == type && c['room'] == room);

      try {
        // Chưa nối workspace nào: không làm gì, không tự nối.
        expect(
          repository.watchChannels(workspaceId: 'ws-1', channelIds: ['c-1']),
          isNull,
        );

        final userEvents = <ConversationRealtimeEvent>[];
        userSub = repository
            .subscribeToUser(workspaceId: 'ws-1')
            .listen(userEvents.add);
        // Workspace khác workspace đang nối: bỏ qua.
        expect(
          repository.watchChannels(workspaceId: 'ws-2', channelIds: ['c-9']),
          isNull,
        );

        final events = <ConversationRealtimeEvent>[];
        watchSub = repository
            .watchChannels(
              workspaceId: 'ws-1',
              channelIds: ['c-1', 'c-2', ' '],
            )!
            .listen(events.add);

        await waitFor(
          () =>
              has('join', 'workspace:ws-1:channel:c-1') &&
              has('join', 'workspace:ws-1:channel:c-2'),
        );
        expect(seen.where((c) => c['type'] == 'join'), hasLength(2));

        sockets.single.add(
          jsonEncode({
            'type': 'MessageCreated',
            'room': 'workspace:ws-1:channel:c-1',
            'payload': {
              'message': {
                'id': 'm-1',
                'workspace_id': 'ws-1',
                'channel_id': 'c-1',
                'body': 'xin chào',
                'created_at': '2026-11-16T02:00:00Z',
              },
            },
          }),
        );
        // Sự kiện của phòng người dùng (cùng channel_id c-1) vẫn về luồng
        // người dùng như cũ, không lọt vào luồng theo dõi danh sách.
        sockets.single.add(
          jsonEncode({
            'type': 'ChannelUpdated',
            'room': 'workspace:ws-1:user-events',
            'payload': {'workspace_id': 'ws-1', 'channel_id': 'c-1'},
          }),
        );
        await waitFor(() => events.isNotEmpty && userEvents.isNotEmpty);
        expect(
          events.single.type,
          ConversationRealtimeEventType.messageCreated,
        );
        expect(events.single.channelId, 'c-1');
        // Tin của phòng chỉ để theo dõi không lọt vào luồng người dùng (màn
        // chính / cuộc gọi đến không xử lý thêm sự kiện của mọi nhóm).
        expect(
          userEvents.single.type,
          ConversationRealtimeEventType.channelUpdated,
        );

        // Danh sách mới không còn c-1: rời c-1, giữ c-2, không join lại c-2.
        repository.watchChannels(workspaceId: 'ws-1', channelIds: ['c-2']);
        await waitFor(() => has('leave', 'workspace:ws-1:channel:c-1'));
        expect(has('leave', 'workspace:ws-1:channel:c-2'), isFalse);
        expect(
          seen.where(
            (c) =>
                c['type'] == 'join' &&
                c['room'] == 'workspace:ws-1:channel:c-2',
          ),
          hasLength(1),
        );

        // Rớt kết nối: nối lại thì join lại phòng đang theo dõi.
        seen.clear();
        await sockets.single.close();
        await waitFor(() => has('join', 'workspace:ws-1:channel:c-2'));
        expect(has('join', 'workspace:ws-1:channel:c-1'), isFalse);
      } finally {
        await watchSub?.cancel();
        await userSub?.cancel();
        await repository.disconnect();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );
}

final class _StaticTokenRepository implements AuthTokenRepository {
  _StaticTokenRepository(this.guard);

  final AuthTokenMutationGuard guard;

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => guard;

  @override
  Future<void> clearTokens() async {}

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) async =>
      guard == this.guard;

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard) async =>
      guard == this.guard;

  @override
  Future<String?> readAccessToken() async => 'token-a';

  @override
  Future<String?> readAccessTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => 'token-a';

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {}

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) async => guard == this.guard;
}
