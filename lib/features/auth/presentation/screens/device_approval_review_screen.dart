import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../application/use_cases/device_approval_use_cases.dart';
import '../../domain/entities/device_approval.dart';
import '../auth_formatters.dart';
import '../controllers/device_approval_controllers.dart';

String deviceApprovalReviewLocation(String sessionId) {
  return Uri(
    pathSegments: ['', 'device-approvals', sessionId.trim()],
  ).toString();
}

/// Duyệt / từ chối một thiết bị đang xin đăng nhập (máy tin cậy hoặc quản
/// trị). Dữ liệu luôn tải lại từ máy chủ, không tin payload WS / push.
class DeviceApprovalReviewScreen extends ConsumerWidget {
  const DeviceApprovalReviewScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceApprovalReviewControllerProvider(sessionId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Đóng',
          onPressed: () => _close(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('Duyệt thiết bị mới'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: switch (state.phase) {
          ReviewPhase.loading => const WebTuiLoadingState(
            message: 'Đang tải yêu cầu duyệt...',
          ),
          ReviewPhase.error => WebTuiErrorState(
            title: 'Không tải được yêu cầu',
            message: state.errorMessage ?? 'Vui lòng thử lại.',
            onRetry: controller.load,
          ),
          ReviewPhase.notFound => WebTuiEmptyState(
            title: 'Không còn yêu cầu chờ duyệt',
            message:
                state.errorMessage ??
                'Yêu cầu đã được xử lý, đã hết hạn hoặc bạn không có quyền duyệt.',
            icon: Icons.verified_user_outlined,
          ),
          ReviewPhase.decided => _DecidedView(
            status: state.resultStatus ?? '',
            onClose: () => _close(context),
          ),
          ReviewPhase.ready || ReviewPhase.deciding => _RequestView(
            request: state.request!,
            busy: state.phase == ReviewPhase.deciding,
            errorMessage: state.errorMessage,
            onApprove: () => controller.decide(approve: true),
            onReject: () => _confirmReject(context, controller),
          ),
        },
      ),
    );
  }

  Future<void> _confirmReject(
    BuildContext context,
    DeviceApprovalReviewController controller,
  ) async {
    final confirmed = await showWebTuiConfirmDialog(
      context,
      title: 'Từ chối thiết bị này?',
      message:
          'Thiết bị sẽ bị đăng xuất ngay. Nếu không phải bạn đăng nhập, hãy đổi '
          'mật khẩu sau khi từ chối.',
      confirmLabel: 'Từ chối',
      cancelLabel: 'Hủy',
      destructive: true,
      icon: WebTuiIcons.close,
    );
    if (confirmed) {
      await controller.decide(approve: false);
    }
  }
}

void _close(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go('/');
  }
}

class _RequestView extends StatelessWidget {
  const _RequestView({
    required this.request,
    required this.busy,
    required this.errorMessage,
    required this.onApprove,
    required this.onReject,
  });

  final DeviceApprovalRequest request;
  final bool busy;
  final String? errorMessage;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final createdAt = request.createdAt;
    final expiresAt = request.approvalExpiresAt;
    final method = authMethodLabel(request.authMethod);
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        Text(
          request.isSelf
              ? 'Có thiết bị đang đăng nhập vào tài khoản của bạn. Chỉ đồng ý nếu '
                    'chính bạn vừa đăng nhập.'
              : '${request.userDisplayName ?? 'Một thành viên'} đang đăng nhập '
                    'trên thiết bị mới và cần bạn duyệt '
                    '(${deviceApprovalRoleLabel(request.myRole)}).',
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textSecondary,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: WebTuiColors.surface,
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!request.isSelf)
                  _InfoLine(
                    label: 'Người dùng',
                    value: [
                      request.userDisplayName,
                      request.userEmail,
                    ].whereType<String>().join(' · '),
                  ),
                _InfoLine(
                  label: 'Thiết bị',
                  value: request.deviceName ?? 'Không xác định',
                ),
                _InfoLine(
                  label: 'Trình duyệt / hệ điều hành',
                  value: describeUserAgent(request.userAgent),
                ),
                _InfoLine(
                  label: 'Địa chỉ IP',
                  value: request.ipAddress ?? 'Không xác định',
                ),
                if (createdAt != null)
                  _InfoLine(
                    label: 'Thời điểm',
                    value: formatAuthDateTime(createdAt),
                  ),
                if (method.isNotEmpty)
                  _InfoLine(label: 'Cách đăng nhập', value: method),
                if (expiresAt != null)
                  _InfoLine(
                    label: 'Hết hạn duyệt',
                    value: formatAuthDateTime(expiresAt),
                  ),
              ],
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            errorMessage!,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: WebTuiSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('device_approval_reject_button'),
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: WebTuiColors.danger,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.block_rounded),
                label: const Text('Từ chối'),
              ),
            ),
            const SizedBox(width: WebTuiSpacing.md),
            Expanded(
              child: FilledButton.icon(
                key: const Key('device_approval_approve_button'),
                onPressed: busy ? null : onApprove,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Đồng ý'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
          Text(
            value.isEmpty ? 'Không xác định' : value,
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecidedView extends StatelessWidget {
  const _DecidedView({required this.status, required this.onClose});

  final String status;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (status) {
      'approved' => (
        Icons.verified_rounded,
        'Đã cho phép thiết bị',
        'Thiết bị mới có thể dùng ứng dụng ngay.',
      ),
      'rejected' => (
        Icons.gpp_bad_rounded,
        'Đã từ chối thiết bị',
        'Thiết bị đã bị đăng xuất.',
      ),
      _ => (
        Icons.hourglass_top_rounded,
        'Đã ghi nhận đồng ý',
        'Thiết bị còn chờ người duyệt thứ hai (quản trị viên).',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: WebTuiColors.primary),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: WebTuiSpacing.lg),
            FilledButton(onPressed: onClose, child: const Text('Xong')),
          ],
        ),
      ),
    );
  }
}
