import '../../../core/network/self_hosted_server_discovery.dart';
import '../../workspace/domain/entities/workspace_permission.dart';

const inboxViewPermission = 'inbox.view';
const inboxReplyPermission = 'inbox.reply';

/// Ai được thấy mục Hộp thư khách: máy chủ báo `capabilities.omnichannel_inbox`
/// và người dùng có `inbox.view`. Máy chủ vẫn tự kiểm quyền cho mọi yêu cầu.
final class InboxAccess {
  const InboxAccess({
    required this.serverSupported,
    required this.permissionsLoaded,
    required this.canView,
  });

  const InboxAccess.unavailable()
    : serverSupported = false,
      permissionsLoaded = true,
      canView = false;

  final bool serverSupported;
  final bool permissionsLoaded;
  final bool canView;

  bool get isPending => serverSupported && !permissionsLoaded;
}

bool inboxServerSupported(SelfHostedServerDiscovery? discovery) {
  return discovery != null && discovery.capabilities.omnichannelInbox;
}

/// Quyền xem hộp thư của [requestedWorkspaceId] (rỗng = workspace đang mở).
/// Workspace khác (mở từ thông báo) thì để máy chủ kiểm, trả 403 thì màn báo
/// không có quyền.
InboxAccess inboxAccessFor({
  required bool serverSupported,
  required PermissionSet? permissions,
  required bool permissionsLoading,
  required String? activeWorkspaceId,
  required String? requestedWorkspaceId,
}) {
  if (!serverSupported) return const InboxAccess.unavailable();
  final requested = requestedWorkspaceId?.trim() ?? '';
  final active = activeWorkspaceId?.trim() ?? '';
  if (requested.isNotEmpty && requested != active) {
    return const InboxAccess(
      serverSupported: true,
      permissionsLoaded: true,
      canView: true,
    );
  }
  if (permissions == null) {
    return InboxAccess(
      serverSupported: true,
      permissionsLoaded: !permissionsLoading,
      canView: false,
    );
  }
  return InboxAccess(
    serverSupported: true,
    permissionsLoaded: true,
    canView: permissions.allows(inboxViewPermission),
  );
}
