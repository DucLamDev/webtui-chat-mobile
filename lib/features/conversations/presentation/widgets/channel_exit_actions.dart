import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/channel_exit.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/channel_membership_events.dart';

/// Màu chữ đỏ đọc được trên nền sáng (≥ 4.5:1 trên nền trắng); nền tối dùng
/// màu đỏ sáng của bảng màu (đã đủ tương phản trên nền tối).
Color get channelExitDangerText => WebTuiColors.brightness == Brightness.dark
    ? WebTuiColors.danger
    : const Color(0xFFB42318);

/// Tên nút xoá: "Xoá nhóm" cho nhóm, "Xoá kênh" khi quản trị xoá kênh công khai.
String deleteGroupLabel(ConversationSummary? channel) =>
    channel?.channelVisibility == ChannelVisibility.public
    ? tr('Xoá kênh', 'Delete channel')
    : tr('Xoá nhóm', 'Delete group');

String get deleteGroupHint =>
    tr('Xoá cho mọi thành viên', 'Deletes it for every member');

/// Mục "Rời nhóm" / "Xoá nhóm" ở màn thông tin nhóm. Chỉ hiện nút máy chủ cho
/// phép ([canLeaveGroup] / [canDeleteGroup]); không có nút nào thì ẩn hẳn.
class ChannelExitSettings extends StatelessWidget {
  const ChannelExitSettings({
    required this.channel,
    required this.onLeave,
    required this.onDelete,
    super.key,
  });

  final ConversationSummary? channel;
  final VoidCallback onLeave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canLeave = canLeaveGroup(channel);
    final canDelete = canDeleteGroup(channel);
    if (!canLeave && !canDelete) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.lg),
      child: WebTuiListSurface(
        children: [
          if (canLeave)
            _ChannelExitRow(
              key: const ValueKey('channel-leave-group'),
              icon: WebTuiIcons.leaveGroup,
              title: tr('Rời nhóm', 'Leave group'),
              subtitle: tr(
                'Nhóm vẫn còn cho các thành viên khác',
                'The group stays for other members',
              ),
              strong: false,
              onTap: onLeave,
            ),
          if (canDelete)
            _ChannelExitRow(
              key: const ValueKey('channel-delete-group'),
              icon: WebTuiIcons.delete,
              title: deleteGroupLabel(channel),
              subtitle: deleteGroupHint,
              strong: true,
              onTap: onDelete,
            ),
        ],
      ),
    );
  }
}

class _ChannelExitRow extends StatelessWidget {
  const _ChannelExitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.strong,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// `true`: đỏ đậm (xoá); `false`: đỏ nhạt (rời).
  final bool strong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final red = channelExitDangerText;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.lg,
                vertical: WebTuiSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: strong
                          ? WebTuiColors.danger
                          : WebTuiColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: strong ? Colors.white : red,
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: red,
                            fontWeight: strong
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: WebTuiSpacing.xs),
                        Text(
                          subtitle,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hỏi xác nhận rồi rời nhóm. Thành công: bỏ nhóm khỏi danh sách và bộ nhớ
/// đệm, đóng phòng chat / màn thông tin, về danh sách Tin nhắn, báo "Đã rời
/// nhóm". Lỗi thì báo ngay trong hộp xác nhận để thử lại.
Future<void> confirmAndLeaveGroup(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required ConversationSummary channel,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _ChannelExitDialog(
      title: tr('Rời nhóm?', 'Leave group?'),
      message: tr(
        'Bạn sẽ không nhận tin của "${channel.title}" nữa. Nhóm vẫn còn cho '
            'các thành viên khác; muốn vào lại cần được thêm lại.',
        'You will stop getting messages from "${channel.title}". The group '
            'stays for other members; you need to be added again to rejoin.',
      ),
      icon: WebTuiIcons.leaveGroup,
      confirmLabel: tr('Rời nhóm', 'Leave'),
      run: () async {
        final result = await ref
            .read(leaveGroupUseCaseProvider)
            .execute(workspaceId: workspaceId, channel: channel);
        return result.failureOrNull?.message;
      },
    ),
  );
  if (done != true || !context.mounted) return;
  _finishExit(
    context,
    ref,
    workspaceId: workspaceId,
    channelId: channel.channelId,
    reason: ChannelRemovalReason.left,
    notice: tr('Đã rời nhóm', 'You left the group'),
  );
}

/// Hỏi xác nhận rồi xoá nhóm cho mọi thành viên (lưu trữ trên máy chủ).
Future<void> confirmAndDeleteGroup(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required ConversationSummary channel,
}) async {
  final isPublic = channel.channelVisibility == ChannelVisibility.public;
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _ChannelExitDialog(
      title: isPublic
          ? tr('Xoá kênh cho mọi thành viên?', 'Delete channel for everyone?')
          : tr('Xoá nhóm cho mọi thành viên?', 'Delete group for everyone?'),
      message: tr(
        '"${channel.title}" sẽ biến mất ở máy của tất cả thành viên và không '
            'mở lại được. Không hoàn tác được.',
        '"${channel.title}" will disappear for every member and can\'t be '
            'reopened. This can\'t be undone.',
      ),
      icon: WebTuiIcons.delete,
      confirmLabel: deleteGroupLabel(channel),
      run: () async {
        final result = await ref
            .read(deleteGroupUseCaseProvider)
            .execute(workspaceId: workspaceId, channel: channel);
        return result.failureOrNull?.message;
      },
    ),
  );
  if (done != true || !context.mounted) return;
  _finishExit(
    context,
    ref,
    workspaceId: workspaceId,
    channelId: channel.channelId,
    reason: ChannelRemovalReason.deleted,
    notice: isPublic
        ? tr('Đã xoá kênh', 'Channel deleted')
        : tr('Đã xoá nhóm', 'Group deleted'),
  );
}

