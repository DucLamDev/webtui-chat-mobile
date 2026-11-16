import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../../workspace/presentation/screens/workspace_selector_screen.dart';
import '../../application/use_cases/device_approval_use_cases.dart';
import '../auth_formatters.dart';
import '../controllers/device_approval_controllers.dart';

const deviceApprovalPendingPath = '/device-approval/pending';

/// Thiết bị mới đăng nhập đang chờ máy tin cậy / quản trị duyệt (Lõi 2.3).
class DeviceApprovalPendingScreen extends ConsumerStatefulWidget {
  const DeviceApprovalPendingScreen({super.key});

  @override
  ConsumerState<DeviceApprovalPendingScreen> createState() =>
      _DeviceApprovalPendingScreenState();
}

class _DeviceApprovalPendingScreenState
    extends ConsumerState<DeviceApprovalPendingScreen> {
  Timer? _clockTimer;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    // Đếm ngược thời hạn chờ duyệt.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PendingApprovalState>(deviceApprovalPendingControllerProvider, (
      previous,
      next,
    ) {
      if (next.phase == PendingApprovalPhase.approved &&
          previous?.phase != PendingApprovalPhase.approved) {
        ref.invalidate(authAccessTokenProvider);
        ref.invalidate(workspaceControllerProvider);
        context.go(workspacePickerAfterLoginPath);
      }
    });
    final state = ref.watch(deviceApprovalPendingControllerProvider);
    final controller = ref.read(
      deviceApprovalPendingControllerProvider.notifier,
    );
    final approval = state.approval;
    final expiresAt = approval?.approvalExpiresAt;
    final remaining = expiresAt?.difference(DateTime.now());

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: WebTuiColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(tr('Chờ duyệt thiết bị', 'Waiting for device approval')),
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: switch (state.phase) {
            PendingApprovalPhase.loading => WebTuiLoadingState(
              message: tr(
                'Đang kiểm tra trạng thái duyệt...',
                'Checking approval status...',
              ),
            ),
            PendingApprovalPhase.error => WebTuiErrorState(
              title: tr(
                'Không kiểm tra được trạng thái duyệt',
                'Could not check the approval status',
              ),
              message:
                  state.errorMessage ??
                  tr('Vui lòng thử lại.', 'Please try again.'),
              onRetry: controller.poll,
            ),
            PendingApprovalPhase.ended => WebTuiLoadingState(
              message: tr(
                'Đang đưa bạn về màn đăng nhập...',
                'Taking you back to sign in...',
              ),
            ),
            _ => ListView(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              children: [
                Icon(
                  Icons.phonelink_lock_rounded,
                  size: 56,
                  color: WebTuiColors.primary,
                ),
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  state.phase == PendingApprovalPhase.finishing ||
                          state.phase == PendingApprovalPhase.approved
                      ? tr(
                          'Đã được duyệt, đang vào ứng dụng...',
                          'Approved, opening the app...',
                        )
                      : tr(
                          'Thiết bị này cần được duyệt',
                          'This device needs approval',
                        ),
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                Text(
                  pendingApprovalExplanation(approval),
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.lg),
                if (remaining != null)
                  Text(
                    tr(
                      'Yêu cầu hết hạn sau ${formatCountdown(remaining)}',
                      'The request expires in ${formatCountdown(remaining)}',
                    ),
                    key: const Key('device_approval_countdown'),
                    textAlign: TextAlign.center,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (approval != null && approval.decisions.isNotEmpty) ...[
                  const SizedBox(height: WebTuiSpacing.md),
                  for (final decision in approval.decisions)
                    Text(
                      '${deviceApprovalRoleLabel(decision.approverRole)}: '
                      '${decision.isApproval ? tr('đã đồng ý', 'approved') : tr('đã từ chối', 'rejected')}',
                      textAlign: TextAlign.center,
                      style: WebTuiTypography.bodySmall,
                    ),
                ],
                if (state.errorMessage != null) ...[
                  const SizedBox(height: WebTuiSpacing.md),
                  Text(
                    state.errorMessage!,
                    textAlign: TextAlign.center,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: WebTuiSpacing.lg),
                const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.xl),
                OutlinedButton.icon(
                  key: const Key('device_approval_logout_button'),
                  onPressed: _loggingOut ? null : _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(tr('Đăng xuất', 'Sign out')),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    await ref.read(logoutUseCaseProvider).execute();
    ref.invalidate(authAccessTokenProvider);
    if (mounted) {
      context.go('/login');
    }
  }
}
