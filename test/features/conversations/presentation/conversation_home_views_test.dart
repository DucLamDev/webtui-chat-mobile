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
          moderationRepositoryProvider.overrideWithValue(_Moderation()),
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
            body: MessagesHomeView(workspaceId: 'ws', onCompose: onCompose),
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

  testWidgets('bộ lọc đúng 4 chip khi bật nghiệp vụ, không dải kênh nhanh', (
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
    expect(chipLabels(tester), ['Tất cả', 'Chưa đọc', 'Nghiệp vụ', 'Nhóm']);
    expect(find.text('Cá nhân'), findsNothing);
    expect(find.text('Ghim'), findsNothing);
    expect(find.byKey(const ValueKey('quick-channel-strip')), findsNothing);
    expect(find.text('Lan'), findsOneWidget);
    expect(find.text('Nhóm team'), findsOneWidget);
    expect(find.text('Đơn hàng'), findsNothing);
  });

  testWidgets('tắt nghiệp vụ: chỉ còn 3 chip', (tester) async {
    await pump(
      tester,
      automation: false,
      channels: [_item('team', 'Nhóm team')],
    );
    expect(chipLabels(tester), ['Tất cả', 'Chưa đọc', 'Nhóm']);
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
    expect(find.text('Tìm tin nhắn, nhóm, kênh...'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(ChoiceChip, 'Chưa đọc'));
    await tester.pumpAndSettle();
    final after = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(after[0].selected, isFalse);
    expect(after[1].selected, isTrue);
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
    expect(look('Ticket').icon, WebTuiIcons.ticket);
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
  @override
  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  }) async => const Success([]);

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
