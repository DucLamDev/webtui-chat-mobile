import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../moderation/presentation/widgets/moderation_actions.dart';
import '../../domain/entities/channel_exit.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/conversation_home_controller.dart';
import 'channel_exit_actions.dart';

/// Thao tác khi ấn giữ một dòng hội thoại (kiểu menu ba chấm của Zalo web).
enum ConversationQuickAction {
  pin,
  unpin,
  markUnread,
  markRead,
  mute,
  unmute,
  hide,
  unhide,
  removeFromList,
  leaveGroup,
  deleteGroup,
  report,
}

/// Danh sách thao tác cho một hội thoại, theo thứ tự hiện trên menu.
///
/// - Ghim, chưa đọc, ẩn: lưu trên máy (máy chủ chưa có API).
/// - Tắt thông báo: máy chủ (cài đặt báo của kênh).
/// - Kênh nghiệp vụ: chỉ đánh dấu đã đọc / chưa đọc.
/// - Xoá: nhóm xoá được → Xoá nhóm; rời được → Rời nhóm; còn lại (chat 1-1,
///   chat bot, kênh không rời được) → gỡ khỏi danh sách trên máy.
/// - Báo xấu: chỉ chat 1-1 với người (máy chủ chỉ nhận báo cáo người / tin).
List<ConversationQuickAction> conversationQuickActions(
  ConversationSummary conversation, {
  required bool hidden,
}) {
  final direct =
      conversation.kind == ConversationKind.direct && !conversation.noticeBot;
  final peer = conversation.peerUserId?.trim() ?? '';
  final readToggle = conversation.isUnread
      ? ConversationQuickAction.markRead
      : ConversationQuickAction.markUnread;
  // Kênh nghiệp vụ có chỗ cố định ở tab Nghiệp vụ: ghim / ẩn / xoá không có
  // nghĩa, tắt báo chỉnh trong phòng.
  if (conversation.isAutomation) return [readToggle];
  return [
    conversation.favorite
        ? ConversationQuickAction.unpin
        : ConversationQuickAction.pin,
    readToggle,
    conversation.muted
        ? ConversationQuickAction.unmute
        : ConversationQuickAction.mute,
    hidden ? ConversationQuickAction.unhide : ConversationQuickAction.hide,
    if (canDeleteGroup(conversation))
      ConversationQuickAction.deleteGroup
    else if (canLeaveGroup(conversation))
      ConversationQuickAction.leaveGroup
    else
      ConversationQuickAction.removeFromList,
    if (direct && peer.isNotEmpty) ConversationQuickAction.report,
  ];
}

String conversationQuickActionLabel(ConversationQuickAction action) {
  return switch (action) {
    ConversationQuickAction.pin => tr('Ghim hội thoại', 'Pin conversation'),
    ConversationQuickAction.unpin => tr('Bỏ ghim hội thoại', 'Unpin'),
    ConversationQuickAction.markUnread => tr(
      'Đánh dấu chưa đọc',
      'Mark as unread',
    ),
    ConversationQuickAction.markRead => tr('Đánh dấu đã đọc', 'Mark as read'),
    ConversationQuickAction.mute => tr('Tắt thông báo', 'Mute notifications'),
    ConversationQuickAction.unmute => tr(
      'Bật thông báo',
      'Unmute notifications',
    ),
    ConversationQuickAction.hide => tr('Ẩn trò chuyện', 'Hide chat'),
    ConversationQuickAction.unhide => tr('Bỏ ẩn trò chuyện', 'Unhide chat'),
    ConversationQuickAction.removeFromList => tr(
      'Xoá hội thoại',
      'Delete conversation',
    ),
    ConversationQuickAction.leaveGroup => tr('Rời nhóm', 'Leave group'),
    ConversationQuickAction.deleteGroup => tr('Xoá nhóm', 'Delete group'),
    ConversationQuickAction.report => tr('Báo xấu', 'Report'),
  };
}

bool _isDanger(ConversationQuickAction action) => switch (action) {
  ConversationQuickAction.removeFromList ||
  ConversationQuickAction.leaveGroup ||
  ConversationQuickAction.deleteGroup => true,
  _ => false,
};

/// `channelId` của dòng đang mở menu ấn giữ (null: không có menu nào mở).
/// Dòng chat nghe giá trị này để tô nền như đang chọn.
final conversationMenuTarget = ValueNotifier<String?>(null);

