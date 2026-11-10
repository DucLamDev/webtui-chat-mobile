import '../../../core/network/self_hosted_server_discovery.dart';
import '../../workspace/domain/entities/workspace_permission.dart';

const customerTicketViewPermission = 'order.view';
const customerTicketReplyPermission = 'order.ticket_reply';

/// Ai được thấy / trả lời ticket khách. Chỉ máy chủ nội bộ VPSTTT (discovery:
/// host + zone nội bộ, có capability `bots`) mới có hộp thư ticket; trong đó
/// xem cần `order.view`, trả lời / thao tác cần thêm `order.ticket_reply`.
/// Máy chủ vẫn tự kiểm quyền cho mọi yêu cầu: đây chỉ là ẩn / hiện giao diện.
final class CustomerTicketAccess {
  const CustomerTicketAccess({
    required this.serverSupported,
    required this.permissionsLoaded,
    required this.canView,
    required this.canReply,
  });

  const CustomerTicketAccess.unavailable()
    : serverSupported = false,
      permissionsLoaded = true,
      canView = false,
      canReply = false;

  factory CustomerTicketAccess.resolve({
    required SelfHostedServerDiscovery? discovery,
    required PermissionSet? permissions,
  }) {
    if (!customerTicketServerSupported(discovery)) {
      return const CustomerTicketAccess.unavailable();
    }
    final canView = permissions?.allows(customerTicketViewPermission) ?? false;
    return CustomerTicketAccess(
      serverSupported: true,
      permissionsLoaded: permissions != null,
      canView: canView,
      canReply:
          canView &&
          (permissions?.allows(customerTicketReplyPermission) ?? false),
    );
  }

  final bool serverSupported;
  final bool permissionsLoaded;
  final bool canView;
  final bool canReply;

  /// Máy chủ hỗ trợ nhưng quyền của workspace chưa tải xong.
  bool get isPending => serverSupported && !permissionsLoaded;
}

bool customerTicketServerSupported(SelfHostedServerDiscovery? discovery) {
  return discovery != null &&
      discovery.vpstttInternalModules &&
      discovery.capabilities.bots;
}
