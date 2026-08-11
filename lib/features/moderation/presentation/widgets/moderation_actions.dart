import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
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
  final action = await showModalBottomSheet<UserSafetyAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Báo cáo người dùng'),
            subtitle: Text('Gửi báo cáo về $userLabel cho đội ngũ kiểm duyệt.'),
            onTap: () => Navigator.pop(sheetContext, UserSafetyAction.report),
          ),
          ListTile(
            leading: Icon(
              blocked ? Icons.person_add_alt_1 : Icons.block_rounded,
              color: blocked ? null : WebTuiColors.danger,
            ),
            title: Text(blocked ? 'Bỏ chặn người dùng' : 'Chặn người dùng'),
            subtitle: Text(
              blocked
                  ? 'Cho phép hiển thị lại nội dung từ $userLabel.'
                  : 'Ẩn nội dung và ngăn tương tác trực tiếp với $userLabel.',
            ),
            onTap: () =>
                Navigator.pop(sheetContext, UserSafetyAction.toggleBlock),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
        ],
      ),
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
    title: 'Báo cáo tin nhắn',
    description:
        'Báo cáo sẽ được gửi riêng cho đội ngũ kiểm duyệt. Người gửi không được thông báo danh tính của bạn.',
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
    title: 'Báo cáo $userLabel',
    description:
        'Hãy chọn lý do phù hợp. Báo cáo sẽ được đội ngũ kiểm duyệt xem xét.',
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
    builder: (dialogContext) => AlertDialog(
      title: Text(blocked ? 'Bỏ chặn $userLabel?' : 'Chặn $userLabel?'),
      content: Text(
        blocked
            ? 'Nội dung mới từ người dùng này sẽ hiển thị lại.'
            : 'Tin nhắn của người dùng này sẽ bị ẩn. Bạn có thể bỏ chặn trong mục Quyền riêng tư.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: blocked
              ? null
              : FilledButton.styleFrom(backgroundColor: WebTuiColors.danger),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(blocked ? 'Bỏ chặn' : 'Chặn'),
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
            blocked ? 'Đã bỏ chặn $userLabel.' : 'Đã chặn $userLabel.',
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
        const SnackBar(
          content: Text(
            'Đã gửi báo cáo. Cảm ơn bạn đã giúp cộng đồng an toàn.',
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
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.description),
            const SizedBox(height: WebTuiSpacing.md),
            DropdownButtonFormField<ModerationReportReason>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Lý do'),
              items: [
                for (final item in ModerationReportReason.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(_reasonLabel(item)),
                  ),
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
            TextField(
              controller: _detailsController,
              enabled: !_isSubmitting,
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Chi tiết (không bắt buộc)',
                hintText: 'Mô tả ngắn gọn điều đã xảy ra',
                alignLabelWithHint: true,
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.flag_outlined),
          label: Text(_isSubmitting ? 'Đang gửi...' : 'Gửi báo cáo'),
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
    ModerationReportReason.spam => 'Spam hoặc lừa đảo',
    ModerationReportReason.harassment => 'Quấy rối hoặc bắt nạt',
    ModerationReportReason.hateSpeech => 'Ngôn từ thù ghét',
    ModerationReportReason.sexualContent => 'Nội dung tình dục',
    ModerationReportReason.violence => 'Bạo lực hoặc đe dọa',
    ModerationReportReason.illegalContent =>
      'Hoạt động hoặc nội dung bất hợp pháp',
    ModerationReportReason.privacy => 'Xâm phạm quyền riêng tư',
    ModerationReportReason.impersonation => 'Mạo danh',
    ModerationReportReason.other => 'Lý do khác',
  };
}
