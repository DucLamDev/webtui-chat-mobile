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