void _finishExit(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String channelId,
  required ChannelRemovalReason reason,
  required String notice,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.maybeOf(context);
  _markClosed(workspaceId, channelId, reason);
  removeChannelEverywhere(
    read: ref.read,
    exists: ref.exists,
    workspaceId: workspaceId,
    channelId: channelId,
    reason: reason,
    initiatedHere: true,
    // Kho đã bỏ nhóm khỏi bộ nhớ đệm khi gọi thành công.
    forgetCache: false,
  );
  router?.go('/');
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(notice)));
}

/// Nhóm vừa đóng gần đây (mỗi sự kiện có thể tới hai lần: room kênh và room
/// cá nhân; phòng chat và màn thông tin cùng nghe) → chỉ đóng / báo một lần.
final Map<String, DateTime> _recentlyClosed = {};
const _closeDedupWindow = Duration(seconds: 10);

String _closeKey(
  String workspaceId,
  String channelId,
  ChannelRemovalReason r,
) => '$workspaceId/$channelId/${r.name}';

void _markClosed(String workspaceId, String channelId, ChannelRemovalReason r) {
  _recentlyClosed[_closeKey(workspaceId, channelId, r)] = DateTime.now();
}

bool _closedRecently(
  String workspaceId,
  String channelId,
  ChannelRemovalReason reason,
) {
  final now = DateTime.now();
  _recentlyClosed.removeWhere(
    (_, at) => now.difference(at) > _closeDedupWindow,
  );
  return _recentlyClosed.containsKey(_closeKey(workspaceId, channelId, reason));
}

/// Màn đang mở nhóm [channelId] nhận tín hiệu nhóm không còn (bị xoá / mình
/// rời ở máy khác): đóng về danh sách Tin nhắn và báo. [navigate] = `false`
/// khi phòng chat nằm trong màn chia đôi (máy tính bảng) — danh sách đã tự bỏ
/// chọn. Tín hiệu do chính máy này bấm thì bỏ qua (đã đóng và báo rồi).
void closeForRemovedChannel(
  BuildContext context,
  ChannelRemovalSignal signal, {
  required String workspaceId,
  required String channelId,
  bool navigate = true,
}) {
  if (signal.initiatedHere ||
      signal.workspaceId != workspaceId ||
      signal.channelId != channelId) {
    return;
  }
  if (_closedRecently(workspaceId, channelId, signal.reason)) return;
  _markClosed(workspaceId, channelId, signal.reason);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (navigate) GoRouter.maybeOf(context)?.go('/');
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          signal.reason == ChannelRemovalReason.deleted
              ? tr('Nhóm đã bị xoá', 'This group was deleted')
              : tr('Bạn đã rời nhóm', 'You left this group'),
        ),
      ),
    );
}

/// Hộp xác nhận rời / xoá: bấm nút chính thì chạy [run] ngay trong hộp (nút
/// quay vòng, không bấm lại được, không đóng được giữa chừng). Thành công thì
/// đóng hộp với `true`; lỗi thì hiện câu lỗi trong hộp để thử lại.
class _ChannelExitDialog extends StatefulWidget {
  const _ChannelExitDialog({
    required this.title,
    required this.message,
    required this.icon,
    required this.confirmLabel,
    required this.run,
  });

  final String title;
  final String message;
  final IconData icon;
  final String confirmLabel;

  /// Trả `null` khi thành công, câu lỗi khi thất bại.
  final Future<String?> Function() run;

  @override
  State<_ChannelExitDialog> createState() => _ChannelExitDialogState();
}

class _ChannelExitDialogState extends State<_ChannelExitDialog> {
  bool _running = false;
  String? _error;

  Future<void> _confirm() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.run();
    } on Object {
      error = tr(
        'Chưa thực hiện được. Vui lòng thử lại.',
        'Could not complete that. Please try again.',
      );
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _running = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: !_running,
      child: WebTuiDialog(
        title: widget.title,
        message: widget.message,
        icon: widget.icon,
        tone: WebTuiDialogTone.danger,
        content: error == null
            ? null
            : Semantics(
                liveRegion: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WebTuiColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(WebTuiRadii.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(WebTuiSpacing.md),
                    child: Text(
                      error,
                      key: const ValueKey('channel-exit-error'),
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: channelExitDangerText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
        actions: [
          WebTuiDialogAction(
            key: const Key('webtui_dialog_cancel'),
            label: tr('Huỷ', 'Cancel'),
            onPressed: _running ? null : () => Navigator.of(context).pop(false),
          ),
          WebTuiDialogAction(
            key: const Key('webtui_dialog_confirm'),
            label: widget.confirmLabel,
            primary: true,
            destructive: true,
            loading: _running,
            onPressed: _confirm,
          ),
        ],
      ),
    );
  }
}
