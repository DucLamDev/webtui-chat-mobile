import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';

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
