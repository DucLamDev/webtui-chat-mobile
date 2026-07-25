import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../auth/domain/repositories/device_identity_repository.dart';
import '../../domain/entities/workspace_sync_event.dart';
import '../../domain/repositories/workspace_sync_repository.dart';

final class CatchUpWorkspaceSyncUseCase {
  const CatchUpWorkspaceSyncUseCase({
    required WorkspaceSyncRepository repository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _repository = repository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final WorkspaceSyncRepository _repository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<WorkspaceSyncPage>> execute({
    required String workspaceId,
    int limit = 100,
    int maxPages = 5,
  }) async {
    final device = await _readDevice();
    if (device case FailureResult<String>(failure: final failure)) {
      return FailureResult(failure);
    }

    var cursor = (await _repository.readCursor(
      workspaceId: workspaceId,
    )).valueOrNull;
    final deviceId = device.valueOrNull!;
    final events = <WorkspaceSyncEvent>[];
    var hasMore = false;
    var serverTime = DateTime.now().toUtc();
    String? nextCursor;

    for (var pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
      final result = await _repository.catchUp(
        workspaceId: workspaceId,
        deviceId: deviceId,
        cursor: cursor,
        limit: limit,
      );
      switch (result) {
        case Success<WorkspaceSyncPage>(value: final page):
          events.addAll(page.events);
          hasMore = page.hasMore;
          serverTime = page.serverTime;
          nextCursor = page.nextCursor?.trim();
          if (nextCursor == null || nextCursor.isEmpty) {
            return Success(
              WorkspaceSyncPage(
                events: events,
                nextCursor: nextCursor,
                hasMore: hasMore,
                serverTime: serverTime,
              ),
            );
          }
          await _persistCursor(
            workspaceId: workspaceId,
            deviceId: deviceId,
            cursor: nextCursor,
          );
          cursor = nextCursor;
          if (!page.hasMore) {
            return Success(
              WorkspaceSyncPage(
                events: events,
                nextCursor: nextCursor,
                hasMore: false,
                serverTime: serverTime,
              ),
            );
          }
        case FailureResult<WorkspaceSyncPage>(failure: final failure):
          if (events.isEmpty) {
            return FailureResult(failure);
          }
          return Success(
            WorkspaceSyncPage(
              events: events,
              nextCursor: nextCursor,
              hasMore: true,
              serverTime: serverTime,
            ),
          );
      }
    }

    return Success(
      WorkspaceSyncPage(
        events: events,
        nextCursor: nextCursor,
        hasMore: hasMore,
        serverTime: serverTime,
      ),
    );
  }

  Future<Result<String>> _readDevice() async {
    try {
      final device = await _deviceIdentityRepository.currentDevice();
      return Success(device.id);
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể đọc định danh thiết bị để đồng bộ.',
          code: 'SYNC_DEVICE_ID_FAILURE',
          cause: error,
        ),
      );
    }
  }

  Future<void> _persistCursor({
    required String workspaceId,
    required String deviceId,
    required String cursor,
  }) async {
    await _repository.saveCursor(workspaceId: workspaceId, cursor: cursor);
    await _repository.ack(
      workspaceId: workspaceId,
      deviceId: deviceId,
      cursor: cursor,
    );
  }
}
