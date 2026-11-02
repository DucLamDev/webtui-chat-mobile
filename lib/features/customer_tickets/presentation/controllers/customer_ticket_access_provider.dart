import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/customer_ticket_access_policy.dart';

/// Quyền vào hộp thư ticket khách của workspace đang mở. Máy chủ không phải
/// máy chủ nội bộ thì trả "không hỗ trợ" ngay, không đọc quyền workspace.
final customerTicketAccessProvider = Provider.autoDispose<CustomerTicketAccess>((
  ref,
) {
  final discovery = ref.watch(activeServerDiscoveryProvider);
  if (!customerTicketServerSupported(discovery)) {
    return const CustomerTicketAccess.unavailable();
  }
  final workspace = ref.watch(
    workspaceControllerProvider.select(
      (state) => (permissions: state.permissions, loading: state.isLoading),
    ),
  );
  final access = CustomerTicketAccess.resolve(
    discovery: discovery,
    permissions: workspace.permissions,
  );
  if (access.isPending && !workspace.loading) {
    // Đã tải xong mà không có quyền nào (lỗi tải quyền): coi như không có quyền.
    return const CustomerTicketAccess(
      serverSupported: true,
      permissionsLoaded: true,
      canView: false,
      canReply: false,
    );
  }
  return access;
});

/// Số ticket chưa trả lời cho ô "Ticket khách" ở tab Nghiệp vụ; `null` khi
/// chưa lấy được. Tải lại khi mở tab (provider tự huỷ khi rời tab) hoặc khi
/// kéo làm mới hộp thư (`ref.invalidate`).
final customerTicketUnansweredCountProvider = FutureProvider.autoDispose
    .family<int?, String>((ref, workspaceId) async {
      final result = await ref
          .watch(countUnansweredCustomerTicketsUseCaseProvider)
          .execute(workspaceId);
      return result.valueOrNull;
    });

/// Đồng hồ cho nhãn "Chờ X phút" / giờ tin nhắn (test ghi đè để cố định).
final customerTicketClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);
