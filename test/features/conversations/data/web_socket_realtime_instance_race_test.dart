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
  test('repository rejects a WebSocket origin outside the instance', () {
    final instance = InstanceScope(
      instanceId: '11111111-1111-4111-8111-111111111111',
      serverOrigin: Uri.parse('https://chat.example'),
    );
    final tokens = _DelayedTokenRepository(
      guard: AuthTokenMutationGuard(
        instanceScopeId: instance.storageId,
        generation: 'generation-a',
      ),
      delayedAccessToken: Future<String?>.value('token-a'),
    );

    expect(
      () => WebSocketConversationRealtimeRepository(
        apiBaseUri: instance.origin,
        wsBaseUri: Uri.parse('wss://sink.chat.example/ws'),
        instanceScope: instance,
        tokenRepository: tokens,
      ),
      throwsFormatException,
    );
  });

  test('delayed A token cannot open A socket after switching to B', () async {
    final instanceA = InstanceScope(
      instanceId: '11111111-1111-4111-8111-111111111111',
      serverOrigin: Uri.parse('https://server-a.example'),
    );
    final guardA = AuthTokenMutationGuard(
      instanceScopeId: instanceA.storageId,
      generation: 'generation-a',
    );
    const guardB = AuthTokenMutationGuard(
      instanceScopeId: 'scope-b',
      generation: 'generation-b',
    );
    final delayedToken = Completer<String?>();
    final tokens = _DelayedTokenRepository(
      guard: guardA,
      delayedAccessToken: delayedToken.future,
    );
    var connectCalls = 0;
    final repository = WebSocketConversationRealtimeRepository(
      apiBaseUri: instanceA.origin,
      wsBaseUri: Uri.parse('wss://server-a.example'),
      instanceScope: instanceA,
      tokenRepository: tokens,
      connectWebSocket: (String url, {Map<String, dynamic>? headers}) async {
        connectCalls += 1;
        throw StateError('Network connector must not be reached.');
      },
    );

    final subscription = repository
        .subscribeToChannel(
          workspaceId: 'workspace-shared',
          channelId: 'channel-shared',
        )
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);

    tokens.guard = guardB;
    delayedToken.complete('token-a');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(connectCalls, 0);
    await subscription.cancel();
    await repository.disconnect();
  });

  test('authenticated WebSocket handshake never follows redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? receivedAuthorization;
    var redirectedSinkReached = false;
    server.listen((request) async {
      if (request.uri.path == '/socket') {
        receivedAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://${server.address.host}:${server.port}/redirected-sink',
          );
        await request.response.close();
        return;
      }
      redirectedSinkReached = true;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });

    try {
      await expectLater(
        connectWebSocketWithoutRedirects(
          'ws://${server.address.host}:${server.port}/socket',
          headers: const {'Authorization': 'Bearer instance-secret'},
        ),
        throwsA(isA<WebSocketException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedAuthorization, 'Bearer instance-secret');
      expect(redirectedSinkReached, isFalse);
    } finally {
      await server.close(force: true);
    }
  });

  test('manual no-redirect handshake creates a usable socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedAuthorization = Completer<String?>();
    server.listen((request) async {
      if (!receivedAuthorization.isCompleted) {
        receivedAuthorization.complete(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen(socket.add);
    });

    WebSocket? socket;
    try {
      socket = await connectWebSocketWithoutRedirects(
        'ws://${server.address.host}:${server.port}/socket',
        headers: const {'Authorization': 'Bearer instance-secret'},
      );
      expect(await receivedAuthorization.future, 'Bearer instance-secret');
      final echo = socket.first;
      socket.add('ping');
      expect(await echo, 'ping');
    } finally {
      await socket?.close();
      await server.close(force: true);
    }
  });

  test(
    'repository keeps existing channel subscribers when another room joins',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final joinedRooms = <String>{};
      final joinedBothRooms = Completer<void>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          if (decoded['type'] == 'join') {
            joinedRooms.add(decoded['room'] as String);
            if (!joinedBothRooms.isCompleted &&
                joinedRooms.contains(
                  'workspace:workspace-1:channel:channel-1',
                ) &&
                joinedRooms.contains(
                  'workspace:workspace-1:channel:channel-2',
                )) {
              joinedBothRooms.complete();
            }
          }
          if (decoded['type'] == 'ping') {
            socket.add(
              jsonEncode({
                'type': 'pong',
                'room': decoded['room'],
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              }),
            );
          }
        });
      });

      final origin = Uri.parse('http://${server.address.host}:${server.port}');
      final instance = InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: origin,
      );
      final tokens = _DelayedTokenRepository(
        guard: AuthTokenMutationGuard(
          instanceScopeId: instance.storageId,
          generation: 'generation-a',
        ),
        delayedAccessToken: Future<String?>.value('token-a'),
      );
      final repository = WebSocketConversationRealtimeRepository(
        apiBaseUri: origin,
        wsBaseUri: origin.replace(scheme: 'ws', path: '/ws'),
        instanceScope: instance,
        tokenRepository: tokens,
      );
      final channelOneEvent = Completer<ConversationRealtimeEvent>();
      final channelTwoEvents = <ConversationRealtimeEvent>[];
      StreamSubscription<ConversationRealtimeEvent>? channelOne;
      StreamSubscription<ConversationRealtimeEvent>? channelTwo;

      try {
        channelOne = repository
            .subscribeToChannel(
              workspaceId: 'workspace-1',
              channelId: 'channel-1',
            )
            .listen((event) {
              if (!channelOneEvent.isCompleted) {
                channelOneEvent.complete(event);
              }
            });
        channelTwo = repository
            .subscribeToChannel(
              workspaceId: 'workspace-1',
              channelId: 'channel-2',
            )
            .listen(channelTwoEvents.add);

        await joinedBothRooms.future.timeout(const Duration(seconds: 2));
        sockets.single.add(
          jsonEncode({
            'type': 'MessageCreated',
            'room': 'workspace:workspace-1:channel:channel-1',
            'payload': {
              'message': {
                'id': 'message-1',
                'workspace_id': 'workspace-1',
                'channel_id': 'channel-1',
                'sender_id': 'user-web',
                'kind': 'text',
                'body': 'hello from web',
                'created_at': '2026-08-14T02:54:00Z',
                'updated_at': '2026-08-14T02:54:00Z',
                'metadata': <String, Object?>{},
                'mentions': <String>[],
                'reactions': <Object>[],
              },
            },
          }),
        );

        final event = await channelOneEvent.future.timeout(
          const Duration(seconds: 2),
        );
        expect(event.messageId, 'message-1');
        expect(event.channelId, 'channel-1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(channelTwoEvents, isEmpty);
      } finally {
        await channelOne?.cancel();
        await channelTwo?.cancel();
        await repository.disconnect();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );
}

final class _DelayedTokenRepository implements AuthTokenRepository {
  _DelayedTokenRepository({
    required this.guard,
    required this.delayedAccessToken,
  });

  AuthTokenMutationGuard? guard;
  final Future<String?> delayedAccessToken;

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
  Future<String?> readAccessToken() => delayedAccessToken;

  @override
  Future<String?> readAccessTokenIfCurrent(AuthTokenMutationGuard guard) =>
      delayedAccessToken;

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
