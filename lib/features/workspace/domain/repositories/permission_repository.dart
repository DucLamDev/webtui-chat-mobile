import '../../../../core/result/result.dart';
import '../entities/workspace_permission.dart';

abstract interface class PermissionRepository {
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  );
}
