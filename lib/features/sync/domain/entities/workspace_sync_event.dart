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
    this.resetRequired = false,
    this.resetReason,
  });

  final List<WorkspaceSyncEvent> events;
  final String? nextCursor;
  final bool hasMore;
  final DateTime serverTime;

  /// Con trỏ đồng bộ đã bị dọn / không còn: máy chủ không trả lại được các sự
  /// kiện đã lỡ, app phải tải lại danh sách hội thoại và hội thoại đang mở rồi
  /// đi tiếp từ [nextCursor] ("bây giờ").
  final bool resetRequired;

  /// `cursor_expired` hoặc `cursor_unknown` (chỉ để ghi nhận).
  final String? resetReason;
}
