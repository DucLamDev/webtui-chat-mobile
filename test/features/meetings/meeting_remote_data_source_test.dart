import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/meetings/application/meeting_join_flow.dart';
import 'package:webtui_chat/features/meetings/data/meeting_remote_data_source.dart';
import 'package:webtui_chat/features/meetings/domain/meeting_models.dart';

const _tokenBody = {
  'data': {
    'provider': 'livekit',
    'server_url': 'wss://live.example',
    'room': 'r1',
    'token': 'tok',
    'identity': 'u1',
    'display_name': 'An',
  },
};

void main() {
  test('token họp gọi đúng đường dẫn có workspace', () async {
    final transport = _Transport(body: _tokenBody);
    final join = await MeetingRemoteDataSource(
      transport,
    ).fetchJoinToken(workspaceId: 'w1', channelId: 'c1', meetingId: 'm1');
    expect(
      transport.calls.single,
      'POST /api/v1/workspaces/w1/channels/c1/collaboration/meetings/m1/token',
    );
    expect(join.token, 'tok');
    expect(join.provider, MeetingProviderKind.livekit);
  });

  test(
    'gọi nhóm: tạo, nhận, từ chối, kết thúc, danh sách đang đổ chuông',
    () async {
      final transport = _Transport(
        body: {
          'data': {
            'group_call': {'id': 'g1', 'status': 'ringing', 'kind': 'video'},
            'meeting_token': _tokenBody['data'],
            'group_calls': [
              {'id': 'g2', 'status': 'ringing'},
            ],
          },
        },
      );
      final api = MeetingRemoteDataSource(transport);
      final call = await api.startGroupCall(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        kind: 'video',
      );
      expect(call.id, 'g1');
      expect(call.isVideo, isTrue);
      expect(transport.bodies.single, {'meeting_id': 'm1', 'kind': 'video'});

      final accepted = await api.acceptGroupCall(
        workspaceId: 'w1',
        channelId: 'c1',
        groupCallId: 'g1',
        deviceId: 'd1',
      );
      expect(accepted.join.token, 'tok');
      expect(transport.bodies.last, {'device_id': 'd1'});

      await api.declineGroupCall(
        workspaceId: 'w1',
        channelId: 'c1',
        groupCallId: 'g1',
      );
      await api.endGroupCall(
        workspaceId: 'w1',
        channelId: 'c1',
        groupCallId: 'g1',
      );
      final ringing = await api.fetchRingingGroupCalls(workspaceId: 'w1');
      expect(ringing.single.id, 'g2');
      const base = 'POST /api/v1/workspaces/w1/channels/c1/group-calls';
      expect(transport.calls, [
        base,
        '$base/g1/accept',
        '$base/g1/decline',
        '$base/g1/end',
        'GET /api/v1/workspaces/w1/group-calls/ringing',
      ]);
    },
  );

  test('lỗi 403/404/409/422 ra chữ tiếng Việt', () async {
    Future<Failure> fail(int status, String code) async {
      final api = MeetingRemoteDataSource(
        _Transport(status: status, code: code),
      );
      try {
        await api.fetchJoinToken(
          workspaceId: 'w',
          channelId: 'c',
          meetingId: 'm',
        );
      } on Failure catch (f) {
        return f;
      }
      throw StateError('không có lỗi');
    }

    expect(
      (await fail(403, 'MEETING_FORBIDDEN')).message,
      'Bạn không có quyền tham gia cuộc họp này.',
    );
    expect(
      (await fail(404, 'MEETING_NOT_FOUND')).message,
      'Không tìm thấy cuộc họp này.',
    );
    expect(
      (await fail(409, 'MEETING_NOT_ACTIVE')).message,
      'Cuộc họp đã kết thúc hoặc đã bị hủy.',
    );
    expect(
      (await fail(422, 'LIVEKIT_NOT_CONFIGURED')).message,
      contains('chưa cấu hình'),
    );
    expect((await fail(409, 'GROUP_CALL_ENDED')).message, contains('kết thúc'));
  });

  test('Jitsi: 404 máy chủ cũ mở như cũ, MEETING_NOT_FOUND ném lên', () async {
    expect(
      await fetchJitsiJwtOrEmpty(
        MeetingRemoteDataSource(_Transport(status: 404, code: 'NOT_FOUND')),
        workspaceId: 'w',
        channelId: 'c',
        meetingId: 'm',
      ),
      '',
    );
    await expectLater(
      fetchJitsiJwtOrEmpty(
        MeetingRemoteDataSource(
          _Transport(status: 404, code: 'MEETING_NOT_FOUND'),
        ),
        workspaceId: 'w',
        channelId: 'c',
        meetingId: 'm',
      ),
      throwsA(isA<Failure>()),
    );
    expect(
      await fetchJitsiJwtOrEmpty(
        MeetingRemoteDataSource(_Transport(body: _tokenBody)),
        workspaceId: 'w',
        channelId: 'c',
        meetingId: 'm',
      ),
      'tok',
    );
  });
}

final class _Transport implements ApiTransport {
  _Transport({this.body, this.status = 200, this.code});

  final Object? body;
  final int status;
  final String? code;
  final calls = <String>[];
  final bodies = <Object?>[];

  Future<Response<T>> _reply<T>(
    String method,
    String path,
    Object? data,
  ) async {
    calls.add('$method $path');
    if (data != null) bodies.add(data);
    final options = RequestOptions(path: path);
    if (status >= 400) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Object>(
          requestOptions: options,
          statusCode: status,
          data: {
            'error': {'code': code, 'message': 'x'},
          },
        ),
      );
    }
    return Response<T>(
      requestOptions: options,
      data: body as T,
      statusCode: status,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('GET', path, null);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('POST', path, data);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
