import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';

/// Máy chủ WebSocket giả: ghi lại các kết nối và lệnh (join / leave...).
final class _FakeRealtimeServer {
  _FakeRealtimeServer._(this._server);

  static Future<_FakeRealtimeServer> start() async {
    final fake = _FakeRealtimeServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fake.sockets.add(socket);
      socket.listen(
        (data) => fake.commands.add(
          jsonDecode(data as String) as Map<String, dynamic>,
        ),
        onDone: () => fake.closedSockets++,
      );
    });
    return fake;
  }

  final HttpServer _server;
  final sockets = <WebSocket>[];
  final commands = <Map<String, dynamic>>[];
  int closedSockets = 0;

  Uri get origin => Uri.parse('http://${_server.address.host}:${_server.port}');

  int count(String type, String room) =>
      commands.where((c) => c['type'] == type && c['room'] == room).length;

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

WebSocketConversationRealtimeRepository _repository(
  _FakeRealtimeServer server, {
  Duration idleDisconnectGrace = realtimeIdleDisconnectGrace,
}) {
  final instance = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: server.origin,
  );
  return WebSocketConversationRealtimeRepository(
    apiBaseUri: server.origin,
    wsBaseUri: server.origin.replace(scheme: 'ws', path: '/ws'),
    instanceScope: instance,
    tokenRepository: _StaticTokenRepository(
      AuthTokenMutationGuard(
        instanceScopeId: instance.storageId,
        generation: 'generation-a',
      ),
    ),
    idleDisconnectGrace: idleDisconnectGrace,
  );
}

