import 'workspace.dart';
import 'workspace_permission.dart';

final class WorkspaceSession {
  const WorkspaceSession({
    required this.workspaces,
    required this.permissions,
    this.activeWorkspace,
  });

  final List<Workspace> workspaces;
  final Workspace? activeWorkspace;
  final PermissionSet permissions;

  bool get hasActiveWorkspace => activeWorkspace != null;
}
