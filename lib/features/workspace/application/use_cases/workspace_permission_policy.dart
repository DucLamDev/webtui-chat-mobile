import '../../domain/entities/workspace_permission.dart';

final class WorkspacePermissionPolicy {
  const WorkspacePermissionPolicy(this.permissions);

  final PermissionSet permissions;

  bool canViewMembers() => permissions.allows('workspace.view_members');

  bool canManageWorkspace() => permissions.allows('workspace.manage');

  bool canInviteUsers() => permissions.allows('workspace.invite_user');

  bool canManageRoles() => permissions.allows('role.manage');

  bool canManageUsers() => permissions.allows('user.manage');

  bool canReadMessages() => permissions.allowsAny(const [
    'message.read',
    'channel.read',
    'workspace.view_members',
  ]);
}