Future<void> _waitFor(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Hết giờ chờ: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Chờ thêm một chút để chắc không có lệnh / kết nối nào tới nữa.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

const _roomA = 'workspace:ws-1:channel:c-a';
const _roomB = 'workspace:ws-1:channel:c-b';

void main() {
  test(
    'mở / rời phòng chat chỉ vào / rời phòng, không mở kết nối mới',
    () async {
      final server = await _FakeRealtimeServer.start();
      final repository = _repository(server);
      final userEvents = <ConversationRealtimeEvent>[];
      final userSub = repository
          .subscribeToUser(workspaceId: 'ws-1')
          .listen(userEvents.add);
      try {
        // Mở phòng A, rời, mở phòng B, rời (như gọi / chuyển phòng liên tục).
        final roomA = repository
            .subscribeToChannel(workspaceId: 'ws-1', channelId: 'c-a')
            .listen((_) {});
        await _waitFor(() => server.count('join', _roomA) == 1, 'join A');
        await roomA.cancel();
        await _waitFor(() => server.count('leave', _roomA) == 1, 'leave A');

        final roomB = repository
            .subscribeToChannel(workspaceId: 'ws-1', channelId: 'c-b')
            .listen((_) {});
        await _waitFor(() => server.count('join', _roomB) == 1, 'join B');
        await roomB.cancel();
        await _waitFor(() => server.count('leave', _roomB) == 1, 'leave B');
        await _settle();

        expect(server.sockets, hasLength(1), reason: 'chỉ một kết nối');
        expect(server.closedSockets, 0);

        // Kết nối vẫn sống cho luồng người dùng (cuộc gọi đến...).
        server.sockets.single.add(
          jsonEncode({
            'type': 'ChannelUpdated',
            'room': 'workspace:ws-1:user-events',
            'payload': {'workspace_id': 'ws-1', 'channel_id': 'c-a'},
          }),
        );
        await _waitFor(() => userEvents.isNotEmpty, 'sự kiện người dùng');
      } finally {
        await userSub.cancel();
        await repository.disconnect();
        await server.close();
      }
    },
  );

  test(
    'hai luồng cùng nghe một phòng: còn một luồng thì chưa rời phòng',
    () async {
      final server = await _FakeRealtimeServer.start();
      final repository = _repository(server);
      final userSub = repository
          .subscribeToUser(workspaceId: 'ws-1')
          .listen((_) {});
      try {
        final first = repository
            .subscribeToChannel(workspaceId: 'ws-1', channelId: 'c-a')
            .listen((_) {});
        final secondEvents = <ConversationRealtimeEvent>[];
        final second = repository
            .subscribeToChannel(workspaceId: 'ws-1', channelId: 'c-a')
            .listen(secondEvents.add);
        await _waitFor(() => server.count('join', _roomA) >= 1, 'join A');
        await _settle();
        expect(server.count('join', _roomA), 1, reason: 'vào phòng một lần');

        await first.cancel();
        await _settle();
        expect(server.count('leave', _roomA), 0);

        server.sockets.single.add(
          jsonEncode({
            'type': 'MessageCreated',
            'room': _roomA,
            'payload': {
              'message': {
                'id': 'm-1',
                'workspace_id': 'ws-1',
                'channel_id': 'c-a',
                'body': 'xin chào',
                'created_at': '2026-11-17T02:00:00Z',
              },
            },
          }),
        );
        await _waitFor(() => secondEvents.isNotEmpty, 'tin của luồng còn lại');

        await second.cancel();
        await _waitFor(() => server.count('leave', _roomA) == 1, 'leave A');
      } finally {
        await userSub.cancel();
        await repository.disconnect();
        await server.close();
      }
    },
  );

  test('phòng còn trong danh sách chat đang theo dõi thì không rời', () async {
    final server = await _FakeRealtimeServer.start();
    final repository = _repository(server);
    final userSub = repository
        .subscribeToUser(workspaceId: 'ws-1')
        .listen((_) {});
    StreamSubscription<ConversationRealtimeEvent>? watchSub;
    try {
      await _waitFor(() => server.sockets.isNotEmpty, 'kết nối');
      watchSub = repository
          .watchChannels(workspaceId: 'ws-1', channelIds: ['c-a'])!
          .listen((_) {});
      final room = repository
          .subscribeToChannel(workspaceId: 'ws-1', channelId: 'c-a')
          .listen((_) {});
      await _waitFor(() => server.count('join', _roomA) >= 1, 'join A');
      await room.cancel();
      await _settle();
      expect(server.count('leave', _roomA), 0);
    } finally {
      await watchSub?.cancel();
      await userSub.cancel();
      await repository.disconnect();
      await server.close();
    }
  });

  test(
    'hết người nghe: chuyển màn nhanh dùng lại kết nối, quá thời gian chờ mới đóng',
    () async {
      final server = await _FakeRealtimeServer.start();
      final repository = _repository(
        server,
        idleDisconnectGrace: const Duration(milliseconds: 300),
      );
      try {
        var sub = repository
            .subscribeToUser(workspaceId: 'ws-1')
            .listen((_) {});
        await _waitFor(() => server.sockets.length == 1, 'kết nối 1');
        // Màn trước huỷ nghe, màn sau nghe ngay: không ngắt, không nối mới.
        await sub.cancel();
        sub = repository.subscribeToUser(workspaceId: 'ws-1').listen((_) {});
        await _settle();
        expect(server.sockets, hasLength(1));
        expect(server.closedSockets, 0);

        // Không ai nghe quá thời gian chờ: đóng kết nối.
        await sub.cancel();
        await _waitFor(() => server.closedSockets == 1, 'đóng khi rảnh');
      } finally {
        await repository.disconnect();
        await server.close();
      }
    },
  );

  test(
    'mở phòng của workspace khác: kết nối phụ, không cắt luồng cuộc gọi đến',
    () async {
      final server = await _FakeRealtimeServer.start();
      final repository = _repository(server);
      final userEvents = <ConversationRealtimeEvent>[];
      final userSub = repository
          .subscribeToUser(workspaceId: 'ws-1')
          .listen(userEvents.add, onDone: () => fail('luồng ws-1 bị đóng'));
      try {
        await _waitFor(() => server.sockets.length == 1, 'kết nối ws-1');
        final otherRoom = repository
            .subscribeToChannel(workspaceId: 'ws-2', channelId: 'c-x')
            .listen((_) {});
        await _waitFor(
          () => server.count('join', 'workspace:ws-2:channel:c-x') == 1,
          'join phòng ws-2',
        );
        expect(server.sockets, hasLength(2));
        expect(server.closedSockets, 0);

        // Kết nối ws-1 vẫn nhận sự kiện của người dùng.
        server.sockets.first.add(
          jsonEncode({
            'type': 'ChannelUpdated',
            'room': 'workspace:ws-1:user-events',
            'payload': {'workspace_id': 'ws-1', 'channel_id': 'c-a'},
          }),
        );
        await _waitFor(() => userEvents.isNotEmpty, 'sự kiện ws-1');
        await otherRoom.cancel();
      } finally {
        await userSub.cancel();
        await repository.disconnect();
        await server.close();
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
