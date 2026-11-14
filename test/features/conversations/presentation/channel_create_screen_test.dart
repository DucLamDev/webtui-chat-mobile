import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/create_group_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/channel_create_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/channel_create_screen.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  Future<_Repo> pump(
    WidgetTester tester, {
    Set<String> failFor = const {},
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(failFor: failFor);
    final router = GoRouter(
      initialLocation: '/channels/new',
      routes: [
        GoRoute(
          path: '/channels/new',
          builder: (_, _) =>
              const GroupCreateView(workspaceId: 'ws', currentUserId: 'me'),
        ),
        GoRoute(
          path: '/conversations/:id',
          builder: (_, state) =>
              Scaffold(body: Text('phòng ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationHomeControllerProvider.overrideWith(
            (ref, id) => ConversationHomeController(
              workspaceId: id,
              loadConversationHomeUseCase: LoadConversationHomeUseCase(
                conversationRepository: repo,
                workspaceSessionRepository: _Session(),
              ),
              openDirectConversationUseCase: OpenDirectConversationUseCase(
                repo,
              ),
              openPrivateChannelSessionUseCase:
                  OpenPrivateChannelSessionUseCase(repo),
            )..load(),
          ),
          createGroupUseCaseProvider.overrideWithValue(
            CreateGroupUseCase(repo),
          ),
        ],
        child: MaterialApp.router(
          theme: WebTuiTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  bool buttonEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('group-create-button')))
      .enabled;

  testWidgets('danh sách bỏ mình, trùng và người chờ kết bạn', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('group-member-me')), findsNothing);
    expect(find.byKey(const Key('group-member-pending')), findsNothing);
    expect(find.byKey(const Key('group-member-u1')), findsOneWidget);
    expect(find.byKey(const Key('group-member-u2')), findsOneWidget);
    expect(find.text('Đã chọn 0'), findsOneWidget);
    expect(find.text('Công khai'), findsNothing);
    expect(find.text('Slug'), findsNothing);
  });

  testWidgets('nút Tạo nhóm chỉ bấm được khi có tên', (tester) async {
    await pump(tester);
    expect(buttonEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const Key('group-name-field')), '   ');
    await tester.pump();
    expect(buttonEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const Key('group-name-field')), 'Nhóm A');
    await tester.pump();
    expect(buttonEnabled(tester), isTrue);
  });

  testWidgets('chọn, bỏ chọn, tìm; tạo nhóm riêng tư thêm đúng người', (
    tester,
  ) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const Key('group-member-u1')));
    await tester.tap(find.byKey(const Key('group-member-u2')));
    await tester.pump();
    expect(find.text('Đã chọn 2'), findsOneWidget);
    expect(find.byKey(const Key('group-chip-u1')), findsOneWidget);
    // Bỏ chọn bằng chip.
    await tester.tap(find.byKey(const Key('group-chip-u2')));
    await tester.pump();
    expect(find.text('Đã chọn 1'), findsOneWidget);
    // Tìm theo tên.
    await tester.enterText(
      find.byKey(const Key('group-member-search')),
      'khong co ai',
    );
    await tester.pump();
    expect(find.text('Không tìm thấy'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('group-member-search')), '');
    await tester.pump();

    await tester.enterText(find.byKey(const Key('group-name-field')), 'Nhóm A');
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-create-button')));
    await tester.pumpAndSettle();

    expect(repo.createdVisibility, ChannelVisibility.private);
    expect(repo.createdName, 'Nhóm A');
    expect(repo.added, ['u1']);
    expect(find.text('phòng ch-1'), findsOneWidget);
  });

  testWidgets('thêm lỗi một phần: vẫn mở nhóm và báo số người lỗi', (
    tester,
  ) async {
    final repo = await pump(tester, failFor: {'u2'});
    await tester.tap(find.byKey(const Key('group-member-u1')));
    await tester.tap(find.byKey(const Key('group-member-u2')));
    await tester.enterText(find.byKey(const Key('group-name-field')), 'Nhóm B');
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-create-button')));
    await tester.pumpAndSettle();
    expect(repo.added, ['u1', 'u2']);
    expect(find.text('phòng ch-1'), findsOneWidget);
    expect(find.text('Không thêm được 1 người'), findsOneWidget);
  });
}

ContactSummary _person(String id, String name, {String? status}) {
  return ContactSummary(
    userId: id,
    displayName: name,
    username: id,
    email: '$id@example.com',
    status: 'active',
    contactStatus: status,
  );
}

final class _Session implements WorkspaceSessionRepository {
  @override
  Future<String?> readActiveWorkspaceId() async => 'ws';

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {}

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {}
}

final class _Repo implements ConversationRepository {
  _Repo({this.failFor = const {}});

  final Set<String> failFor;
  ChannelVisibility? createdVisibility;
  String? createdName;
  final added = <String>[];

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async => const Success([]);

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) async => const Success([]);

  @override
  Future<Result<List<ContactSummary>>> listContacts() async => Success([
    _person('u1', 'An Nguyễn', status: 'accepted'),
    _person('me', 'Tôi'),
    _person('pending', 'Chờ kết bạn', status: 'pending'),
  ]);

  @override
  Future<Result<List<ContactSummary>>> listContactRequests({
    String status = 'all',
  }) async => const Success([]);

  @override
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) async => Success([
    _person('u1', 'An Nguyễn'),
    _person('u2', 'Bình Trần'),
    _person('me', 'Tôi'),
  ]);

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) async => const Success([]);

  @override
  Future<Result<ConversationSummary>> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) async {
    createdVisibility = visibility;
    createdName = name;
    return Success(
      ConversationSummary(
        id: 'ch-1',
        workspaceId: workspaceId,
        channelId: 'ch-1',
        kind: ConversationKind.channel,
        title: name,
        preview: '',
        updatedAt: DateTime.utc(2026, 11, 14),
        channelVisibility: visibility,
      ),
    );
  }

  @override
  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    added.add(userId);
    if (failFor.contains(userId)) {
      return const FailureResult(
        Failure(kind: FailureKind.server, message: 'Không thêm được'),
      );
    }
    return Success(
      ChannelMember(
        channelId: channelId,
        userId: userId,
        email: '$userId@example.com',
        username: userId,
        displayName: userId,
        status: 'active',
        joinedAt: DateTime.utc(2026, 11, 14),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
