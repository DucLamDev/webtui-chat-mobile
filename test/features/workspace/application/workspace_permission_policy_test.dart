import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/workspace/application/use_cases/workspace_permission_policy.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';

void main() {
  test('gates UI by permission code, not role-like display text', () {
    final permissions = PermissionSet(const [
      WorkspacePermission(
        id: 'p1',
        code: 'workspace.view_members',
        module: 'workspace',
        action: 'view_members',
        name: 'Xem thành viên',
      ),
      WorkspacePermission(
        id: 'p2',
        code: 'message.read',
        module: 'message',
        action: 'read',
        name: 'Đọc tin nhắn',
      ),
    ]);

    final policy = WorkspacePermissionPolicy(permissions);

    expect(policy.canViewMembers(), isTrue);
    expect(policy.canReadMessages(), isTrue);
    expect(policy.canManageWorkspace(), isFalse);
    expect(permissions.allows('workspace_admin'), isFalse);
  });
}
