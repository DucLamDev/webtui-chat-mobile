import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../domain/entities/conversation_summary.dart';
import '../widgets/workspace_modules.dart';

/// Công cụ tạo nội dung dùng chung trong phòng chat bị khoá khi người dùng bị
/// chặn / chưa rõ trạng thái chặn (dùng cho các công cụ mở từ phòng chat).
bool workspaceToolsSharedContentBlocked(
  ConversationSummary room,
  ModerationState moderationState,
) {
  if (room.kind != ConversationKind.direct) return false;
  if (moderationState.isLoadingBlockedUsers ||
      moderationState.errorMessage != null) {
    return true;
  }
  final peerUserId = room.directCallTargetUserId();
  if (peerUserId == null || peerUserId.trim().isEmpty) return true;
  return moderationState.isBlocked(peerUserId);
}

/// Tab Công việc: danh sách tiện ích đã bật (hiện chỉ My Note). Công cụ cộng
/// tác (họp, chia sẻ, bảng trắng...) mở từ bên trong từng phòng chat.
class WorkspaceToolsScreen extends ConsumerWidget {
  const WorkspaceToolsScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref
        .watch(workspaceModulesProvider)
        .where((module) => module.enabled)
        .toList(growable: false);
    if (modules.isEmpty || workspaceId.trim().isEmpty) {
      return const WebTuiEmptyState(
        key: Key('workspace_tools_empty'),
        title: 'Chưa có tiện ích nào được bật',
        message:
            'Chưa có tiện ích nào được bật cho tổ chức này. Khi quản trị viên '
            'bật thêm, chúng sẽ hiện ở đây.',
        icon: Icons.widgets_outlined,
      );
    }
    return ListView(
      key: const Key('workspace_tools_list'),
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        for (final module in modules)
          _ModuleCard(module: module, workspaceId: workspaceId.trim()),
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.workspaceId});

  final WorkspaceModule module;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
      child: Material(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: InkWell(
          key: Key('workspace_module_${module.id}'),
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          onTap: () => context.push(module.routeFor(workspaceId)),
          child: Container(
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WebTuiRadii.lg),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: WebTuiColors.primarySoft,
                    borderRadius: BorderRadius.circular(WebTuiRadii.md),
                  ),
                  child: Icon(module.icon, color: WebTuiColors.primary),
                ),
                const SizedBox(width: WebTuiSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: WebTuiTypography.titleMedium.copyWith(
                          color: WebTuiColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        module.description,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: WebTuiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WebTuiColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
