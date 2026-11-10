import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/customer_tickets/data/repositories/web_socket_customer_ticket_realtime_repository.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket_realtime_event.dart';

void main() {
  test(
    'join phòng order-tickets và chỉ nhận OrderTicketUpdated của phòng đó',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final joined = Completer<String>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          if (decoded['type'] == 'join' && !joined.isCompleted) {
            joined.complete(decoded['room'] as String);
          }
        });
      });

      final origin = Uri.parse('http://${server.address.host}:${server.port}');
      final instance = InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: origin,
      );
      final socketRepository = WebSocketConversationRealtimeRepository(
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
      final repository = WebSocketCustomerTicketRealtimeRepository(
        socketRepository.subscribeToOrderTickets,
      );
      final events = <CustomerTicketRealtimeEvent>[];
      final received = Completer<CustomerTicketRealtimeEvent>();
      StreamSubscription<CustomerTicketRealtimeEvent>? subscription;

      try {
        subscription = repository.watch(workspaceId: 'ws-1').listen((event) {
          events.add(event);
          if (!received.isCompleted) received.complete(event);
        });

        expect(
          await joined.future.timeout(const Duration(seconds: 2)),
          'workspace:ws-1:order-tickets',
        );
        // Tin chat của phòng khác không lọt vào luồng ticket.
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
                'created_at': '2026-11-02T02:00:00Z',
              },
            },
          }),
        );
        sockets.single.add(
          jsonEncode({
            'type': 'OrderTicketUpdated',
            'room': 'workspace:ws-1:order-tickets',
            'payload': {
              'reason': 'replied',
              'ticket_ids': [1001],
              'actor_user_id': 'user-lan',
              'counts': {'unanswered': 2, 'answered': 5, 'total': 7},
            },
          }),
        );

        final event = await received.future.timeout(const Duration(seconds: 2));
        expect(event.reason, CustomerTicketRealtimeReason.replied);
        expect(event.ticketIds, ['1001']);
        expect(event.actorUserId, 'user-lan');
        expect(event.counts?.unanswered, 2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, hasLength(1));
      } finally {
        await subscription?.cancel();
        await socketRepository.disconnect();
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
