import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/device_approval.dart';
import '../auth_formatters.dart';
import '../controllers/device_approval_controllers.dart';
import '../screens/device_approval_review_screen.dart';

/// Cài đặt → Phiên: các thiết bị đang chờ chính bạn duyệt (`scope=mine`).
class PendingDeviceApprovalsSection extends ConsumerWidget {
  const PendingDeviceApprovalsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingDeviceApprovalsProvider);
    return pending.when(
      loading: () => WebTuiLoadingState(
        message: tr(
          'Đang tải thiết bị chờ duyệt...',
          'Loading devices waiting for approval...',
        ),
      ),
      error: (_, _) => WebTuiErrorState(
        title: tr(
          'Không tải được thiết bị chờ duyệt',
          'Could not load devices waiting for approval',
        ),
        message: tr('Vui lòng thử lại sau.', 'Please try again later.'),
        onRetry: () => ref.invalidate(pendingDeviceApprovalsProvider),
      ),
      data: (result) => switch (result) {
        FailureResult<List<DeviceApprovalRequest>>(:final failure) =>
          WebTuiErrorState(
            title: tr(
              'Không tải được thiết bị chờ duyệt',
              'Could not load devices waiting for approval',
            ),
            message: pendingListFailureMessage(failure),
            onRetry: () => ref.invalidate(pendingDeviceApprovalsProvider),
          ),
        Success<List<DeviceApprovalRequest>>(value: final items)
            when items.isEmpty =>
          WebTuiListSurface(
            children: [
              WebTuiSettingRow(
                title: tr(
                  'Không có thiết bị chờ duyệt',
                  'No devices waiting for approval',
                ),
                subtitle: tr(
                  'Khi bạn đăng nhập trên thiết bị mới, yêu cầu hiện ở đây',
                  'When you sign in on a new device, the request appears here',
                ),
                icon: Icons.verified_user_outlined,
              ),
            ],
          ),
        Success<List<DeviceApprovalRequest>>(value: final items) =>
          WebTuiListSurface(
            children: [
              for (final item in items)
                WebTuiSettingRow(
                  key: ValueKey('pending-approval-${item.sessionId}'),
                  title:
                      item.deviceName ??
                      tr('Thiết bị không xác định', 'Unknown device'),
                  subtitle: [
                    describeUserAgent(item.userAgent),
                    if (item.ipAddress != null) 'IP ${item.ipAddress}',
                    if (item.createdAt != null)
                      formatAuthDateTime(item.createdAt!),
                  ].join(' · '),
                  icon: Icons.phonelink_lock_rounded,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await context.push(
                      deviceApprovalReviewLocation(item.sessionId),
                    );
                    ref.invalidate(pendingDeviceApprovalsProvider);
                  },
                ),
            ],
          ),
      },
    );
  }
}
