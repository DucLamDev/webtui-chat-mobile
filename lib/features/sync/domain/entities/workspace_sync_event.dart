import '../../../../core/network/api_response.dart';

final class WorkspaceSyncEvent {
  const WorkspaceSyncEvent({
    required this.eventId,
    required this.workspaceId,
    required this.type,
    required this.aggregateType,
    required this.aggregateId,
    required this.eventVersion,
    required this.occurredAt,
    this.payload = const {},
  });

  final String eventId;
  final String workspaceId;
  final String type;
  final String aggregateType;
  final String aggregateId;
  final int eventVersion;
  final DateTime occurredAt;
  final JsonMap payload;
}

final class WorkspaceSyncPage {
  const WorkspaceSyncPage({
    required this.events,
    required this.serverTime,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<WorkspaceSyncEvent> events;
  final String? nextCursor;
  final bool hasMore;
  final DateTime serverTime;
}
