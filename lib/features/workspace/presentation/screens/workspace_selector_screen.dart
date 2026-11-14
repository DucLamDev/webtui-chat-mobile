import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/workspace.dart';
import '../controllers/workspace_controller.dart';

/// Đường dẫn ngay sau đăng nhập: hỏi chọn workspace nếu tài khoản có nhiều
/// workspace và chưa chọn lần nào, không thì vào thẳng app.
const workspacePickerAfterLoginPath = '/workspaces?first=1';

class WorkspaceSelectorScreen extends ConsumerStatefulWidget {
  const WorkspaceSelectorScreen({
    this.onWorkspaceSelected,
    this.firstLogin = false,
    super.key,
  });

  final VoidCallback? onWorkspaceSelected;

  /// Mở ngay sau đăng nhập: tải lại danh sách, chỉ hiện khi cần hỏi chọn.
  final bool firstLogin;

  @override
  ConsumerState<WorkspaceSelectorScreen> createState() =>
      _WorkspaceSelectorScreenState();
}

class _WorkspaceSelectorScreenState
    extends ConsumerState<WorkspaceSelectorScreen> {
  late bool _checkingFirstLogin = widget.firstLogin;

  @override
  void initState() {
    super.initState();
    if (widget.firstLogin) {
      Future<void>.microtask(_checkFirstLogin);
    }
  }

  Future<void> _checkFirstLogin() async {
    if (!mounted) return;
    // Tài khoản vừa đăng nhập có thể khác tài khoản trước: luôn tải lại.
    await ref.read(workspaceControllerProvider.notifier).load();
    if (!mounted) return;
    final state = ref.read(workspaceControllerProvider);
    if (state.errorMessage == null &&
        state.hasActiveWorkspace &&
        !state.needsInitialChoice) {
      widget.onWorkspaceSelected?.call();
      return;
    }
    setState(() => _checkingFirstLogin = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);
    final onWorkspaceSelected = widget.onWorkspaceSelected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn workspace'),
        automaticallyImplyLeading: !widget.firstLogin,
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
            if (_checkingFirstLogin) {
              return const WebTuiLoadingState(message: 'Đang tải workspace...');
            }
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WebTuiSpacing.lg,
                    WebTuiSpacing.sm,
                    WebTuiSpacing.lg,
                    WebTuiSpacing.md,
                  ),
                  child: Text(
                    widget.firstLogin
                        ? 'Tài khoản của bạn thuộc nhiều workspace. Chọn '
                              'workspace để bắt đầu; bạn có thể đổi sau trong '
                              'Cài đặt.'
                        : state.workspaces.length == 1
                        ? 'Tài khoản của bạn hiện thuộc một workspace. Khi '
                              'được mời vào workspace khác, bấm Tải lại để '
                              'thấy và chuyển sang.'
                        : 'Chọn tổ chức bạn muốn làm việc.',
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
