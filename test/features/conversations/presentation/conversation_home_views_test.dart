import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/approvals/application/approval_access_policy.dart';
import 'package:webtui_chat/features/approvals/presentation/controllers/approval_access_provider.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/messages_tab_unread.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/notice_bot_identity.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/conversation_home_views.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_access_provider.dart';
import 'package:webtui_chat/features/inbox/application/inbox_access_policy.dart';
import 'package:webtui_chat/features/inbox/presentation/controllers/inbox_access_provider.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';
import 'package:webtui_chat/features/moderation/domain/repositories/moderation_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool automation,
    List<ConversationSummary> channels = const [],
    List<ConversationSummary> directs = const [],
    VoidCallback? onCompose,
    List<BlockedUser> blocked = const [],
    bool showTabBadge = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repository(directs: directs, channels: channels);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noticeBotIdentityProvider.overrideWithValue(
            NoticeBotIdentity.fromOrganization(name: 'Công ty A'),
          ),
          moderationRepositoryProvider.overrideWithValue(_Moderation(blocked)),
          approvalAccessProvider.overrideWith(
            (ref, id) => const ApprovalAccess(
              serverSupported: true,
              permissionsLoaded: true,
              canView: true,
            ),
          ),
          customerTicketAccessProvider.overrideWith(
            (ref) => const CustomerTicketAccess(
              serverSupported: true,
              permissionsLoaded: true,
              canView: true,
              canReply: true,
            ),
          ),
          customerTicketUnansweredCountProvider.overrideWith(
            (ref, id) async => 2,
          ),
          inboxAccessProvider.overrideWith(
            (ref, id) => const InboxAccess(
              serverSupported: true,
              permissionsLoaded: true,
              canView: true,
            ),
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
              automationEnabled: automation,
            )..load(),
          ),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: Scaffold(
            body: showTabBadge
                ? Column(
                    children: [
                      // Cùng nguồn với số đỏ tab Tin nhắn ở thanh dưới.
                      Consumer(
                        builder: (context, ref, _) => Text(
                          'badge ${ref.watch(messagesTabUnreadCountProvider('ws'))}',
                          key: const ValueKey('tab-badge'),
                        ),
                      ),
                      Expanded(
                        child: MessagesHomeView(
                          workspaceId: 'ws',
                          onCompose: onCompose,
                        ),
                      ),
                    ],
                  )
                : MessagesHomeView(workspaceId: 'ws', onCompose: onCompose),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> chipLabels(WidgetTester tester) => [
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
      (chip.label as Text).data!,
  ];

  testWidgets('bộ lọc đúng 5 chip khi bật nghiệp vụ, không dải kênh nhanh', (
    tester,
  ) async {
    await pump(
      tester,
      automation: true,
      directs: [_item('dm', 'Lan', channel: false)],
      channels: [
        _item('orders', 'Đơn hàng', automation: true, slug: 'orders'),
        _item('team', 'Nhóm team'),
      ],
    );
    expect(chipLabels(tester), [
      'Tất cả',
      'Nhóm',
      'Cá nhân',
      'Nghiệp vụ',
      'Chưa đọc',
    ]);
    expect(find.text('Ghim'), findsNothing);
    expect(find.byKey(const ValueKey('quick-channel-strip')), findsNothing);
    expect(find.text('Lan'), findsOneWidget);
    expect(find.text('Nhóm team'), findsOneWidget);
    expect(find.text('Đơn hàng'), findsNothing);
  });

  testWidgets('tắt nghiệp vụ: chỉ còn 4 chip', (tester) async {
    await pump(
      tester,
      automation: false,
      channels: [_item('team', 'Nhóm team')],
    );
    expect(chipLabels(tester), ['Tất cả', 'Nhóm', 'Cá nhân', 'Chưa đọc']);
  });

  testWidgets('tab Nghiệp vụ: mục đặc biệt và kênh bot là dòng hội thoại', (
    tester,
  ) async {
    await pump(
      tester,
      automation: true,
      channels: [
        _item('orders', 'Đơn hàng', automation: true, slug: 'orders'),
        _item('renew', 'Gia hạn', automation: true, slug: 'gia-han'),
      ],
    );
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Nghiệp vụ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Nghiệp vụ'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsNothing);
    for (final key in [
      'business_entry',
      'approval_entry',
      'inbox_entry',
      'customer_ticket_entry',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
      expect(
        tester.widget(find.byKey(Key(key))),
        isA<WebTuiConversationListItem>(),
      );
    }
    expect(
      find.widgetWithText(WebTuiConversationListItem, 'Đơn hàng'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(WebTuiConversationListItem, 'Gia hạn'),
      findsOneWidget,
    );
  });

  testWidgets('bỏ tiêu đề lớn; nút soạn bên trái ô tìm, cùng một hàng', (
    tester,
  ) async {
    var composed = 0;
    await pump(
      tester,
      automation: true,
      channels: [_item('team', 'Nhóm team')],
      onCompose: () => composed++,
    );
    expect(find.text('Tin nhắn'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final compose = find.byKey(const Key('compose_button'));
    final search = find.byType(WebTuiSearchBar);
    expect(find.text('Tìm tin nhắn, nhóm...'), findsOneWidget);
    expect(
      tester.getCenter(compose).dx,
      lessThan(tester.getTopLeft(search).dx),
      reason: 'nút soạn nằm bên trái ô tìm',
    );
    expect(
      (tester.getCenter(compose).dy - tester.getCenter(search).dy).abs(),
      lessThan(2),
      reason: 'cùng một hàng',
    );
    expect(find.byIcon(WebTuiIcons.compose), findsOneWidget);
    await tester.tap(compose);
    expect(composed, 1);
  });

  testWidgets('không truyền onCompose thì không có nút soạn', (tester) async {
    await pump(tester, automation: false, channels: [_item('t', 'Nhóm')]);
    expect(find.byKey(const Key('compose_button')), findsNothing);
  });

  testWidgets('chip lọc: chọn = nền xanh chữ trắng, chưa chọn = viền xám', (
    tester,
  ) async {
    await pump(tester, automation: true, channels: [_item('t', 'Nhóm')]);
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(chips.first.selected, isTrue);
    expect(chips.first.selectedColor, WebTuiColors.primary);
    expect(chips.first.labelStyle!.color, WebTuiColors.textOnPrimary);
    expect(chips[1].selected, isFalse);
    expect(chips[1].backgroundColor, WebTuiColors.surface);
    expect(chips[1].side!.color, isNot(WebTuiColors.primary));

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Chưa đọc'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Chưa đọc'));
    await tester.pumpAndSettle();
    final after = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(after[0].selected, isFalse);
    expect(after.last.selected, isTrue);
  });

  testWidgets('chip lọc: vùng bấm cao ≥ 48dp, thiếu chỗ thì cuộn ngang', (
    tester,
  ) async {
    await pump(
      tester,
      automation: true,
      directs: [_item('dm', 'Lan', channel: false, unread: 12)],
      channels: [
        _item('t', 'Nhóm', unread: 3),
        _item('o', 'Đơn hàng', automation: true, slug: 'orders', unread: 1),
      ],
    );
    // Màn hẹp: không thu nhỏ cả hàng (chữ, vùng bấm giữ nguyên) mà cuộn ngang.
    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('inbox-filter-chips'));
    expect(
      find.descendant(of: row, matching: find.byType(FittedBox)),
      findsNothing,
    );
    for (final chip in find.byType(ChoiceChip).evaluate()) {
      expect(
        tester.getSize(find.byWidget(chip.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: row, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    // Chip cuối nằm ngoài màn vẫn cuộn tới và bấm được.
    final last = find.byType(ChoiceChip).last;
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChoiceChip>(find.byType(ChoiceChip).last).selected,
      isTrue,
    );
  });

  testWidgets('dòng chat: kênh = ô vuông + biểu tượng, người = ảnh tròn', (
    tester,
  ) async {
    await pump(
      tester,
      automation: false,
      directs: [_item('dm', 'Bùi Tú Thiên', channel: false, unread: 2)],
      channels: [
        _item('g', 'Chung', slug: 'general'),
        _item('b', 'Bảng tin', slug: 'announcements'),
        _item('o', 'Đơn hàng', slug: 'orders'),
        _item('t', 'Ticket', slug: 'ticket'),
        _item('c', 'Trò chuyện'),
        _item('k', 'Kế toán', slug: 'ke-toan'),
        _item('p', 'Nhóm kín', private: true),
        _item('x', 'Dự án X'),
      ],
    );
    ({bool square, IconData? icon}) look(String title) {
      final item = tester.widget<WebTuiConversationListItem>(
        find.widgetWithText(WebTuiConversationListItem, title),
      );
      return (
        square: item.squareAvatar || item.avatarIcon != null,
        icon: item.avatarIcon,
      );
    }

    expect(look('Chung').icon, WebTuiIcons.channel);
    expect(look('Bảng tin').icon, WebTuiIcons.announcement);
    expect(look('Đơn hàng').icon, WebTuiIcons.orders);
    // Kênh hệ thống (Ticket) bị ẩn khỏi app.
    expect(find.text('Ticket'), findsNothing);
    expect(look('Trò chuyện').icon, WebTuiIcons.chitchat);
    expect(look('Kế toán').icon, WebTuiIcons.accounting);
    expect(look('Nhóm kín').icon, WebTuiIcons.channelPrivate);
    expect(look('Dự án X').icon, WebTuiIcons.channel);
    expect(look('Chung').square, isTrue);
    expect(look('Bùi Tú Thiên').icon, isNull);
    expect(look('Bùi Tú Thiên').square, isFalse);
    final avatar = tester.widget<WebTuiAvatar>(
      find.descendant(
        of: find.widgetWithText(WebTuiConversationListItem, 'Bùi Tú Thiên'),
        matching: find.byType(WebTuiAvatar),
      ),
    );
    expect(avatar.square, isFalse);
  });

  testWidgets('dòng ghim có biểu tượng ghim, số chưa đọc tròn xanh', (
    tester,
  ) async {
    await pump(
      tester,
      automation: false,
      channels: [
        _item('a', 'Kênh ghim', favorite: true, unread: 3),
        _item('b', 'Kênh thường'),
      ],
    );
    final pinned = find.widgetWithText(WebTuiConversationListItem, 'Kênh ghim');
    final plain = find.widgetWithText(
      WebTuiConversationListItem,
      'Kênh thường',
    );
    expect(
      find.descendant(of: pinned, matching: find.byIcon(WebTuiIcons.pin)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: plain, matching: find.byIcon(WebTuiIcons.pin)),
      findsNothing,
    );
    expect(
      find.descendant(of: pinned, matching: find.byType(WebTuiUnreadBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pinned, matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('chat bot thông báo: tên tổ chức + Bot và nhãn BOT', (
    tester,
  ) async {
    await pump(
      tester,
      automation: false,
      channels: [
        _item('n', 'Thông báo', notice: true, favorite: true, unread: 2),
        _item('g', 'Chung'),
      ],
    );
    final bot = find.widgetWithText(
      WebTuiConversationListItem,
      'Công ty A Bot',
    );
    expect(bot, findsOneWidget);
    expect(
      find.descendant(of: bot, matching: find.text('BOT')),
      findsOneWidget,
    );
    expect(find.text('BOT'), findsOneWidget, reason: 'chỉ chat bot có nhãn');
  });

  testWidgets(
    'số đỏ tab Tin nhắn không nhảy khi đổi chip / gõ tìm, bỏ người đã chặn',
    (tester) async {
      await pump(
        tester,
        automation: true,
        showTabBadge: true,
        blocked: [
          BlockedUser(
            blockedUserId: 'user-binh',
            createdAt: DateTime.utc(2026, 11, 1),
          ),
        ],
        directs: [
          _item('dm-a', 'An', channel: false, unread: 2, peer: 'user-an'),
          _item('dm-b', 'Bình', channel: false, unread: 5, peer: 'user-binh'),
          _item('dm-c', 'Chi', channel: false, unread: 7, muted: true),
        ],
        channels: [
          _item('team', 'Nhóm team', unread: 3),
          _item(
            'orders',
            'Đơn hàng',
            automation: true,
            slug: 'orders',
            unread: 4,
          ),
        ],
      );
      String badge() =>
          tester.widget<Text>(find.byKey(const ValueKey('tab-badge'))).data!;

      // An 2 + Nhóm team 3 + Đơn hàng 4; Bình bị chặn, Chi tắt tiếng.
      expect(badge(), 'badge 9');
      // Nhãn chip có kèm số (vd. "Nhóm 1") nên bấm theo vị trí: Chưa đọc,
      // Nghiệp vụ, Cá nhân, Nhóm rồi về Tất cả.
      expect(chipLabels(tester).length, 5);
      for (final index in [4, 3, 2, 1, 0]) {
        // Hàng chip cuộn ngang: cuộn tới chip trước khi bấm.
        await tester.ensureVisible(find.byType(ChoiceChip).at(index));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ChoiceChip).at(index));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ChoiceChip>(find.byType(ChoiceChip).at(index)).selected,
          isTrue,
          reason: 'đã chọn ${chipLabels(tester)[index]}',
        );
        expect(badge(), 'badge 9', reason: chipLabels(tester)[index]);
      }
      await tester.enterText(find.byType(TextField).first, 'An');
      await tester.pumpAndSettle();
      expect(badge(), 'badge 9');
    },
  );
}

ConversationSummary _item(
  String id,
  String title, {
  bool channel = true,
  bool automation = false,
  String? slug,
  bool favorite = false,
  int unread = 0,
  bool notice = false,
  bool private = false,
  String? peer,
  bool muted = false,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: channel ? ConversationKind.channel : ConversationKind.direct,
    title: title,
    preview: 'xin chào',
    updatedAt: DateTime.utc(2026, 7, 16),
    channelVisibility: !channel
        ? ChannelVisibility.direct
        : private
        ? ChannelVisibility.private
        : ChannelVisibility.public,
    favorite: favorite,
    unreadCount: unread,
    noticeBot: notice,
    membershipStatus: MembershipStatus.active,
    isAutomation: automation,
    slug: slug,
    peerUserId: peer,
    muted: muted,
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

final class _Moderation implements ModerationRepository {
  _Moderation([this.blocked = const []]);

  final List<BlockedUser> blocked;

  @override
  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  }) async => Success(blocked);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Repository implements ConversationRepository {
  _Repository({required this.directs, required this.channels});

  final List<ConversationSummary> directs;
  final List<ConversationSummary> channels;

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async => Success(directs);

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) async => Success(channels);

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
  }) async => const Success([]);

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) async => const Success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
