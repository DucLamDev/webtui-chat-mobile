import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../controllers/approval_access_provider.dart';

/// Dòng "Phê duyệt" ở tab Nghiệp vụ (cùng kiểu dòng hội thoại). Chỉ hiện khi
/// máy chủ báo `capabilities.approvals` và người dùng có quyền xem.
class ApprovalInboxEntry extends ConsumerWidget {
  const ApprovalInboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(approvalAccessProvider(workspaceId));
    final id = workspaceId.trim();
    if (!access.canView || id.isEmpty) return const SizedBox.shrink();
    return WebTuiConversationListItem(
      key: const Key('approval_entry'),
      title: 'Phê duyệt',
      preview: 'Duyệt hoặc từ chối yêu cầu đang chờ',
      timeLabel: '',
      avatarLabel: 'Phê duyệt',
      avatarIcon: WebTuiIcons.tasks,
      trailing: const Icon(
        CupertinoIcons.chevron_right,
        size: 18,
        color: WebTuiColors.textMuted,
      ),
      onTap: () => context.push(
        Uri(
          path: '/approvals',
          queryParameters: {'workspaceId': id},
        ).toString(),
      ),
    );
  }
}
