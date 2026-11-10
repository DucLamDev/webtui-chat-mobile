import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../controllers/approval_access_provider.dart';

/// Ô "Phê duyệt" ở tab Nghiệp vụ. Chỉ hiện khi máy chủ báo
/// `capabilities.approvals` và người dùng có quyền xem.
class ApprovalInboxEntry extends ConsumerWidget {
  const ApprovalInboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(approvalAccessProvider);
    final id = workspaceId.trim();
    if (!access.canView || id.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
        WebTuiSpacing.lg,
        0,
      ),
      child: Material(
        color: WebTuiColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          side: const BorderSide(color: WebTuiColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const Key('approval_entry'),
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Phê duyệt'),
          subtitle: const Text('Duyệt hoặc từ chối yêu cầu đang chờ'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(
            Uri(
              path: '/approvals',
              queryParameters: {'workspaceId': id},
            ).toString(),
          ),
        ),
      ),
    );
  }
}
