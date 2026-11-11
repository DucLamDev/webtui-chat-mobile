import 'package:dio/dio.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/api_transport.dart';
import '../domain/meeting_models.dart';

/// Gọi API họp (token tham gia) và gọi nhóm có đổ chuông.
abstract interface class MeetingApi {
  Future<MeetingJoinInfo> fetchJoinToken({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  });

  Future<GroupCall> startGroupCall({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String kind,
  });

  Future<GroupCallAcceptance> acceptGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
    String? deviceId,
  });

  Future<List<GroupCall>> fetchRingingGroupCalls({required String workspaceId});

  Future<void> declineGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
  });

  Future<void> endGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
  });
}

final class MeetingRemoteDataSource implements MeetingApi {
  const MeetingRemoteDataSource(this._api);

  final ApiTransport _api;

  @override
  Future<MeetingJoinInfo> fetchJoinToken({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    final response = await _guard(
      () => _api.post<Object>(
        '/api/v1/workspaces/${_seg(workspaceId)}/channels/${_seg(channelId)}'
        '/collaboration/meetings/${_seg(meetingId)}/token',
      ),
    );
    return MeetingJoinInfo.fromMap(jsonMap(envelopeData(response.data)));
  }

  @override
  Future<GroupCall> startGroupCall({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String kind,
  }) async {
    final response = await _guard(
      () => _api.post<Object>(
        _groupCalls(workspaceId, channelId),
        data: {
          'meeting_id': meetingId,
          'kind': kind == 'video' ? 'video' : 'audio',
        },
      ),
    );
    return GroupCall.fromMap(envelopeItem(response.data, 'group_call'));
  }

  @override
  Future<GroupCallAcceptance> acceptGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
    String? deviceId,
  }) async {
    final device = deviceId?.trim() ?? '';
    final response = await _guard(
      () => _api.post<Object>(
        '${_groupCalls(workspaceId, channelId)}/${_seg(groupCallId)}/accept',
        data: device.isEmpty ? null : {'device_id': device},
      ),
    );
    final data = jsonMap(envelopeData(response.data));
    // Hợp đồng: trả kèm token như endpoint token. Chấp nhận cả dạng phẳng và
    // dạng lồng (`join` / `token` là đối tượng).
    final nested =
        jsonMapOrNull(data['meeting_token']) ??
        jsonMapOrNull(data['join']) ??
        jsonMapOrNull(data['token']);
    final callMap = jsonMapOrNull(data['group_call']);
    return GroupCallAcceptance(
      call: callMap == null ? null : GroupCall.fromMap(callMap),
      join: MeetingJoinInfo.fromMap(nested ?? data),
    );
  }

  @override
  Future<List<GroupCall>> fetchRingingGroupCalls({
    required String workspaceId,
  }) async {
    final response = await _guard(
      () => _api.get<Object>(
        '/api/v1/workspaces/${_seg(workspaceId)}/group-calls/ringing',
      ),
    );
    final data = envelopeData(response.data);
    final raw = data is Map ? data['group_calls'] : data;
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (jsonMapOrNull(item) case final map?) GroupCall.fromMap(map),
    ];
  }

  @override
  Future<void> declineGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
  }) async {
    await _guard(
      () => _api.post<Object>(
        '${_groupCalls(workspaceId, channelId)}/${_seg(groupCallId)}/decline',
      ),
    );
  }

  @override
  Future<void> endGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
  }) async {
    await _guard(
      () => _api.post<Object>(
        '${_groupCalls(workspaceId, channelId)}/${_seg(groupCallId)}/end',
      ),
    );
  }

  String _groupCalls(String workspaceId, String channelId) =>
      '/api/v1/workspaces/${_seg(workspaceId)}/channels/${_seg(channelId)}'
      '/group-calls';

  String _seg(String value) => Uri.encodeComponent(value.trim());

  Future<Response<Object>> _guard(
    Future<Response<Object>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw meetingFailureFrom(mapDioExceptionToFailure(error));
    }
  }
}

/// Đổi lỗi máy chủ của họp / gọi nhóm sang câu tiếng Việt dễ hiểu. Giữ nguyên
/// [Failure.kind] và mã lỗi để nơi gọi còn phân biệt (ví dụ 404 do máy chủ cũ).
Failure meetingFailureFrom(Failure failure) {
  final message = switch (failure.code?.trim().toUpperCase()) {
    'MEETING_FORBIDDEN' => 'Bạn không có quyền tham gia cuộc họp này.',
    'MEETING_NOT_FOUND' => 'Không tìm thấy cuộc họp này.',
    'MEETING_NOT_ACTIVE' => 'Cuộc họp đã kết thúc hoặc đã bị hủy.',
    'LIVEKIT_NOT_CONFIGURED' =>
      'Máy chủ chưa cấu hình dịch vụ họp trực tuyến. Hãy báo quản trị viên.',
    'GROUP_CALL_ACTIVE' => 'Kênh này đang có một cuộc gọi nhóm khác đổ chuông.',
    'GROUP_CALL_NOT_FOUND' => 'Không tìm thấy cuộc gọi nhóm này.',
    'GROUP_CALL_NOT_RINGING' => 'Cuộc gọi nhóm không còn đổ chuông.',
    'GROUP_CALL_ENDED' => 'Cuộc gọi nhóm đã kết thúc.',
    'MEETING_PROVIDER_UNSUPPORTED' => 'Máy chủ chưa hỗ trợ loại cuộc họp này.',
    'GROUP_CALLS_UNAVAILABLE' =>
      'Gọi nhóm tạm thời không khả dụng. Hãy thử lại sau.',
    _ => switch (failure.kind) {
      FailureKind.forbidden => 'Bạn không có quyền thực hiện thao tác này.',
      FailureKind.notFound => 'Không tìm thấy cuộc họp hoặc cuộc gọi nhóm.',
      FailureKind.conflict => 'Cuộc họp hoặc cuộc gọi nhóm đã kết thúc.',
      FailureKind.validation =>
        'Máy chủ chưa hỗ trợ thao tác này hoặc dữ liệu không hợp lệ.',
      _ => failure.message,
    },
  };
  return failure.copyWith(message: message);
}
