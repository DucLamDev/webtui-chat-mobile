import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/workspace_sync_event.dart';
import '../../domain/repositories/workspace_sync_repository.dart';
import '../datasources/local_workspace_sync_cursor_data_source.dart';
import '../datasources/workspace_sync_remote_data_source.dart';

final class WorkspaceSyncRepositoryImpl implements WorkspaceSyncRepository {
  const WorkspaceSyncRepositoryImpl({
    required WorkspaceSyncRemoteDataSource remote,
    required LocalWorkspaceSyncCursorDataSource localCursor,
  }) : _remote = remote,
       _localCursor = localCursor;

  final WorkspaceSyncRemoteDataSource _remote;
  final LocalWorkspaceSyncCursorDataSource _localCursor;

  @override
  Future<Result<String?>> readCursor({required String workspaceId}) {
    return guardResult(() => _localCursor.readCursor(workspaceId: workspaceId));
  }

  @override
  Future<Result<void>> saveCursor({
    required String workspaceId,
    required String cursor,
  }) {
    return guardResult(
      () => _localCursor.saveCursor(workspaceId: workspaceId, cursor: cursor),
    );
  }

  @override
  Future<Result<WorkspaceSyncPage>> catchUp({
    required String workspaceId,
    required String deviceId,
    String? cursor,
    int limit = 100,
  }) {
    return guardResult(
      () => _remote.catchUp(
        workspaceId: workspaceId,
        deviceId: deviceId,
        cursor: cursor,
        limit: limit,
      ),
    );
  }

  @override
  Future<Result<void>> ack({
    required String workspaceId,
    required String deviceId,
    required String cursor,
  }) {
    return guardResult(
      () => _remote.ack(
        workspaceId: workspaceId,
        deviceId: deviceId,
        cursor: cursor,
      ),
    );
  }
}
