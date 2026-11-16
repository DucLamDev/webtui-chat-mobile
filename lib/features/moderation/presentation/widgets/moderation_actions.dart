import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../domain/entities/moderation.dart';
import '../controllers/moderation_controller.dart';

enum UserSafetyAction { report, toggleBlock }

Future<void> showUserSafetyActions(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String userId,
  required String userLabel,
}) async {
  final normalizedUserId = userId.trim();
  if (workspaceId.trim().isEmpty || normalizedUserId.isEmpty) {
    return;
  }
  final provider = moderationControllerProvider(workspaceId);
  final blocked = ref.read(provider).isBlocked(normalizedUserId);
  final action = await showWebTuiSheet<UserSafetyAction>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WebTuiSheetHeader(title: userLabel, subtitle: tr('An toàn', 'Safety')),
        WebTuiSheetActionTile(
          icon: WebTuiIcons.report,
          title: tr('Báo cáo người dùng', 'Report user'),
          subtitle: tr(
            'Gửi báo cáo về $userLabel cho đội ngũ kiểm duyệt.',
            'Send a report about $userLabel to the moderation team.',
          ),
          onTap: () => Navigator.pop(sheetContext, UserSafetyAction.report),
        ),
        WebTuiSheetActionTile(
          icon: blocked ? WebTuiIcons.unblock : WebTuiIcons.block,
          tone: blocked ? WebTuiDialogTone.normal : WebTuiDialogTone.danger,
          title: blocked
              ? tr('Bỏ chặn người dùng', 'Unblock user')
              : tr('Chặn người dùng', 'Block user'),
          subtitle: blocked
              ? tr(
                  'Cho phép hiển thị lại nội dung từ $userLabel.',
                  'Show content from $userLabel again.',
                )
              : tr(
                  'Ẩn nội dung và ngăn tương tác trực tiếp với $userLabel.',
                  'Hide content and prevent direct interaction with $userLabel.',
                ),
          onTap: () =>
              Navigator.pop(sheetContext, UserSafetyAction.toggleBlock),
        ),
        const SizedBox(height: WebTuiSpacing.md),
      ],
    ),
  );
  if (action == null || !context.mounted) {
    return;
  }
  switch (action) {
    case UserSafetyAction.report:
      await reportUser(
        context,
        ref,
        workspaceId: workspaceId,
        userId: normalizedUserId,
        userLabel: userLabel,
      );
    case UserSafetyAction.toggleBlock:
      await toggleUserBlock(
        context,
        ref,
        workspaceId: workspaceId,
        userId: normalizedUserId,
        userLabel: userLabel,
      );
  }
}

Future<bool> reportMessage(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String messageId,
}) {
  return _showReportDialog(
    context,
    title: tr('Báo cáo tin nhắn', 'Report message'),
    description: tr(
      'Báo cáo sẽ được gửi riêng cho đội ngũ kiểm duyệt. Người gửi không được thông báo danh tính của bạn.',
      'The report goes privately to the moderation team. The sender isn\'t told who you are.',
    ),
    onSubmit: (reason, details) async {
      final result = await ref
          .read(moderationControllerProvider(workspaceId).notifier)
          .report(
            targetType: ModerationTargetType.message,
            targetId: messageId,
            reason: reason,
            details: details,
          );
      return result.failureOrNull?.message;
    },
  );
}

Future<bool> reportUser(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String userId,
  required String userLabel,
}) {
  return _showReportDialog(
    context,
    title: tr('Báo cáo $userLabel', 'Report $userLabel'),
    description: tr(
      'Hãy chọn lý do phù hợp. Báo cáo sẽ được đội ngũ kiểm duyệt xem xét.',
      'Choose a suitable reason. The moderation team will review the report.',
    ),
    onSubmit: (reason, details) async {
      final result = await ref
          .read(moderationControllerProvider(workspaceId).notifier)
          .report(
            targetType: ModerationTargetType.user,
            targetId: userId,
            reason: reason,
            details: details,
          );
      return result.failureOrNull?.message;
    },
  );
}

