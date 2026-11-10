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
    this.canReply = false,
  });

  const InboxAccess.unavailable()
    : serverSupported = false,
      permissionsLoaded = true,
      canView = false,
      canReply = false;

  final bool serverSupported;
  final bool permissionsLoaded;
  final bool canView;

  /// Có `inbox.reply`: trả lời, ghi chú, nhận / bỏ nhận, đổi trạng thái, tag.
  final bool canReply;

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
    // Chủ ý: app chỉ nạp quyền của workspace đang mở, không biết quyền của
    // workspace khác (vd. mở từ thông báo). Nên cho vào và để máy chủ kiểm
    // quyền từng yêu cầu; thiếu quyền thì máy chủ trả 403 và màn báo "không có
    // quyền". Ẩn nút không phải là chặn quyền.
    return const InboxAccess(
      serverSupported: true,
      permissionsLoaded: true,
      canView: true,
      canReply: true,
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
    canReply:
        permissions.allows(inboxViewPermission) &&
        permissions.allows(inboxReplyPermission),
  );
}
