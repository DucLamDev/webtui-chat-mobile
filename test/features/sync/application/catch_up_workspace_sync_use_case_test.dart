import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';
import 'package:webtui_chat/features/auth/domain/repositories/device_identity_repository.dart';
import 'package:webtui_chat/features/sync/application/use_cases/workspace_sync_use_cases.dart';
import 'package:webtui_chat/features/sync/domain/entities/workspace_sync_event.dart';
import 'package:webtui_chat/features/sync/domain/repositories/workspace_sync_repository.dart';

void main() {
  test('catch-up reads cursor and acks each returned next cursor', () async {
    final repository = _FakeWorkspaceSyncRepository(
      pages: [
        WorkspaceSyncPage(
          events: [_event('event-1')],
          nextCursor: 'event-1',
          hasMore: true,
          serverTime: DateTime.utc(2026, 7, 17, 9),
        ),
        WorkspaceSyncPage(
          events: [_event('event-2')],
          nextCursor: 'event-2',
          serverTime: DateTime.utc(2026, 7, 17, 9, 1),
        ),
      ],
    );
    final useCase = CatchUpWorkspaceSyncUseCase(
      repository: repository,
      deviceIdentityRepository: const _FakeDeviceIdentityRepository(),
    );

    final result = await useCase.execute(workspaceId: 'workspace-1');

    final page = result.valueOrNull;
    expect(page!.events.map((event) => event.eventId), ['event-1', 'event-2']);
    expect(page.nextCursor, 'event-2');
    expect(repository.requestedCursors, [null, 'event-1']);
    expect(repository.savedCursors, ['event-1', 'event-2']);
    expect(repository.ackedCursors, ['event-1', 'event-2']);
  });
}

WorkspaceSyncEvent _event(String id) {
  return WorkspaceSyncEvent(
    eventId: id,
    workspaceId: 'workspace-1',
    type: 'MessageCreated',
    aggregateType: 'message',
    aggregateId: 'message-$id',
    eventVersion: 1,
    occurredAt: DateTime.utc(2026, 7, 17, 9),
  );
}

final class _FakeWorkspaceSyncRepository implements WorkspaceSyncRepository {
  _FakeWorkspaceSyncRepository({required this.pages});

  final List<WorkspaceSyncPage> pages;
  final requestedCursors = <String?>[];
  final savedCursors = <String>[];
  final ackedCursors = <String>[];
  int _pageIndex = 0;

  @override
  Future<Result<String?>> readCursor({required String workspaceId}) async {
    return const Success(null);
  }

  @override
  Future<Result<void>> saveCursor({
    required String workspaceId,
    required String cursor,
  }) async {
    savedCursors.add(cursor);
    return const Success(null);
  }

  @override
  Future<Result<WorkspaceSyncPage>> catchUp({
    required String workspaceId,
    required String deviceId,
    String? cursor,
    int limit = 100,
  }) async {
    requestedCursors.add(cursor);
    return Success(pages[_pageIndex++]);
  }

  @override
  Future<Result<void>> ack({
    required String workspaceId,
    required String deviceId,
    required String cursor,
  }) async {
    ackedCursors.add(cursor);
    return const Success(null);
  }
}

final class _FakeDeviceIdentityRepository implements DeviceIdentityRepository {
  const _FakeDeviceIdentityRepository();

  @override
  Future<DeviceIdentity> currentDevice() async {
    return const DeviceIdentity(
      id: 'device-1',
      platform: 'test',
      displayName: 'Test device',
    );
  }
}
