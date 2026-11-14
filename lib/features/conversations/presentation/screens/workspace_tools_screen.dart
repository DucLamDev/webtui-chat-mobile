import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../work_hub/presentation/widgets/my_tasks_card.dart';
import '../../../work_hub/presentation/widgets/work_apps_grid.dart';
import '../../../work_hub/presentation/widgets/work_common.dart';
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

/// Tab Công việc: Việc của tôi, My Note và lưới Ứng dụng (Lịch họp, Tệp chia
/// sẻ, lối tắt do quản trị thêm). Công cụ cộng tác (họp, bảng trắng...) vẫn mở
/// từ bên trong từng phòng chat.
class WorkspaceToolsScreen extends ConsumerWidget {
  const WorkspaceToolsScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = workspaceId.trim();
    if (id.isEmpty) {
      return const WebTuiEmptyState(
        key: Key('workspace_tools_empty'),
        title: 'Chưa có workspace',
        message: 'Chọn một workspace để xem công việc của bạn.',
        icon: WebTuiIcons.work,
      );
    }
    final modules = ref
        .watch(workspaceModulesProvider)
        .where((module) => module.enabled)
        .toList(growable: false);
    return ListView(
      key: const Key('workspace_tools_list'),
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.xxl,
      ),
      children: [
        MyTasksCard(workspaceId: id),
        for (final module in modules) ...[
          const SizedBox(height: 14),
          _ModuleCard(module: module, workspaceId: id),
        ],
        const SizedBox(height: WebTuiSpacing.xxl),
        WorkAppsSection(workspaceId: id),
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
    return WorkCard(
      key: Key('workspace_module_${module.id}'),
      radius: 20,
      onTap: () => context.push(module.routeFor(workspaceId)),
      child: Row(
        children: [
          WorkIconBox(icon: module.icon, size: 56, radius: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.title,
                  style: WebTuiTypography.titleMedium.copyWith(
                    fontSize: 18,
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.xxs),
                Text(
                  module.description,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(WebTuiIcons.forward, color: WebTuiColors.textSecondary),
        ],
      ),
    );
  }
}