Future<bool> toggleUserBlock(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String userId,
  required String userLabel,
}) async {
  final provider = moderationControllerProvider(workspaceId);
  final blocked = ref.read(provider).isBlocked(userId);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => WebTuiDialog(
      title: blocked
          ? tr('Bỏ chặn $userLabel?', 'Unblock $userLabel?')
          : tr('Chặn $userLabel?', 'Block $userLabel?'),
      message: blocked
          ? tr(
              'Nội dung mới từ người dùng này sẽ hiển thị lại.',
              'New content from this user will be shown again.',
            )
          : tr(
              'Tin nhắn của người dùng này sẽ bị ẩn. Bạn có thể bỏ chặn trong mục Quyền riêng tư.',
              'This user\'s messages will be hidden. You can unblock them under Privacy.',
            ),
      icon: blocked ? WebTuiIcons.unblock : WebTuiIcons.block,
      tone: blocked ? WebTuiDialogTone.normal : WebTuiDialogTone.danger,
      actions: [
        WebTuiDialogAction(
          label: tr('Hủy', 'Cancel'),
          onPressed: () => Navigator.pop(dialogContext, false),
        ),
        WebTuiDialogAction(
          label: blocked ? tr('Bỏ chặn', 'Unblock') : tr('Chặn', 'Block'),
          primary: true,
          destructive: !blocked,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return false;
  }

  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(provider.notifier);
  final Result<Object?> result = blocked
      ? await controller.unblock(userId)
      : await controller.block(userId: userId, reason: 'user_safety_action');
  if (!context.mounted) {
    return result.isSuccess;
  }
  switch (result) {
    case Success<Object?>():
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? tr('Đã bỏ chặn $userLabel.', 'Unblocked $userLabel.')
                : tr('Đã chặn $userLabel.', 'Blocked $userLabel.'),
          ),
        ),
      );
      return true;
    case FailureResult<Object?>(failure: final failure):
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return false;
  }
}

Future<bool> _showReportDialog(
  BuildContext context, {
  required String title,
  required String description,
  required Future<String?> Function(
    ModerationReportReason reason,
    String details,
  )
  onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ModerationReportDialog(
      title: title,
      description: description,
      onSubmit: onSubmit,
    ),
  ).then((submitted) {
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Đã gửi báo cáo. Cảm ơn bạn đã giúp cộng đồng an toàn.',
              'Report sent. Thanks for helping keep the community safe.',
            ),
          ),
        ),
      );
    }
    return submitted ?? false;
  });
}

class _ModerationReportDialog extends StatefulWidget {
  const _ModerationReportDialog({
    required this.title,
    required this.description,
    required this.onSubmit,
  });

  final String title;
  final String description;
  final Future<String?> Function(ModerationReportReason reason, String details)
  onSubmit;

  @override
  State<_ModerationReportDialog> createState() =>
      _ModerationReportDialogState();
}

class _ModerationReportDialogState extends State<_ModerationReportDialog> {
  final _detailsController = TextEditingController();
  var _reason = ModerationReportReason.spam;
  var _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebTuiDialog(
      title: widget.title,
      message: widget.description,
      icon: WebTuiIcons.report,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<ModerationReportReason>(
            initialValue: _reason,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Lý do', 'Reason')),
            items: [
              for (final item in ModerationReportReason.values)
                DropdownMenuItem(value: item, child: Text(_reasonLabel(item))),
            ],
            onChanged: _isSubmitting
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _reason = value);
                    }
                  },
          ),
          const SizedBox(height: WebTuiSpacing.md),
          WebTuiDialogTextField(
            controller: _detailsController,
            label: tr('Chi tiết (không bắt buộc)', 'Details (optional)'),
            hint: tr(
              'Mô tả ngắn gọn điều đã xảy ra',
              'Briefly describe what happened',
            ),
            maxLength: 2000,
            textInputAction: TextInputAction.done,
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: WebTuiColors.danger),
              ),
            ),
        ],
      ),
      actions: [
        WebTuiDialogAction(
          label: tr('Hủy', 'Cancel'),
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
        ),
        WebTuiDialogAction(
          label: _isSubmitting
              ? tr('Đang gửi...', 'Sending...')
              : tr('Gửi báo cáo', 'Send report'),
          primary: true,
          loading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final error = await widget.onSubmit(_reason, _detailsController.text);
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = error;
    });
  }
}

String _reasonLabel(ModerationReportReason reason) {
  return switch (reason) {
    ModerationReportReason.spam => tr('Spam hoặc lừa đảo', 'Spam or scam'),
    ModerationReportReason.harassment => tr(
      'Quấy rối hoặc bắt nạt',
      'Harassment or bullying',
    ),
    ModerationReportReason.hateSpeech => tr('Ngôn từ thù ghét', 'Hate speech'),
    ModerationReportReason.sexualContent => tr(
      'Nội dung tình dục',
      'Sexual content',
    ),
    ModerationReportReason.violence => tr(
      'Bạo lực hoặc đe dọa',
      'Violence or threats',
    ),
    ModerationReportReason.illegalContent => tr(
      'Hoạt động hoặc nội dung bất hợp pháp',
      'Illegal activity or content',
    ),
    ModerationReportReason.privacy => tr(
      'Xâm phạm quyền riêng tư',
      'Privacy violation',
    ),
    ModerationReportReason.impersonation => tr('Mạo danh', 'Impersonation'),
    ModerationReportReason.other => tr('Lý do khác', 'Other reason'),
  };
}
