import 'workspace.dart';
import 'workspace_permission.dart';

final class WorkspaceSession {
  const WorkspaceSession({
    required this.workspaces,
    required this.permissions,
    this.activeWorkspace,
    this.activeWasSaved = true,
  });

  final List<Workspace> workspaces;
  final Workspace? activeWorkspace;
  final PermissionSet permissions;

  /// Workspace đang chọn lấy từ lựa chọn đã lưu (false = app tự chọn tạm,
  /// vd. lần đầu đăng nhập).
  final bool activeWasSaved;

  bool get hasActiveWorkspace => activeWorkspace != null;

  /// Lần đầu đăng nhập vào tài khoản có nhiều workspace: hỏi người dùng chọn.
  bool get needsInitialChoice => workspaces.length > 1 && !activeWasSaved;
}
