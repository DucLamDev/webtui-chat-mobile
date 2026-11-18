import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';

/// Máy chủ WebSocket giả. [silent] = kết nối vẫn mở nhưng không trả lời gì
/// (như kết nối đã chết khi iOS treo app: socket phía app vẫn báo `open`).
final class _FakeServer {
  _FakeServer._(this._server);

  static Future<_FakeServer> start() async {
    final fake = _FakeServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      final index = fake.sockets.length;
      fake.sockets.add(socket);
      socket.listen((data) {
        final command = jsonDecode(data as String) as Map<String, dynamic>;
        fake.commands.add((socket: index, command: command));
        if (!fake.silent && command['type'] == 'ping') {
          socket.add(jsonEncode({'type': 'pong', 'room': command['room']}));
        }
      });
    });
    return fake;
  }

  final HttpServer _server;
  final sockets = <WebSocket>[];
  final commands = <({int socket, Map<String, dynamic> command})>[];
  bool silent = false;

  Uri get origin => Uri.parse('http://${_server.address.host}:${_server.port}');

  bool joinedOn(int socket, String room) => commands.any(
    (c) =>
        c.socket == socket &&
        c.command['type'] == 'join' &&
        c.command['room'] == room,
  );

  int pingsOn(int socket) => commands
      .where((c) => c.socket == socket && c.command['type'] == 'ping')
      .length;

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

WebSocketConversationRealtimeRepository _repository(
  Uri origin, {
  Duration staleAfter = realtimeStaleAfter,
  Duration probeAfter = realtimeProbeAfter,
  Duration probeTimeout = realtimeProbeTimeout,
  Future<WebSocket> Function(String url, {Map<String, dynamic>? headers})?
  connectWebSocket,
}) {
  final instance = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: origin,
  );
  return WebSocketConversationRealtimeRepository(
    apiBaseUri: origin,
    wsBaseUri: origin.replace(scheme: 'ws', path: '/ws'),
    instanceScope: instance,
    tokenRepository: _StaticTokenRepository(
      AuthTokenMutationGuard(
        instanceScopeId: instance.storageId,
        generation: 'generation-a',
      ),
    ),
    staleAfter: staleAfter,
    probeAfter: probeAfter,
    probeTimeout: probeTimeout,
    connectWebSocket: connectWebSocket,
  );
}

Future<void> _waitFor(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Hết giờ chờ: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _room = 'workspace:ws-1:channel:call-room';

void main() {
  test(
    'kết nối im quá lâu (app bị treo ở nền): vào phòng thì nối lại, vào phòng trên kết nối mới',
    () async {
      final server = await _FakeServer.start();
      server.silent = true;
      final repository = _repository(
        server.origin,
        staleAfter: const Duration(milliseconds: 300),
      );
      final userSub = repository
          .subscribeToUser(workspaceId: 'ws-1')
          .listen((_) {});
      StreamSubscription<ConversationRealtimeEvent>? roomSub;
      try {
        await _waitFor(() => server.sockets.length == 1, 'kết nối đầu');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        // Màn gọi mở ra sau khi app bị treo: phải nối mới chứ không vào phòng
        // trên kết nối đã chết.
        server.silent = false;
        final events = <ConversationRealtimeEvent>[];
        roomSub = repository
            .subscribeToChannel(workspaceId: 'ws-1', channelId: 'call-room')
            .listen(events.add);
        await _waitFor(() => server.sockets.length == 2, 'kết nối mới');
        await _waitFor(
          () => server.joinedOn(1, _room),
          'vào phòng trên kết nối mới',
        );

        // Kết nối cũ đóng muộn không được làm rơi kết nối mới.
        await server.sockets.first.close();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        server.sockets[1].add(
          jsonEncode({
            'type': 'CallOffer',
            'room': _room,
            'payload': {
              'call_id': 'call-1',
              'workspace_id': 'ws-1',
              'channel_id': 'call-room',
              'signal_type': 'offer',
              'payload': {'type': 'offer', 'sdp': 'v=0'},
            },
          }),
        );
        await _waitFor(() => events.isNotEmpty, 'offer qua kết nối mới');
        expect(server.sockets, hasLength(2), reason: 'không nối thêm lần nữa');
      } finally {
        await roomSub?.cancel();
        await userSub.cancel();
        await repository.disconnect();
        await server.close();
      }
    },
  );

  test(
    'ensureConnected: im một lúc thì ping hỏi thử; không trả lời thì nối lại',
    () async {
      final server = await _FakeServer.start();
      final repository = _repository(
        server.origin,
        probeAfter: const Duration(milliseconds: 100),
        probeTimeout: const Duration(milliseconds: 300),
      );
      final roomSub = repository
          .subscribeToChannel(workspaceId: 'ws-1', channelId: 'call-room')
          .listen((_) {});
      try {
        await _waitFor(() => server.joinedOn(0, _room), 'kết nối đầu');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Kết nối còn sống (máy chủ trả pong): giữ nguyên.
        expect(await repository.ensureConnected(workspaceId: 'ws-1'), isTrue);
        expect(server.pingsOn(0), 1);
        expect(server.sockets, hasLength(1));

        // Kết nối chết (không trả lời ping): bỏ, nối lại, vào lại phòng cũ.
        server.silent = true;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final ensured = repository.ensureConnected(workspaceId: 'ws-1');
        await _waitFor(
          () => server.sockets.length == 2,
          'kết nối mới sau ping không hồi âm',
        );
        server.silent = false;
        expect(await ensured, isTrue);
        expect(server.pingsOn(0), 2);
        await _waitFor(
          () => server.joinedOn(1, _room),
          'vào lại phòng trên kết nối mới',
        );
      } finally {
        await roomSub.cancel();
        await repository.disconnect();
        await server.close();
      }
    },
  );

  test(
    'ensureConnected: mất mạng hẳn thì trả false đúng hạn, không nối dồn dập',
    () async {
      var attempts = 0;
      final repository = _repository(
        Uri.parse('http://127.0.0.1:9'),
        connectWebSocket: (url, {headers}) async {
          attempts += 1;
          throw const SocketException('mất mạng');
        },
      );
      final userSub = repository
          .subscribeToUser(workspaceId: 'ws-1')
          .listen((_) {});
      try {
        final started = DateTime.now();
        final ok = await repository.ensureConnected(
          workspaceId: 'ws-1',
          timeout: const Duration(milliseconds: 1500),
        );
        expect(ok, isFalse);
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(seconds: 3)),
        );
        // Lần nối khi bắt đầu nghe + tối đa mỗi giây một lần.
        expect(attempts, inInclusiveRange(2, 4));
        // Workspace chưa nối: không làm gì.
        expect(await repository.ensureConnected(workspaceId: 'ws-x'), isFalse);
      } finally {
        await userSub.cancel();
        await repository.disconnect();
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
