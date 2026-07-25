import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/repositories/workspace_repository.dart';
import '../datasources/workspace_remote_data_source.dart';

final class WorkspaceRepositoryImpl implements WorkspaceRepository {
  const WorkspaceRepositoryImpl(this._remote);

  final WorkspaceRemoteDataSource _remote;

  @override
  Future<Result<List<Workspace>>> listMine() {
    return guardResult(_remote.listMine);
  }

  @override
  Future<Result<Workspace>> get(String workspaceId) {
    return guardResult(() => _remote.get(workspaceId));
  }
}
