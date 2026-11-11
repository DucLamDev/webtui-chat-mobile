import '../../../core/error/failure.dart';
import '../data/meeting_remote_data_source.dart';
import '../domain/meeting_models.dart';

/// Lấy token Jitsi để ghép `?jwt=`. Trả chuỗi rỗng (mở phòng như cũ, không
/// jwt) khi máy chủ chưa có endpoint token (404 không kèm mã cuộc họp) hoặc
/// chưa cấu hình JWT. Lỗi thật của cuộc họp (không quyền, đã kết thúc) được
/// ném lên để báo người dùng.
Future<String> fetchJitsiJwtOrEmpty(
  MeetingApi api, {
  required String workspaceId,
  required String channelId,
  required String? meetingId,
}) async {
  final id = meetingId?.trim() ?? '';
  if (id.isEmpty) return '';
  try {
    final join = await api.fetchJoinToken(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: id,
    );
    return join.token;
  } on Failure catch (failure) {
    if (_isLegacyServerMissingEndpoint(failure)) return '';
    rethrow;
  }
}

bool _isLegacyServerMissingEndpoint(Failure failure) {
  if (failure.kind != FailureKind.notFound) return false;
  final code = failure.code?.trim().toUpperCase() ?? '';
  return code != 'MEETING_NOT_FOUND';
}

/// Họp chạy trong app khi cuộc họp dùng LiveKit và máy chủ báo bật LiveKit.
bool opensMeetingInApp({
  required String meetingProvider,
  required bool livekitCapability,
}) =>
    MeetingProviderKind.fromApi(meetingProvider) ==
        MeetingProviderKind.livekit &&
    livekitCapability;