/// Mở menu ấn giữ ngay tại dòng chat rồi làm thao tác đã chọn.
///
/// [anchor]: khung của dòng chat (toạ độ toàn màn hình). Menu là hộp nổi canh
/// phải, ngay dưới dòng; dòng ở gần đáy (không đủ chỗ) thì bật lên phía trên.
Future<void> showConversationQuickActions(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required ConversationSummary conversation,
  required bool hidden,
  required Rect anchor,
}) async {
  final actions = conversationQuickActions(conversation, hidden: hidden);
  final screen = MediaQuery.sizeOf(context);
  final padding = MediaQuery.paddingOf(context);
  final position = conversationQuickActionsPosition(
    anchor: anchor,
    screen: screen,
    menuHeight: conversationQuickActionsHeight(actions),
    // Chừa thanh tab nổi ở đáy và tai thỏ ở đỉnh.
    safeTop: padding.top + WebTuiSpacing.sm,
    safeBottom: padding.bottom + _kBottomReserve,
  );
  final dark = Theme.of(context).brightness == Brightness.dark;
  // Tô nền dòng đang mở menu để biết menu thuộc dòng nào (như Zalo).
  conversationMenuTarget.value = conversation.channelId;
  final ConversationQuickAction? action;
  try {
    action = await showMenu<ConversationQuickAction>(
      context: context,
      position: position,
      constraints: const BoxConstraints.tightFor(width: _kMenuWidth),
      color: WebTuiColors.surface,
      surfaceTintColor: Colors.transparent,
      // Bóng mềm, nhạt kiểu Zalo, không viền. Nền tối bóng gần như không
      // thấy nên thêm viền rất mảnh để menu tách khỏi danh sách.
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.22),
      menuPadding: const EdgeInsets.symmetric(vertical: _kMenuVerticalPadding),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: dark
            ? BorderSide(color: Colors.white.withValues(alpha: 0.08))
            : BorderSide.none,
      ),
      items: [
        for (var index = 0; index < actions.length; index++) ...[
          if (_needsDivider(actions, index))
            const PopupMenuDivider(height: _kDividerHeight),
          _menuItem(context, actions[index]),
        ],
      ],
    );
  } finally {
    conversationMenuTarget.value = null;
  }
  if (action == null || !context.mounted) return;
  await runConversationQuickAction(
    context,
    ref,
    workspaceId: workspaceId,
    conversation: conversation,
    action: action,
  );
}

const double _kMenuWidth = 240;
const double _kItemHeight = 48;
const double _kDividerHeight = 9;
const double _kMenuVerticalPadding = 6;
// Thanh tab nổi + khoảng hở dưới đáy màn Tin nhắn.
const double _kBottomReserve = 88;

bool _needsDivider(List<ConversationQuickAction> actions, int index) =>
    index > 0 && _isDanger(actions[index]) && !_isDanger(actions[index - 1]);

/// Chiều cao hộp menu (để biết đặt dưới hay trên dòng chat).
double conversationQuickActionsHeight(List<ConversationQuickAction> actions) {
  var height = _kMenuVerticalPadding * 2 + actions.length * _kItemHeight;
  for (var index = 0; index < actions.length; index++) {
    if (_needsDivider(actions, index)) height += _kDividerHeight;
  }
  return height;
}

/// Vị trí hộp menu: canh phải theo dòng chat (cách mép 12), ngay dưới dòng;
/// không đủ chỗ phía dưới thì nằm ngay trên dòng.
@visibleForTesting
RelativeRect conversationQuickActionsPosition({
  required Rect anchor,
  required Size screen,
  required double menuHeight,
  required double safeTop,
  required double safeBottom,
}) {
  const margin = WebTuiSpacing.md;
  final maxLeft = screen.width - _kMenuWidth - margin;
  final left = (anchor.right - _kMenuWidth - margin).clamp(
    margin,
    maxLeft < margin ? margin : maxLeft,
  );
  final fitsBelow = anchor.bottom + menuHeight <= screen.height - safeBottom;
  final fitsAbove = anchor.top - menuHeight >= safeTop;
  final double top = fitsBelow || !fitsAbove
      ? anchor.bottom - 4
      : anchor.top - menuHeight + 4;
  return RelativeRect.fromLTRB(
    left,
    top,
    screen.width - left - _kMenuWidth,
    screen.height - top,
  );
}

PopupMenuItem<ConversationQuickAction> _menuItem(
  BuildContext context,
  ConversationQuickAction action,
) {
  final danger = _isDanger(action);
  final light = Theme.of(context).brightness == Brightness.light;
  // Đỏ nền sáng đậm hơn một bậc cho đủ tương phản chữ (≥ 4.5:1).
  final dangerText = light
      ? Color.alphaBlend(
          Colors.black.withValues(alpha: 0.2),
          WebTuiColors.danger,
        )
      : WebTuiColors.danger;
  return PopupMenuItem<ConversationQuickAction>(
    key: ValueKey('conversation-action-${action.name}'),
    value: action,
    height: _kItemHeight,
    padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
    child: Text(
      conversationQuickActionLabel(action),
      style: WebTuiTypography.bodyMedium.copyWith(
        fontSize: 15.5,
        color: danger ? dangerText : WebTuiColors.textPrimary,
      ),
    ),
  );
}

