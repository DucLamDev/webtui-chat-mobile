import '../../../core/network/self_hosted_server_discovery.dart';
import '../../workspace/domain/entities/workspace_permission.dart';

/// Quyền "Vào trang quản trị": máy chủ trả cho chủ sở hữu, quản trị workspace và
/// vai trò được cấp riêng; thành viên thường không có. Trang quản trị cũng đòi
/// đúng quyền này khi đăng nhập. Ẩn / hiện dòng chỉ là giao diện: máy chủ và
/// trang quản trị tự kiểm lại.
const adminPanelPermission = 'admin.view';

/// Trang quản trị mở từ app nhận `?from=app`: nút "Về giao diện chat" của nó
/// khi đó mở lại app bằng `webtui://chat` thay vì web chat.
const adminPanelFromAppParam = 'from';
const adminPanelFromAppValue = 'app';

/// Có hiện dòng "Trang quản trị" không (quyền của workspace đang mở).
bool canOpenAdminPanel(PermissionSet? permissions) =>
    permissions?.allows(adminPanelPermission) ?? false;

/// Địa chỉ trang quản trị mở bằng trình duyệt: `admin_base_url` của discovery
/// (đã kiểm cùng origin lúc đọc), không có thì `<origin của API>/admin/`; luôn
/// kèm `from=app`. Chưa có discovery thì null.
Uri? adminPanelUri(SelfHostedServerDiscovery? discovery) {
  if (discovery == null) return null;
  final base = discovery.adminBaseUri;
  if (base != null) {
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path.isEmpty ? '/' : base.path,
      queryParameters: const {adminPanelFromAppParam: adminPanelFromAppValue},
    );
  }
  final api = discovery.apiBaseUri;
  return Uri(
    scheme: api.scheme,
    host: api.host,
    port: api.hasPort ? api.port : null,
    path: '/admin/',
    queryParameters: const {adminPanelFromAppParam: adminPanelFromAppValue},
  );
}
