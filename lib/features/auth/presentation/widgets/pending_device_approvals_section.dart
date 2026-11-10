import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
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
      loading: () =>
          const WebTuiLoadingState(message: 'Đang tải thiết bị chờ duyệt...'),
      error: (_, _) => WebTuiErrorState(
        title: 'Không tải được thiết bị chờ duyệt',
        message: 'Vui lòng thử lại sau.',
        onRetry: () => ref.invalidate(pendingDeviceApprovalsProvider),
      ),
      data: (result) => switch (result) {
        FailureResult<List<DeviceApprovalRequest>>(:final failure) =>
          WebTuiErrorState(
            title: 'Không tải được thiết bị chờ duyệt',
            message: pendingListFailureMessage(failure),
            onRetry: () => ref.invalidate(pendingDeviceApprovalsProvider),
          ),
        Success<List<DeviceApprovalRequest>>(value: final items)
            when items.isEmpty =>
          WebTuiListSurface(
            children: const [
              WebTuiSettingRow(
                title: 'Không có thiết bị chờ duyệt',
                subtitle:
                    'Khi bạn đăng nhập trên thiết bị mới, yêu cầu hiện ở đây',
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
                  title: item.deviceName ?? 'Thiết bị không xác định',
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
