import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/conversation_home_views.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_access_provider.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';
import 'package:webtui_chat/features/moderation/domain/repositories/moderation_repository.dart';
import 'package:webtui_chat/features/profile/application/use_cases/profile_use_cases.dart';
import 'package:webtui_chat/features/profile/domain/entities/user_profile.dart';
import 'package:webtui_chat/features/profile/domain/repositories/avatar_repository.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';
import 'package:webtui_chat/features/profile/presentation/controllers/profile_controller.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    List<ConversationSummary> channels = const [],
    List<ContactSummary> members = const [],
    Future<Result<List<ConversationSummary>>> Function()? loadChannels,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repository(
      channels: channels,
      members: members,
      loadChannels: loadChannels,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: ContactsHomeView(workspaceId: 'ws')),
        ),
        GoRoute(
          path: '/conversations/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Phòng ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/channels/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Chi tiết ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final profileRepository = _Profile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moderationRepositoryProvider.overrideWithValue(_Moderation()),
          customerTicketAccessProvider.overrideWith(
            (ref) => const CustomerTicketAccess(
              serverSupported: true,
              permissionsLoaded: true,
              canView: true,
              canReply: true,
            ),
          ),
          profileControllerProvider.overrideWith(
            (ref) => ProfileController(
              loadProfileUseCase: LoadProfileUseCase(profileRepository),
              updateProfileUseCase: UpdateProfileUseCase(profileRepository),
              changeAvatarUseCase: ChangeAvatarUseCase(
                pickerRepository: _Picker(),
                uploadRepository: _Upload(),
                profileRepository: profileRepository,
                workspaceSessionRepository: _Session(),
              ),
            )..load(),
          ),
          conversationHomeControllerProvider.overrideWith(
            (ref, id) => ConversationHomeController(
              workspaceId: id,
              loadConversationHomeUseCase: LoadConversationHomeUseCase(
                conversationRepository: repository,
                workspaceSessionRepository: _Session(),
              ),
              openDirectConversationUseCase: OpenDirectConversationUseCase(
                repository,
              ),
              openPrivateChannelSessionUseCase:
                  OpenPrivateChannelSessionUseCase(repository),
            )..load(),
          ),
        ],
        child: MaterialApp.router(
          theme: WebTuiTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> openChannelsTab(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ChoiceChip, 'Nhóm'));
    await tester.pumpAndSettle();
  }

  testWidgets('hai tab Đồng nghiệp / Kênh, mặc định Đồng nghiệp', (
    tester,
  ) async {
    await pump(
      tester,
      members: [_member('u-lan', 'Lan')],
      channels: [_channel('du-an', 'Dự án A')],
    );

    final tabs = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(
      [for (final chip in tabs) (chip.label as Text).data],
      ['Đồng nghiệp', 'Nhóm'],
    );
    expect(tabs.first.selected, isTrue);
    for (final chip in find.byType(ChoiceChip).evaluate()) {
      expect(
        tester.getSize(find.byWidget(chip.widget)).height,
        greaterThanOrEqualTo(44),
      );
    }
    expect(find.text('Bạn bè trong workspace'), findsNothing);
    expect(find.text('Lan'), findsOneWidget);
    expect(find.text('Dự án A'), findsNothing);
  });

  testWidgets('tab Kênh: kênh đã tham gia (cả kênh chưa có tin) và có thể '
      'tham gia, tìm theo tên, bấm mở chat', (tester) async {
    await pump(
      tester,
      members: [_member('u-lan', 'Lan')],
      channels: [
        _channel('chung', 'Chung', slug: 'general'),
        _channel('du-an', 'Dự án A', lastMessage: true),
        _channel('im-lang', 'Nhóm im lặng'),
        _channel('mo', 'Kênh mở', member: false),
        _channel(
          'orders',
          'Đơn hàng',
          slug: 'orders',
          automation: true,
          lastMessage: true,
        ),
      ],
    );
    await openChannelsTab(tester);

    expect(find.text('Lan'), findsNothing);
    expect(find.text('Nhóm đã tham gia'), findsOneWidget);
    expect(find.text('Chung'), findsOneWidget);
    expect(find.text('Dự án A'), findsOneWidget);
    expect(find.text('Nhóm im lặng'), findsOneWidget);
    expect(find.text('Nhóm có thể tham gia'), findsOneWidget);
    expect(find.text('Kênh mở'), findsOneWidget);
    // Kênh bot nghiệp vụ ở tab Nghiệp vụ của Tin nhắn, không lặp ở đây.
    expect(find.text('Đơn hàng'), findsNothing);

    await tester.enterText(find.byType(TextField), 'im lặng');
    await tester.pumpAndSettle();
    expect(find.text('Nhóm im lặng'), findsOneWidget);
    expect(find.text('Dự án A'), findsNothing);
    expect(find.text('Kênh mở'), findsNothing);

    await tester.tap(find.text('Nhóm im lặng'));
    await tester.pumpAndSettle();
    expect(find.text('Phòng im-lang'), findsOneWidget);
  });

  testWidgets('tab Kênh: rỗng thì báo "Chưa có nhóm nào"', (tester) async {
    await pump(tester, members: [_member('u-lan', 'Lan')]);
    await openChannelsTab(tester);

    expect(find.text('Chưa có nhóm nào'), findsOneWidget);
  });

  testWidgets('tab Kênh: đang tải rồi lỗi có nút Thử lại', (tester) async {
    var calls = 0;
    final pending = Completer<Result<List<ConversationSummary>>>();
    await pump(
      tester,
      settle: false,
      loadChannels: () {
        calls++;
        if (calls == 1) return pending.future;
        return Future.value(Success([_channel('du-an', 'Dự án A')]));
      },
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Nhóm'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WebTuiLoadingState), findsOneWidget);

    pending.complete(
      const FailureResult(
        Failure(kind: FailureKind.network, message: 'Mất kết nối'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không tải được danh sách nhóm'), findsOneWidget);

    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Dự án A'), findsOneWidget);
    expect(calls, 2);
  });
}

ConversationSummary _channel(
  String id,
  String title, {
  String? slug,
  bool member = true,
  bool automation = false,
  bool lastMessage = false,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: ConversationKind.channel,
    title: title,
    preview: 'Mô tả kênh',
    updatedAt: DateTime.utc(2026, 11, 15, 8),
    membershipStatus: member ? MembershipStatus.active : MembershipStatus.none,
    isAutomation: automation,
    slug: slug,
    lastMessageAt: lastMessage ? DateTime.utc(2026, 11, 15, 9) : null,
  );
}

ContactSummary _member(String id, String name) {
  return ContactSummary(
    userId: id,
    displayName: name,
    username: id,
    email: '$id@example.com',
    status: 'active',
  );
}

final class _Repository implements ConversationRepository {
  _Repository({
    required this.channels,
    required this.members,
    this.loadChannels,
  });

  final List<ConversationSummary> channels;
  final List<ContactSummary> members;
  final Future<Result<List<ConversationSummary>>> Function()? loadChannels;

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async => const Success([]);

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) => loadChannels?.call() ?? Future.value(Success(channels));

  @override
  Future<Result<List<ContactSummary>>> listContacts() async =>
      const Success([]);

  @override
  Future<Result<List<ContactSummary>>> listContactRequests({
    String status = 'all',
  }) async => const Success([]);

  @override
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) async => Success(members);

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) async => const Success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Moderation implements ModerationRepository {
  @override
  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  }) async => const Success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Profile implements ProfileRepository {
  @override
  Future<Result<UserProfile>> me() async => const Success(
    UserProfile(
      id: 'u-me',
      email: 'me@example.com',
      username: 'me',
      displayName: 'Tôi',
      status: 'active',
      locale: 'vi',
      timezone: 'Asia/Ho_Chi_Minh',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Picker implements AvatarPickerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Upload implements AvatarUploadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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
