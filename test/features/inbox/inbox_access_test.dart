import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/inbox/application/inbox_access_policy.dart';
import 'package:webtui_chat/features/inbox/domain/entities/inbox.dart';
import 'package:webtui_chat/features/inbox/presentation/controllers/inbox_access_provider.dart';
import 'package:webtui_chat/features/inbox/presentation/screens/inbox_conversation_screen.dart';
import 'package:webtui_chat/features/inbox/presentation/screens/inbox_list_screen.dart';
import 'package:webtui_chat/features/inbox/presentation/widgets/inbox_entry.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/permission_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

import 'support/inbox_fakes.dart';

PermissionSet _perms(List<String> codes) => PermissionSet([
  for (final code in codes)
    WorkspacePermission(
      id: code,
      code: code,
      module: 'inbox',
      action: code,
      name: code,
    ),
]);

InboxAccess _access({
  bool server = true,
  PermissionSet? permissions,
  bool loading = false,
  String? active = 'ws',
  String? requested,
}) => inboxAccessFor(
  serverSupported: server,
  permissions: permissions,
  permissionsLoading: loading,
  activeWorkspaceId: active,
  requestedWorkspaceId: requested,
);

SelfHostedServerDiscovery _server({bool inbox = true}) =>
    SelfHostedServerDiscovery(
      instanceId: '11111111-1111-4111-8111-111111111111',
      discoveryVersion: '1',
      domain: 'chat.company.example',
      name: 'Máy chủ thử',
      apiBaseUri: Uri.parse('https://chat.company.example'),
      wsBaseUri: Uri.parse('wss://chat.company.example/ws'),
      registrationMode: 'closed',
      appVersion: '1.0.0',
      apiContractVersion: 1,
      serverVersion: '1.0.0',
      minimumSupportedMobileVersion: '1.0.0',
      capabilities: SelfHostedCapabilities(omnichannelInbox: inbox),
      zoneKind: 'dedicated',
    );

final class _Workspaces implements WorkspaceRepository {
  @override
  Future<Result<List<Workspace>>> listMine() async => const Success([
    Workspace(id: 'ws', slug: 'ws', name: 'WS', plan: 'free', status: 'active'),
  ]);

  @override
  Future<Result<Workspace>> get(String workspaceId) async => const Success(
    Workspace(id: 'ws', slug: 'ws', name: 'WS', plan: 'free', status: 'active'),
  );
}

final class _Permissions implements PermissionRepository {
  _Permissions(this.codes);

  final List<String> codes;

  @override
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  ) async => Success([
    for (final code in codes)
      WorkspacePermission(
        id: code,
        code: code,
        module: 'inbox',
        action: code,
        name: code,
      ),
  ]);
}

final class _Session implements WorkspaceSessionRepository {
  @override
  Future<String?> readActiveWorkspaceId() async => 'ws';

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {}

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {}
}

