import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/moderation/data/datasources/moderation_remote_data_source.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';

void main() {
  test('creates a report from the raw backend response', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'id': 'report-1',
          'workspace_id': 'workspace-1',
          'target_type': 'message',
          'target_id': 'message-1',
          'reason': 'harassment',
          'details': 'Repeated abuse',
          'status': 'pending',
          'created_at': '2026-08-07T00:00:00Z',
        },
      },
    );
    final remote = ModerationRemoteDataSource(api);

    final report = await remote.createReport(
      workspaceId: 'workspace-1',
      targetType: ModerationTargetType.message,
      targetId: 'message-1',
      reason: ModerationReportReason.harassment,
      details: '  Repeated abuse  ',
    );

    expect(api.path, '/api/v1/workspaces/workspace-1/moderation/reports');
    expect(api.method, 'POST');
    expect(api.data, {
      'target_type': 'message',
      'target_id': 'message-1',
      'reason': 'harassment',
      'details': 'Repeated abuse',
    });
    expect(report.id, 'report-1');
    expect(report.reason, ModerationReportReason.harassment);
  });

  test('lists the backend BlockDTO fields from the workspace route', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'blocks': [
            {
              'blocked_user_id': 'user/unsafe',
              'blocked_display_name': 'Blocked user',
              'blocked_username': 'unsafe',
              'blocked_avatar_url': 'https://cdn.example/avatar.png',
              'reason': 'user_safety_action',
              'created_at': '2026-08-07T00:00:00Z',
            },
          ],
        },
      },
    );
    final remote = ModerationRemoteDataSource(api);

    final users = await remote.listBlockedUsers(workspaceId: 'workspace-1');

    expect(api.path, '/api/v1/workspaces/workspace-1/blocks');
    expect(users.single.blockedUserId, 'user/unsafe');
    expect(users.single.displayName, 'Blocked user');
    expect(users.single.username, 'unsafe');
    expect(users.single.avatarUrl, 'https://cdn.example/avatar.png');

    await remote.unblockUser(
      workspaceId: 'workspace-1',
      blockedUserId: 'user/unsafe',
    );
    expect(api.method, 'DELETE');
    expect(api.path, '/api/v1/workspaces/workspace-1/blocks/user%2Funsafe');
  });

  test(
    'blocks a user through workspace blocks and parses raw BlockDTO',
    () async {
      final api = _RecordingApiTransport(
        responseData: {
          'success': true,
          'data': {
            'blocked_user_id': 'user-2',
            'blocked_display_name': 'Blocked user',
            'created_at': '2026-08-07T00:00:00Z',
          },
        },
      );
      final remote = ModerationRemoteDataSource(api);

      final blocked = await remote.blockUser(
        workspaceId: 'workspace-1',
        blockedUserId: 'user-2',
        reason: '  user_safety_action ',
      );

      expect(api.path, '/api/v1/workspaces/workspace-1/blocks');
      expect(api.data, {
        'blocked_user_id': 'user-2',
        'reason': 'user_safety_action',
      });
      expect(blocked.blockedUserId, 'user-2');
      expect(blocked.displayName, 'Blocked user');
    },
  );
}

final class _RecordingApiTransport implements ApiTransport {
  _RecordingApiTransport({this.responseData});

  final Object? responseData;
  String? method;
  String? path;
  Object? data;

  Response<T> _response<T>(String path) {
    return Response<T>(
      data: responseData as T?,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    method = 'DELETE';
    this.path = path;
    this.data = data;
    return _response(path);
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    method = 'GET';
    this.path = path;
    return _response(path);
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    method = 'POST';
    this.path = path;
    this.data = data;
    return _response(path);
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
