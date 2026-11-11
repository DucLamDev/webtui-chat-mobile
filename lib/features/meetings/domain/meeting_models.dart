import '../../../core/network/api_response.dart';

/// Máy chủ họp: LiveKit (họp ngay trong app) hoặc Jitsi (mở trình duyệt).
enum MeetingProviderKind {
  livekit,
  jitsi;

  static MeetingProviderKind fromApi(String? value) =>
      value?.trim().toLowerCase() == 'livekit' ? livekit : jitsi;
}

/// Kết quả `POST .../meetings/{id}/token` (và `group-calls/{id}/accept`).
final class MeetingJoinInfo {
  const MeetingJoinInfo({
    required this.provider,
    required this.serverUrl,
    required this.room,
    required this.token,
    this.expiresAt,
    this.identity = '',
    this.displayName = '',
    this.canPublishAudio = true,
    this.canPublishVideo = true,
    this.canShareScreen = false,
    this.isModerator = false,
    this.e2ee = false,
  });

  factory MeetingJoinInfo.fromMap(JsonMap map) {
    return MeetingJoinInfo(
      provider: MeetingProviderKind.fromApi(
        stringField(map, const ['provider']),
      ),
      serverUrl: stringField(map, const ['server_url']).trim(),
      room: stringField(map, const ['room']).trim(),
      token: stringField(map, const ['token']).trim(),
      expiresAt: nullableDateTimeField(map, const ['expires_at']),
      identity: stringField(map, const ['identity']),
      displayName: stringField(map, const ['display_name']),
      canPublishAudio: boolField(map, const [
        'can_publish_audio',
      ], fallback: true),
      canPublishVideo: boolField(map, const [
        'can_publish_video',
      ], fallback: true),
      canShareScreen: boolField(map, const ['can_share_screen']),
      isModerator: boolField(map, const ['is_moderator']),
      e2ee: boolField(map, const ['e2ee']),
    );
  }

  final MeetingProviderKind provider;
  final String serverUrl;
  final String room;
  final String token;
  final DateTime? expiresAt;
  final String identity;
  final String displayName;
  final bool canPublishAudio;
  final bool canPublishVideo;
  final bool canShareScreen;
  final bool isModerator;
  final bool e2ee;

  /// Địa chỉ phòng Jitsi kèm `?jwt=` khi máy chủ cấp token; không có token thì
  /// trả [base] như cũ. Token luôn được mã hoá khi ghép vào địa chỉ.
  static Uri withJitsiJwt(Uri base, String token) {
    final jwt = token.trim();
    if (jwt.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, 'jwt': jwt});
  }
}

enum GroupCallStatus {
  ringing,
  active,
  ended;

  static GroupCallStatus fromApi(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'active' => active,
        'ended' => ended,
        _ => ringing,
      };
}

/// Cuộc gọi nhóm có đổ chuông (`GroupCall` trong hợp đồng).
final class GroupCall {
  const GroupCall({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.meetingId,
    required this.kind,
    required this.status,
    this.provider = MeetingProviderKind.jitsi,
    this.startedBy = '',
    this.startedByName = '',
    this.channelName = '',
    this.ringTruncated = false,
    this.ringEndsAt,
  });

  factory GroupCall.fromMap(JsonMap map) {
    return GroupCall(
      id: stringField(map, const ['id', 'group_call_id']).trim(),
      workspaceId: stringField(map, const ['workspace_id']).trim(),
      channelId: stringField(map, const ['channel_id']).trim(),
      meetingId: stringField(map, const ['meeting_id']).trim(),
      kind: stringField(map, const ['kind']).trim().toLowerCase() == 'video'
          ? 'video'
          : 'audio',
      status: GroupCallStatus.fromApi(stringField(map, const ['status'])),
      provider: MeetingProviderKind.fromApi(
        stringField(map, const ['provider']),
      ),
      startedBy: stringField(map, const ['started_by']),
      startedByName: stringField(map, const ['started_by_name', 'caller_name']),
      channelName: stringField(map, const ['channel_name']),
      ringTruncated: boolField(map, const ['ring_truncated']),
      ringEndsAt: nullableDateTimeField(map, const ['ring_ends_at']),
    );
  }

  final String id;
  final String workspaceId;
  final String channelId;
  final String meetingId;

  /// `audio` hoặc `video`.
  final String kind;
  final GroupCallStatus status;
  final MeetingProviderKind provider;
  final String startedBy;
  final String startedByName;
  final DateTime? ringEndsAt;
  final String channelName;
  final bool ringTruncated;

  /// Bản sao có `workspaceId` (danh sách đang đổ chuông có thể không kèm).
  GroupCall withWorkspace(String value) => GroupCall(
    id: id,
    workspaceId: value,
    channelId: channelId,
    meetingId: meetingId,
    kind: kind,
    status: status,
    provider: provider,
    startedBy: startedBy,
    startedByName: startedByName,
    channelName: channelName,
    ringTruncated: ringTruncated,
    ringEndsAt: ringEndsAt,
  );

  bool get isVideo => kind == 'video';
  bool get isRinging => status == GroupCallStatus.ringing;

  /// Dòng hiển thị trên chuông: "người gọi đang gọi nhóm tên kênh".
  String get ringTitle => groupCallRingTitle(startedByName, channelName);
}

String groupCallRingTitle(String callerName, String channelName) {
  final caller = callerName.trim().isEmpty ? 'Một thành viên' : callerName;
  final channel = channelName.trim();
  return channel.isEmpty
      ? '$caller đang gọi nhóm'
      : '$caller đang gọi nhóm $channel';
}

/// Kết quả nhận cuộc gọi nhóm: thông tin cuộc gọi + token vào họp.
final class GroupCallAcceptance {
  const GroupCallAcceptance({required this.call, required this.join});

  final GroupCall? call;
  final MeetingJoinInfo join;
}
