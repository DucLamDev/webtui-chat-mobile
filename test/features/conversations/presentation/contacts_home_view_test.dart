import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/components/webtui_person_silhouette.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_density.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/contact_directory.dart';
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
          builder: (context, state) => Scaffold(
            body: Text(
              'Phòng ${state.pathParameters['id']}'
              ' call=${state.uri.queryParameters['startCall']}',
            ),
          ),
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
    await tester.tap(find.byKey(const ValueKey('contacts-tab-channels')));
    await tester.pumpAndSettle();
  }

  ContactsUnderlineTabs tabsBar(WidgetTester tester) =>
      tester.widget<ContactsUnderlineTabs>(
        find.byKey(const ValueKey('contacts-tabs')),
      );

  testWidgets('hai tab Đồng nghiệp / Kênh, mặc định Đồng nghiệp', (
    tester,
  ) async {
    await pump(
      tester,
      members: [_member('u-lan', 'Lan')],
      channels: [_channel('du-an', 'Dự án A')],
    );

    final tabs = tabsBar(tester);
    expect([for (final tab in tabs.tabs) tab.label], ['Đồng nghiệp', 'Nhóm']);
    // Kèm số: 1 đồng nghiệp (ẩn chính mình), 1 kênh.
    expect([for (final tab in tabs.tabs) tab.count], [1, 1]);
    expect(tabs.selectedIndex, 0);
    for (final key in ['contacts-tab-colleagues', 'contacts-tab-channels']) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        greaterThanOrEqualTo(44),
      );
    }
    expect(find.byType(WebTuiLargeTitleBar), findsNothing);
    expect(find.text('Bạn bè'), findsNothing, reason: 'bỏ tiêu đề lớn');
    expect(find.byType(WebTuiSegmentedTabs), findsNothing);
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
    expect(find.text('Phòng im-lang call=null'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('contacts-tab-channels')));
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

  testWidgets('dòng đồng nghiệp: ảnh 48, cao 64, không nút khiên; nhấn giữ '
      'mở báo cáo / chặn', (tester) async {
    await pump(tester, members: [_member('u-lan', 'Lan')]);
    final row = find.byKey(const ValueKey('contact-u-lan'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, 64);
    final avatar = tester.widget<WebTuiAvatar>(
      find.descendant(of: row, matching: find.byType(WebTuiAvatar)),
    );
    expect(avatar.size, WebTuiListDensity.avatarSize);
    expect(
      find.text('u-lan@example.com'),
      findsNothing,
      reason: 'kiểu Zalo chỉ hiện tên; email chỉ khi trùng tên',
    );
    expect(
      find.descendant(of: row, matching: find.byType(IconButton)),
      findsNWidgets(2),
      reason: 'chỉ hai nút gọi, không nút khiên',
    );
    expect(find.byTooltip('Báo cáo hoặc chặn Lan'), findsNothing);
    expect(
      tester
          .widget<WebTuiSliverListSurface>(find.byType(WebTuiSliverListSurface))
          .dividerIndent,
      WebTuiListDensity.contactDividerIndent,
    );

    // Trình đọc màn hình: có gợi ý nhấn giữ và hành động riêng.
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.text('Lan'));
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );
    final actions = [
      for (final id in node.getSemanticsData().customSemanticsActionIds ?? [])
        CustomSemanticsAction.getAction(id),
    ];
    expect(
      actions.map((action) => action?.label),
      contains('Báo cáo hoặc chặn Lan'),
    );
    expect(
      actions.map((action) => action?.hint),
      contains('Báo cáo hoặc chặn Lan'),
      reason: 'gợi ý nhấn giữ cho trình đọc màn hình',
    );
    handle.dispose();

    await tester.longPress(find.text('Lan'));
    await tester.pumpAndSettle();
    expect(find.text('Báo cáo người dùng'), findsOneWidget);
    expect(find.text('Chặn người dùng'), findsOneWidget);
  });

  testWidgets('đồng nghiệp chưa có ảnh: hình người theo giới tính', (
    tester,
  ) async {
    await pump(
      tester,
      members: [
        _member('u-lan', 'Lan', gender: 'female'),
        _member('u-nam', 'Nam', gender: 'male'),
        _member('u-an', 'An'),
      ],
    );

    WebTuiAvatarGender genderOf(String name) => tester
        .widget<WebTuiPersonSilhouette>(
          find.descendant(
            of: find
                .ancestor(of: find.text(name), matching: find.byType(InkWell))
                .first,
            matching: find.byType(WebTuiPersonSilhouette),
          ),
        )
        .gender;
    expect(genderOf('Lan'), WebTuiAvatarGender.female);
    expect(genderOf('Nam'), WebTuiAvatarGender.male);
    // Chưa khai giới tính: hình người trung tính, không phải chữ cái tên.
    expect(genderOf('An'), WebTuiAvatarGender.neutral);
    expect(find.text('AN'), findsNothing);
  });

  testWidgets('bấm dòng đồng nghiệp vẫn mở chat riêng', (tester) async {
    await pump(tester, members: [_member('u-lan', 'Lan')]);
    await tester.tap(find.text('Lan'));
    await tester.pumpAndSettle();
    expect(find.text('Phòng dm-u-lan call=null'), findsOneWidget);
  });

  testWidgets('xếp A–Z có tiêu đề chữ cái, "#" ở cuối, trùng tên hiện email', (
    tester,
  ) async {
    await pump(
      tester,
      members: [
        _member('u-1', '123 Bot'),
        _member('u-2', 'Đức'),
        _member('u-3', 'Ánh'),
        _member('u-4', 'bình'),
        _member('u-5', 'Bình'),
        _member('u-6', 'Dũng'),
      ],
    );
    double top(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('contact-$id'))).dy;
    // Ánh (A) < bình/Bình (B) < Đức, Dũng (D) < 123 (#).
    expect(top('u-3'), lessThan(top('u-4')));
    expect(top('u-4'), lessThan(top('u-5')), reason: 'trùng tên: giữ thứ tự');
    expect(top('u-5'), lessThan(top('u-2')));
    expect(top('u-2'), lessThan(top('u-6')));
    expect(top('u-6'), lessThan(top('u-1')));
    for (final letter in ['A', 'B', 'D', '#']) {
      expect(find.byKey(ValueKey('contact-letter-$letter')), findsOneWidget);
    }
    expect(find.text('u-4@example.com'), findsOneWidget);
    expect(find.text('u-5@example.com'), findsOneWidget);
    expect(find.text('u-3@example.com'), findsNothing);
  });

  testWidgets('mỗi dòng có hai nút gọi bên phải tên; bấm gọi video mở chat '
      'với startCall=video', (tester) async {
    await pump(tester, members: [_member('u-lan', 'Lan')]);
    final row = find.byKey(const ValueKey('contact-u-lan'));
    final audio = find.descendant(
      of: row,
      matching: find.byKey(const ValueKey('contact-call-audio')),
    );
    final video = find.descendant(
      of: row,
      matching: find.byKey(const ValueKey('contact-call-video')),
    );
    expect(find.byTooltip('Gọi thoại'), findsOneWidget);
    expect(find.byTooltip('Gọi video'), findsOneWidget);
    final nameRight = tester.getTopRight(find.text('Lan')).dx;
    expect(tester.getTopLeft(audio).dx, greaterThan(nameRight));
    expect(
      tester.getTopLeft(video).dx,
      greaterThan(tester.getTopLeft(audio).dx),
    );
    for (final button in [audio, video]) {
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    }
    await tester.tap(video);
    await tester.pumpAndSettle();
    expect(find.text('Phòng dm-u-lan call=video'), findsOneWidget);
  });

  testWidgets('bấm gọi thoại mở chat với startCall=audio', (tester) async {
    await pump(tester, members: [_member('u-lan', 'Lan')]);
    await tester.tap(find.byKey(const ValueKey('contact-call-audio')));
    await tester.pumpAndSettle();
    expect(find.text('Phòng dm-u-lan call=audio'), findsOneWidget);
  });

  testWidgets('không mở được chat riêng thì không có nút gọi', (tester) async {
    await pump(
      tester,
      members: [
        _member('u-lan', 'Lan'),
        const ContactSummary(
          userId: 'u-cho',
          displayName: 'Chờ',
          username: 'cho',
          email: 'cho@example.com',
          status: 'active',
          contactStatus: 'pending',
        ),
      ],
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('contact-u-cho')),
        matching: find.byType(ContactCallButtons),
      ),
      findsNothing,
    );
    expect(find.byType(ContactCallButtons), findsOneWidget);
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

ContactSummary _member(String id, String name, {String? gender}) {
  return ContactSummary(
    userId: id,
    displayName: name,
    username: id,
    email: '$id@example.com',
    status: 'active',
    gender: gender,
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
  Future<Result<ConversationSummary>> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
  }) async => Success(
    ConversationSummary(
      id: 'dm-${participantIds.first}',
      workspaceId: workspaceId,
      channelId: 'dm-${participantIds.first}',
      kind: ConversationKind.direct,
      title: 'Lan',
      preview: '',
      updatedAt: DateTime.utc(2026, 11, 15),
      channelVisibility: ChannelVisibility.direct,
      participantIds: participantIds,
    ),
  );

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
