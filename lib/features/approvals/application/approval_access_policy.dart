import '../../../core/network/self_hosted_server_discovery.dart';
import '../../workspace/domain/entities/workspace_permission.dart';

const approvalViewPermission = 'approval.view';

/// Ai được thấy mục Phê duyệt. Cần máy chủ báo `capabilities.approvals` và
/// quyền `approval.view`. Máy chủ vẫn tự kiểm quyền cho mọi yêu cầu.
final class ApprovalAccess {
  const ApprovalAccess({
    required this.serverSupported,
    required this.permissionsLoaded,
    required this.canView,
  });

  const ApprovalAccess.unavailable()
    : serverSupported = false,
      permissionsLoaded = true,
      canView = false;

  factory ApprovalAccess.resolve({
    required SelfHostedServerDiscovery? discovery,
    required PermissionSet? permissions,
  }) {
    if (!approvalServerSupported(discovery)) {
      return const ApprovalAccess.unavailable();
    }
    return ApprovalAccess(
      serverSupported: true,
      permissionsLoaded: permissions != null,
      canView: permissions?.allows(approvalViewPermission) ?? false,
    );
  }

  final bool serverSupported;
  final bool permissionsLoaded;
  final bool canView;

  bool get isPending => serverSupported && !permissionsLoaded;
}

bool approvalServerSupported(SelfHostedServerDiscovery? discovery) {
  return discovery != null && discovery.capabilities.approvals;
}

/// Quyền xem phê duyệt của [requestedWorkspaceId] (rỗng = workspace đang mở).
/// Quyền đã tải chỉ thuộc workspace đang mở; workspace khác (mở từ thông báo)
/// thì để máy chủ kiểm, trả 403 thì màn báo không có quyền.
ApprovalAccess approvalAccessFor({
  required bool serverSupported,
  required PermissionSet? permissions,
  required bool permissionsLoading,
  required String? activeWorkspaceId,
  required String? requestedWorkspaceId,
}) {
  if (!serverSupported) return const ApprovalAccess.unavailable();
  final requested = requestedWorkspaceId?.trim() ?? '';
  final active = activeWorkspaceId?.trim() ?? '';
  if (requested.isNotEmpty && requested != active) {
    return const ApprovalAccess(
      serverSupported: true,
      permissionsLoaded: true,
      canView: true,
    );
  }
  if (permissions == null) {
    // Đang tải thì chờ; tải xong mà không có quyền thì coi như không quyền.
    return ApprovalAccess(
      serverSupported: true,
      permissionsLoaded: !permissionsLoading,
      canView: false,
    );
  }
  return ApprovalAccess(
    serverSupported: true,
    permissionsLoaded: true,
    canView: permissions.allows(approvalViewPermission),
  );
}