/// Đi qua provider quyền thật: chỉ giả máy chủ discovery và dữ liệu workspace.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool inbox,
  required List<String> codes,
  FakeInboxRepository? repo,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeServerDiscoveryProvider.overrideWithValue(_server(inbox: inbox)),
        workspaceRepositoryProvider.overrideWithValue(_Workspaces()),
        permissionRepositoryProvider.overrideWithValue(_Permissions(codes)),
        workspaceSessionRepositoryProvider.overrideWithValue(_Session()),
        inboxRepositoryProvider.overrideWithValue(
          repo ?? (FakeInboxRepository()..pages = []),
        ),
        inboxRealtimeRepositoryProvider.overrideWithValue(FakeInboxRealtime()),
        inboxCurrentUserIdProvider.overrideWith((ref) async => 'me'),
      ],
      child: MaterialApp(theme: WebTuiTheme.light(), home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('inboxServerSupported', () {
    test('không có discovery hoặc capability tắt / thiếu thì false', () {
      expect(inboxServerSupported(null), isFalse);
      expect(inboxServerSupported(_server(inbox: false)), isFalse);
    });

    test('capability bật thì true', () {
      expect(inboxServerSupported(_server()), isTrue);
    });
  });

  group('inboxAccessFor', () {
    test('máy chủ không hỗ trợ thì không vào được, kể cả có quyền', () {
      final access = _access(
        server: false,
        permissions: _perms([inboxViewPermission, inboxReplyPermission]),
      );
      expect(access.serverSupported, isFalse);
      expect(access.canView, isFalse);
      expect(access.canReply, isFalse);
      expect(access.isPending, isFalse);
    });

    test('đang tải quyền thì chờ, chưa cho xem', () {
      final access = _access(loading: true);
      expect(access.isPending, isTrue);
      expect(access.canView, isFalse);
    });

    test('permissions == null (đã tải xong) thì không xem được', () {
      final access = _access();
      expect(access.isPending, isFalse);
      expect(access.canView, isFalse);
      expect(access.canReply, isFalse);
    });

    test('thiếu inbox.view thì không xem được, kể cả có inbox.reply', () {
      final access = _access(permissions: _perms([inboxReplyPermission]));
      expect(access.canView, isFalse);
      expect(access.canReply, isFalse);
    });

    test('chỉ có inbox.view thì xem được, không thao tác', () {
      final access = _access(permissions: _perms([inboxViewPermission]));
      expect(access.canView, isTrue);
      expect(access.canReply, isFalse);
    });

    test('có inbox.view và inbox.reply thì xem và thao tác', () {
      final access = _access(
        permissions: _perms([inboxViewPermission, inboxReplyPermission]),
      );
      expect(access.canView, isTrue);
      expect(access.canReply, isTrue);
    });

    test(
      'workspace khác workspace đang mở: cho vào, máy chủ kiểm bằng 403',
      () {
        final access = _access(
          permissions: _perms(const []),
          requested: 'khac',
        );
        expect(access.canView, isTrue);
        expect(access.canReply, isTrue);
        expect(access.isPending, isFalse);
        // Dù quyền của workspace đang mở đang tải hay chưa có.
        expect(_access(loading: true, requested: 'khac').canView, isTrue);
        expect(_access(requested: 'khac').canView, isTrue);
      },
    );

    test('workspace khác nhưng máy chủ không hỗ trợ vẫn bị chặn', () {
      expect(_access(server: false, requested: 'khac').canView, isFalse);
    });

    test('workspace yêu cầu trùng workspace đang mở thì xét quyền thật', () {
      final access = _access(permissions: _perms(const []), requested: ' ws ');
      expect(access.canView, isFalse);
    });
  });

  group('InboxEntry (provider quyền thật)', () {
    testWidgets('ẩn khi máy chủ tắt', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: InboxEntry(workspaceId: 'ws')),
        inbox: false,
        codes: [inboxViewPermission],
      );
      expect(find.byKey(const Key('inbox_entry')), findsNothing);
    });

    testWidgets('ẩn khi thiếu quyền xem', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: InboxEntry(workspaceId: 'ws')),
        inbox: true,
        codes: const [],
      );
      expect(find.byKey(const Key('inbox_entry')), findsNothing);
    });

    testWidgets('hiện khi máy chủ bật và đủ quyền', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: InboxEntry(workspaceId: 'ws')),
        inbox: true,
        codes: [inboxViewPermission],
      );
      expect(find.byKey(const Key('inbox_entry')), findsOneWidget);
    });
  });

  group('inboxAccessGate (provider quyền thật)', () {
    testWidgets('máy chủ cũ: báo chưa có hộp thư khách', (tester) async {
      await _pump(
        tester,
        const InboxListScreen(workspaceId: 'ws'),
        inbox: false,
        codes: [inboxViewPermission],
      );
      expect(find.byKey(const Key('inbox_no_access')), findsOneWidget);
      expect(find.text('Máy chủ này chưa có hộp thư khách.'), findsOneWidget);
    });

    testWidgets('thiếu quyền: hiện inbox_no_access', (tester) async {
      await _pump(
        tester,
        const InboxListScreen(workspaceId: 'ws'),
        inbox: true,
        codes: const [],
      );
      expect(find.byKey(const Key('inbox_no_access')), findsOneWidget);
      expect(find.text('Máy chủ này chưa có hộp thư khách.'), findsNothing);
    });

    testWidgets('đủ quyền: hiện nội dung danh sách', (tester) async {
      await _pump(
        tester,
        const InboxListScreen(workspaceId: 'ws'),
        inbox: true,
        codes: [inboxViewPermission],
        repo: FakeInboxRepository()
          ..pages = [
            InboxConversationPage(items: [sampleConversation(id: 'a')]),
          ],
      );
      expect(find.byKey(const Key('inbox_no_access')), findsNothing);
      expect(find.byKey(const Key('inbox_item_a')), findsOneWidget);
    });

    testWidgets('chỉ có inbox.view: màn hội thoại chỉ xem, không có ô nhập', (
      tester,
    ) async {
      await _pump(
        tester,
        const InboxConversationScreen(conversationId: 'c1', workspaceId: 'ws'),
        inbox: true,
        codes: [inboxViewPermission],
      );
      expect(find.byKey(const Key('inbox_view_only')), findsOneWidget);
      expect(find.text('Bạn chỉ có quyền xem hộp thư này.'), findsOneWidget);
      expect(find.byKey(const Key('inbox_reply_input')), findsNothing);
      expect(find.byKey(const Key('inbox_note_input')), findsNothing);
      expect(find.byKey(const Key('inbox_compose_mode')), findsNothing);
      final claim = tester.widget<OutlinedButton>(
        find.byKey(const Key('inbox_claim')),
      );
      expect(claim.onPressed, isNull);
      final tags = tester.widget<TextButton>(
        find.byKey(const Key('inbox_tags_edit')),
      );
      expect(tags.onPressed, isNull);
      final menu = tester.widget<PopupMenuButton<InboxStatus>>(
        find.byKey(const Key('inbox_status_menu')),
      );
      expect(menu.enabled, isFalse);
    });

    testWidgets('có inbox.reply: ô trả lời và nút nhận bật', (tester) async {
      await _pump(
        tester,
        const InboxConversationScreen(conversationId: 'c1', workspaceId: 'ws'),
        inbox: true,
        codes: [inboxViewPermission, inboxReplyPermission],
      );
      expect(find.byKey(const Key('inbox_view_only')), findsNothing);
      expect(find.byKey(const Key('inbox_reply_input')), findsOneWidget);
      final claim = tester.widget<OutlinedButton>(
        find.byKey(const Key('inbox_claim')),
      );
      expect(claim.onPressed, isNotNull);
    });

    testWidgets('có reply nhưng can_reply=false: ghi chú vẫn dùng được', (
      tester,
    ) async {
      await _pump(
        tester,
        const InboxConversationScreen(conversationId: 'c1', workspaceId: 'ws'),
        inbox: true,
        codes: [inboxViewPermission, inboxReplyPermission],
        repo: FakeInboxRepository()
          ..conversation = sampleConversation(
            canReply: false,
            blocked: 'Quá 24 giờ',
          ),
      );
      final input = tester.widget<TextField>(
        find.byKey(const Key('inbox_reply_input')),
      );
      expect(input.enabled, isFalse);
      await tester.tap(find.text('Ghi chú'));
      await tester.pump();
      final note = tester.widget<TextField>(
        find.byKey(const Key('inbox_note_input')),
      );
      expect(note.enabled, isTrue);
      final claim = tester.widget<OutlinedButton>(
        find.byKey(const Key('inbox_claim')),
      );
      expect(claim.onPressed, isNotNull);
    });
  });
}
