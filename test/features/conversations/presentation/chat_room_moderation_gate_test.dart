import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/chat_room_screen.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';
import 'package:webtui_chat/features/moderation/presentation/controllers/moderation_controller.dart';

void main() {
  testWidgets('direct deep-link route is fail-closed while blocks load', (
    tester,
  ) async {
    await _pumpDirectRoute(
      tester,
      initialState: const ModerationState(isLoadingBlockedUsers: true),
    );

    expect(
      find.byKey(const Key('chat_moderation_loading_gate')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('direct deep-link route shows safety error and retries', (
    tester,
  ) async {
    final pendingRetry = Completer<Result<List<BlockedUser>>>();
    var retryCalls = 0;
    await _pumpDirectRoute(
      tester,
      initialState: const ModerationState(
        errorMessage: 'Cannot verify blocked users.',
      ),
      listBlockedUsers: (_) {
        retryCalls++;
        return pendingRetry.future;
      },
    );

    expect(find.byKey(const Key('chat_moderation_error_gate')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Thử lại'));
    await tester.pump();

    expect(retryCalls, 1);
    expect(
      find.byKey(const Key('chat_moderation_loading_gate')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  test('ready state is the only state allowed to build chat content', () {
    expect(
      chatModerationSafetyStatus(const ModerationState()),
      ChatModerationSafetyStatus.ready,
    );
    expect(
      chatModerationSafetyStatus(
        const ModerationState(isLoadingBlockedUsers: true),
      ),
      ChatModerationSafetyStatus.loading,
    );
    expect(
      chatModerationSafetyStatus(
        const ModerationState(errorMessage: 'Safety lookup failed.'),
      ),
      ChatModerationSafetyStatus.error,
    );
  });

  test('moderation retry transitions error through loading to ready', () async {
    final response = Completer<Result<List<BlockedUser>>>();
    final controller = ModerationController.forTesting(
      workspaceId: 'workspace-1',
      initialState: const ModerationState(errorMessage: 'Initial failure.'),
      listBlockedUsers: (_) => response.future,
    );

    final retry = controller.loadBlockedUsers();
    expect(controller.state.isLoadingBlockedUsers, isTrue);
    expect(
      chatModerationSafetyStatus(controller.state),
      ChatModerationSafetyStatus.loading,
    );

    response.complete(const Success(<BlockedUser>[]));
    await retry;

    expect(controller.state.errorMessage, isNull);
    expect(
      chatModerationSafetyStatus(controller.state),
      ChatModerationSafetyStatus.ready,
    );
    controller.dispose();
  });
}

Future<void> _pumpDirectRoute(
  WidgetTester tester, {
  required ModerationState initialState,
  Future<Result<List<BlockedUser>>> Function(String workspaceId)?
  listBlockedUsers,
}) async {
  final router = GoRouter(
    initialLocation: '/conversations/channel-1',
    routes: [
      GoRoute(
        path: '/conversations/:channelId',
        builder: (_, _) => const ChatRoomScreen(
          workspaceId: 'workspace-1',
          channelId: 'channel-1',
          title: 'Direct conversation',
          peerUserId: 'blocked-user',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moderationControllerProvider('workspace-1').overrideWith(
          (ref) => ModerationController.forTesting(
            workspaceId: 'workspace-1',
            initialState: initialState,
            listBlockedUsers: listBlockedUsers,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}