/// Đánh dấu đã đọc tới tin mới nhất trên máy chủ (cùng lời gọi phòng chat
/// dùng khi mở). Hội thoại chưa có tin thì không cần báo. Trả về false khi
/// không tải được tin mới nhất hoặc máy chủ từ chối.
Future<bool> _markReadOnServer(
  WidgetRef ref, {
  required String workspaceId,
  required String channelId,
}) async {
  final latest = await ref
      .read(conversationRepositoryProvider)
      .listMessages(workspaceId: workspaceId, channelId: channelId, limit: 1);
  final messages = latest.valueOrNull;
  if (messages == null) return false;
  if (messages.isEmpty) return true;
  final result = await ref
      .read(markConversationReadUseCaseProvider)
      .execute(
        workspaceId: workspaceId,
        channelId: channelId,
        lastReadMessageId: messages.last.id,
      );
  return result.isSuccess;
}

Future<void> runConversationQuickAction(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required ConversationSummary conversation,
  required ConversationQuickAction action,
}) async {
  final controller = ref.read(
    conversationHomeControllerProvider(workspaceId).notifier,
  );
  final messenger = ScaffoldMessenger.maybeOf(context);
  void notice(String text) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  switch (action) {
    case ConversationQuickAction.pin:
      controller.setPinned(conversation, true);
      notice(tr('Đã ghim hội thoại', 'Conversation pinned'));
    case ConversationQuickAction.unpin:
      controller.setPinned(conversation, false);
      notice(tr('Đã bỏ ghim hội thoại', 'Conversation unpinned'));
    case ConversationQuickAction.markUnread:
      controller.setMarkedUnread(conversation, true);
    case ConversationQuickAction.markRead:
      // Báo máy chủ như khi mở phòng, để lần đồng bộ sau (và máy khác) không
      // hiện lại số chưa đọc. Lỗi thì giữ nguyên, không xoá số giả trên máy.
      if (await _markReadOnServer(
        ref,
        workspaceId: workspaceId,
        channelId: conversation.channelId,
      )) {
        controller.setMarkedUnread(conversation, false);
      } else {
        notice(
          tr(
            'Không đánh dấu được đã đọc, thử lại sau',
            'Couldn\'t mark as read, try again later',
          ),
        );
      }
    case ConversationQuickAction.mute:
    case ConversationQuickAction.unmute:
      final muted = action == ConversationQuickAction.mute;
      final result = await ref
          .read(setChannelNotificationMutedUseCaseProvider)
          .execute(
            workspaceId: workspaceId,
            channelId: conversation.channelId,
            muted: muted,
          );
      if (result.isSuccess) {
        controller.setMutedLocally(conversation.channelId, muted);
        notice(
          muted
              ? tr('Đã tắt thông báo', 'Notifications muted')
              : tr('Đã bật thông báo', 'Notifications on'),
        );
      } else {
        notice(
          result.failureOrNull?.message ??
              tr(
                'Không đổi được thông báo, thử lại sau',
                'Couldn\'t change notifications, try again later',
              ),
        );
      }
    case ConversationQuickAction.hide:
      controller.setHidden(conversation, true);
      notice(
        tr(
          'Đã ẩn trò chuyện. Gõ tên vào ô tìm để mở lại.',
          'Chat hidden. Search its name to open it again.',
        ),
      );
    case ConversationQuickAction.unhide:
      controller.setHidden(conversation, false);
      notice(tr('Đã bỏ ẩn trò chuyện', 'Chat unhidden'));
    case ConversationQuickAction.removeFromList:
      final confirmed = await showWebTuiConfirmDialog(
        context,
        title: tr('Xoá hội thoại?', 'Delete conversation?'),
        message: tr(
          '"${conversation.title}" sẽ được gỡ khỏi danh sách trên máy này. '
              'Có tin nhắn mới thì hội thoại hiện lại.',
          '"${conversation.title}" will be removed from the list on this '
              'device. It comes back when a new message arrives.',
        ),
        confirmLabel: tr('Xoá', 'Delete'),
        destructive: true,
      );
      if (!confirmed) return;
      controller.removeFromList(conversation);
      notice(tr('Đã xoá hội thoại', 'Conversation deleted'));
    case ConversationQuickAction.leaveGroup:
      await confirmAndLeaveGroup(
        context,
        ref,
        workspaceId: workspaceId,
        channel: conversation,
      );
    case ConversationQuickAction.deleteGroup:
      await confirmAndDeleteGroup(
        context,
        ref,
        workspaceId: workspaceId,
        channel: conversation,
      );
    case ConversationQuickAction.report:
      final peer = conversation.peerUserId?.trim() ?? '';
      if (peer.isEmpty) return;
      await reportUser(
        context,
        ref,
        workspaceId: workspaceId,
        userId: peer,
        userLabel: conversation.title,
      );
  }
}
