import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/workspace_permission.dart';
import '../../domain/repositories/permission_repository.dart';
import '../datasources/permission_remote_data_source.dart';

final class PermissionRepositoryImpl implements PermissionRepository {
  const PermissionRepositoryImpl(this._remote);

  final PermissionRemoteDataSource _remote;

  @override
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  ) {
    return guardResult(() => _remote.listForWorkspace(workspaceId));
  }
}
