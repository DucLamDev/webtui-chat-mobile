import '../../../../core/result/result.dart';
import '../entities/workspace.dart';

abstract interface class WorkspaceRepository {
  Future<Result<List<Workspace>>> listMine();

  Future<Result<Workspace>> get(String workspaceId);
}
