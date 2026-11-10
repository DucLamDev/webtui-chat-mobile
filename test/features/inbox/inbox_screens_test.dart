import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/inbox/application/inbox_access_policy.dart';
import 'package:webtui_chat/features/inbox/domain/entities/inbox.dart';
import 'package:webtui_chat/features/inbox/presentation/controllers/inbox_access_provider.dart';
import 'package:webtui_chat/features/inbox/presentation/screens/inbox_conversation_screen.dart';
import 'package:webtui_chat/features/inbox/presentation/screens/inbox_list_screen.dart';
import 'package:webtui_chat/features/inbox/presentation/widgets/inbox_message_bubble.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/permission_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

import 'support/inbox_fakes.dart';

final class _NoWorkspaces implements WorkspaceRepository {
  @override
  Future<Result<List<Workspace>>> listMine() async =>
      FailureResult(failure(FailureKind.network));

  @override
  Future<Result<Workspace>> get(String workspaceId) async =>
      FailureResult(failure(FailureKind.network));
}

final class _NoPermissions implements PermissionRepository {
  @override
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  ) async => FailureResult(failure(FailureKind.network));
}

final class _NoSession implements WorkspaceSessionRepository {
  @override
  Future<String?> readActiveWorkspaceId() async => null;

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {}

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {}
}

const _allowed = InboxAccess(
  serverSupported: true,
  permissionsLoaded: true,
  canView: true,
);

Future<void> _pump(
  WidgetTester tester, {
  required FakeInboxRepository repo,
  required Widget screen,
  InboxAccess access = _allowed,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceRepositoryProvider.overrideWithValue(_NoWorkspaces()),
        permissionRepositoryProvider.overrideWithValue(_NoPermissions()),
        workspaceSessionRepositoryProvider.overrideWithValue(_NoSession()),
        inboxRepositoryProvider.overrideWithValue(repo),
        inboxRealtimeRepositoryProvider.overrideWithValue(FakeInboxRealtime()),
        inboxAccessProvider.overrideWith((ref, _) => access),
        inboxCurrentUserIdProvider.overrideWith((ref) async => 'me'),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('Màn danh sách hộp thư khách', () {
    testWidgets('rỗng thì hiện trạng thái trống', (tester) async {
      final repo = FakeInboxRepository()
        ..pages = [const InboxConversationPage(items: [])];
      await _pump(
        tester,
        repo: repo,
        screen: const InboxListScreen(workspaceId: 'ws'),
      );
      expect(find.byKey(const Key('inbox_empty')), findsOneWidget);
    });

    testWidgets('có dữ liệu thì hiện nhãn, tóm tắt, chưa đọc, nguồn', (
      tester,
    ) async {
      final repo = FakeInboxRepository()
        ..pages = [
          InboxConversationPage(
            items: [sampleConversation(id: 'a', unread: 3)],
          ),
        ];
      await _pump(
        tester,
        repo: repo,
        screen: const InboxListScreen(workspaceId: 'ws'),
      );
      expect(find.byKey(const Key('inbox_item_a')), findsOneWidget);
      expect(find.text('An · fb#vip'), findsOneWidget);
      expect(find.text('Xin chào shop'), findsOneWidget);
      expect(find.byKey(const Key('inbox_unread_a')), findsOneWidget);
      expect(find.byKey(const Key('inbox_source_a')), findsOneWidget);
    });

    testWidgets('403 thì báo không có quyền, không lỗi', (tester) async {
      final repo = FakeInboxRepository()
        ..listFailure = failure(FailureKind.forbidden);
      await _pump(
        tester,
        repo: repo,
        screen: const InboxListScreen(workspaceId: 'ws'),
      );
      expect(find.byKey(const Key('inbox_no_access')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Màn hội thoại', () {
    testWidgets('can_reply=false khoá ô trả lời và hiện lý do', (tester) async {
      final repo = FakeInboxRepository()
        ..conversation = sampleConversation(
          canReply: false,
          blocked: 'Đã quá 24 giờ kể từ tin cuối của khách',
        );
      await _pump(
        tester,
        repo: repo,
        screen: const InboxConversationScreen(
          conversationId: 'c1',
          workspaceId: 'ws',
        ),
      );
      expect(find.byKey(const Key('inbox_reply_blocked')), findsOneWidget);
      expect(
        find.text('Đã quá 24 giờ kể từ tin cuối của khách'),
        findsOneWidget,
      );
      final input = tester.widget<TextField>(
        find.byKey(const Key('inbox_reply_input')),
      );
      expect(input.enabled, isFalse);
      expect(repo.readCalls, 1);
    });

    testWidgets('ghi chú nội bộ khác màu và có nhãn', (tester) async {
      final repo = FakeInboxRepository()
        ..messagePage = InboxMessagePage(
          items: [
            sampleMessage(id: 'm1'),
            sampleMessage(
              id: 'n1',
              kind: InboxMessageKind.note,
              direction: InboxDirection.outbound,
              body: 'Khách quen',
            ),
          ],
        );
      await _pump(
        tester,
        repo: repo,
        screen: const InboxConversationScreen(
          conversationId: 'c1',
          workspaceId: 'ws',
        ),
      );
      expect(find.text(inboxNoteLabel), findsOneWidget);
      Color? colorOf(String id) {
        final box = tester.widget<Container>(
          find.byKey(Key('inbox_message_$id')),
        );
        return (box.decoration as BoxDecoration?)?.color ?? box.color;
      }

      expect(colorOf('n1'), inboxNoteColor);
      expect(colorOf('m1'), isNot(inboxNoteColor));
    });
  });
}
