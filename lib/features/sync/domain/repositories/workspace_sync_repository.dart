import '../../../../core/result/result.dart';
import '../entities/workspace_sync_event.dart';

abstract interface class WorkspaceSyncRepository {
  Future<Result<String?>> readCursor({required String workspaceId});

  Future<Result<void>> saveCursor({
    required String workspaceId,
    required String cursor,
  });

  Future<Result<WorkspaceSyncPage>> catchUp({
    required String workspaceId,
    required String deviceId,
    String? cursor,
    int limit = 100,
  });

  Future<Result<void>> ack({
    required String workspaceId,
    required String deviceId,
    required String cursor,
  });
}
