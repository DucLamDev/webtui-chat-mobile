import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/workspace_sync_event.dart';

final class WorkspaceSyncRemoteDataSource {
  const WorkspaceSyncRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<WorkspaceSyncPage> catchUp({
    required String workspaceId,
    required String deviceId,
    String? cursor,
    int limit = 100,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}/sync',
      queryParameters: compactMap({
        'device_id': deviceId,
        'cursor': cursor,
        'limit': limit,
      }),
    );
    final data = jsonMap(envelopeData(response.data));
    final events = jsonMapList(
      data['events'],
    ).map(_eventFromMap).toList(growable: false);
    return WorkspaceSyncPage(
      events: events,
      nextCursor: nullableStringField(data, const [
        'next_cursor',
        'nextCursor',
      ]),
      hasMore: boolField(data, const ['has_more', 'hasMore']),
      serverTime: dateTimeField(data, const ['server_time', 'serverTime']),
    );
  }

  Future<void> ack({
    required String workspaceId,
    required String deviceId,
    required String cursor,
  }) async {
    await _api.post<Object>(
      '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}/sync/ack',
      data: {'device_id': deviceId, 'cursor': cursor},
    );
  }
}

WorkspaceSyncEvent _eventFromMap(JsonMap map) {
  return WorkspaceSyncEvent(
    eventId: stringField(map, const ['event_id', 'eventId']),
    workspaceId: stringField(map, const ['workspace_id', 'workspaceId']),
    type: stringField(map, const ['type']),
    aggregateType: stringField(map, const ['aggregate_type', 'aggregateType']),
    aggregateId: stringField(map, const ['aggregate_id', 'aggregateId']),
    eventVersion: intField(map, const ['event_version', 'eventVersion']),
    occurredAt: dateTimeField(map, const ['occurred_at', 'occurredAt']),
    payload: jsonMap(map['payload']),
  );
}
