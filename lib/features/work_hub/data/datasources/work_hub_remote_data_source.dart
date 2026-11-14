import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/work_hub.dart';

/// API tab Công việc: lối tắt ứng dụng, đếm việc, lịch họp chung, tệp chia sẻ.
final class WorkHubRemoteDataSource {
  const WorkHubRemoteDataSource(this._api);

  final ApiTransport _api;

  String _base(String workspaceId) =>
      '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}';

  Future<AppShortcutList> listShortcuts({required String workspaceId}) async {
    final response = await _api.get<Object>('${_base(workspaceId)}/shortcuts');
    final data = jsonMap(envelopeData(response.data));
    return AppShortcutList(
      shortcuts: envelopeList(
        response.data,
        'shortcuts',
      ).map(_shortcutFromMap).toList(growable: false),
      canManage: boolField(data, const ['can_manage', 'canManage']),
    );
  }

  Future<AppShortcut> createShortcut({
    required String workspaceId,
    required AppShortcutDraft draft,
  }) async {
    final response = await _api.post<Object>(
      '${_base(workspaceId)}/shortcuts',
      data: _draftBody(draft),
    );
    return _shortcutFromMap(envelopeItem(response.data, 'shortcut'));
  }

  Future<AppShortcut> updateShortcut({
    required String workspaceId,
    required String shortcutId,
    required AppShortcutDraft draft,
  }) async {
    final response = await _api.patch<Object>(
      '${_base(workspaceId)}/shortcuts/${Uri.encodeComponent(shortcutId)}',
      data: _draftBody(draft),
    );
    return _shortcutFromMap(envelopeItem(response.data, 'shortcut'));
  }

  Future<void> deleteShortcut({
    required String workspaceId,
    required String shortcutId,
  }) async {
    await _api.delete<Object>(
      '${_base(workspaceId)}/shortcuts/${Uri.encodeComponent(shortcutId)}',
    );
  }

  Future<List<AppShortcut>> reorderShortcuts({
    required String workspaceId,
    required List<String> ids,
  }) async {
    final response = await _api.put<Object>(
      '${_base(workspaceId)}/shortcuts/order',
      data: {'ids': ids},
    );
    return envelopeList(
      response.data,
      'shortcuts',
    ).map(_shortcutFromMap).toList(growable: false);
  }

  Future<AssignedTaskSummary> assignedTaskSummary({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '${_base(workspaceId)}/tasks/assigned/summary',
    );
    final map = jsonMap(envelopeData(response.data));
    return AssignedTaskSummary(
      open: intField(map, const ['open']),
      inProgress: intField(map, const ['in_progress', 'inProgress']),
      doneLast7Days: intField(map, const ['done_7d', 'done7d']),
    );
  }

  Future<List<UpcomingMeeting>> upcomingMeetings({
    required String workspaceId,
    int days = 14,
    int limit = 50,
  }) async {
    final response = await _api.get<Object>(
      '${_base(workspaceId)}/meetings/upcoming',
      queryParameters: {'days': days, 'limit': limit},
    );
    return envelopeList(response.data, 'meetings')
        .map(_meetingFromMap)
        .where((meeting) => meeting.channelId.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<SharedFile>> listFiles({
    required String workspaceId,
    int limit = 100,
  }) async {
    final response = await _api.get<Object>(
      '${_base(workspaceId)}/files',
      queryParameters: {'limit': limit},
    );
    return envelopeList(
      response.data,
      'files',
    ).map(_fileFromMap).toList(growable: false);
  }

  /// Xin đường dẫn phát dần (video / ghi âm) cho một tệp; chấp nhận cả dạng
  /// bọc `{data: {...}}` lẫn không bọc.
  Future<SharedFileStreamLink> createFileStreamLink({
    required String workspaceId,
    required String fileId,
  }) async {
    final response = await _api.post<Object>(
      '${_base(workspaceId)}/files/${Uri.encodeComponent(fileId)}/stream-link',
    );
    final map = jsonMap(envelopeData(response.data));
    final url = stringField(map, const ['url']).trim();
    if (url.isEmpty) {
      throw const FormatException('stream-link response has no url');
    }
    final expires = nullableStringField(map, const ['expires_at', 'expiresAt']);
    return SharedFileStreamLink(
      url: url,
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
    );
  }
}

Map<String, Object?> _draftBody(AppShortcutDraft draft) => {
  'title': draft.title,
  'url': draft.url,
  'icon': draft.icon,
  'color': draft.color,
};

AppShortcut _shortcutFromMap(JsonMap map) {
  return AppShortcut(
    id: stringField(map, const ['id']),
    title: stringField(map, const ['title']),
    url: stringField(map, const ['url']),
    icon: stringField(map, const ['icon'], fallback: 'link'),
    color: stringField(map, const ['color'], fallback: 'blue'),
    position: intField(map, const ['position']),
  );
}

UpcomingMeeting _meetingFromMap(JsonMap map) {
  return UpcomingMeeting(
    id: stringField(map, const ['id']),
    channelId: stringField(map, const ['channel_id', 'channelId']),
    channelName: stringField(map, const ['channel_name', 'channelName']),
    title: stringField(map, const ['title']),
    startsAt: dateTimeField(map, const ['starts_at', 'startsAt']),
    endsAt: nullableDateTimeField(map, const ['ends_at', 'endsAt']),
    status: stringField(map, const ['status'], fallback: 'scheduled'),
  );
}

SharedFile _fileFromMap(JsonMap map) {
  return SharedFile(
    id: stringField(map, const ['id', 'file_id']),
    name: stringField(map, const [
      'original_name',
      'name',
      'file_name',
    ], fallback: 'Tệp'),
    mimeType: stringField(map, const [
      'mime_type',
      'mimeType',
    ], fallback: 'application/octet-stream'),
    byteSize: intField(map, const ['byte_size', 'size_bytes', 'size']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    thumbnailUrl: _optionalText(map['thumbnail_url']),
    width: _positiveInt(map['width']),
    height: _positiveInt(map['height']),
    durationMs: _positiveInt(map['duration_ms']),
  );
}

String? _optionalText(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

int? _positiveInt(Object? value) {
  final number = switch (value) {
    final int whole => whole,
    final double real when real.isFinite => real.round(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
  return number != null && number > 0 ? number : null;
}
