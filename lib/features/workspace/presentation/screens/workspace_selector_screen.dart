import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/workspace.dart';
import '../controllers/workspace_controller.dart';

class WorkspaceSelectorScreen extends ConsumerWidget {
  const WorkspaceSelectorScreen({this.onWorkspaceSelected, super.key});

  final VoidCallback? onWorkspaceSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn workspace'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: state.isLoading ? null : controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (state.isLoading && state.workspaces.isEmpty) {
              return const WebTuiLoadingState(message: 'Đang tải workspace...');
            }
            if (state.errorMessage != null && state.workspaces.isEmpty) {
              return WebTuiErrorState(
                title: 'Không tải được workspace',
                message: state.errorMessage!,
                onRetry: controller.load,
              );
            }
            if (state.workspaces.isEmpty) {
              return const WebTuiEmptyState(
                title: 'Chưa có workspace',
                message: 'Tài khoản này chưa thuộc workspace nào.',
                icon: Icons.domain_disabled_outlined,
              );
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.xl),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    WebTuiSpacing.lg,
                    WebTuiSpacing.sm,
                    WebTuiSpacing.lg,
                    WebTuiSpacing.md,
                  ),
                  child: Text(
                    'Dữ liệu chat, cursor và quyền được tách theo workspace.',
                  ),
                ),
                WebTuiListSurface(
                  children: [
                    for (final workspace in state.workspaces)
                      _WorkspaceRow(
                        workspace: workspace,
                        selected: state.activeWorkspace?.id == workspace.id,
                        busy: state.isSwitching,
                        onTap: () async {
                          final ok = await controller.select(workspace);
                          if (ok && context.mounted) {
                            onWorkspaceSelected?.call();
                          }
                        },
                      ),
                  ],
                ),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(WebTuiSpacing.lg),
                    child: Text(
                      state.errorMessage!,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.workspace,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final Workspace workspace;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WebTuiSettingRow(
      title: workspace.name,
      subtitle: '${workspace.slug} • ${workspace.status}',
      icon: Icons.business_rounded,
      onTap: busy ? null : onTap,
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: WebTuiColors.primary)
          : const Icon(
              Icons.chevron_right_rounded,
              color: WebTuiColors.textMuted,
            ),
    );
  }
}
