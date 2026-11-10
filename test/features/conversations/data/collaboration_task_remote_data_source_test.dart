import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';

void main() {
  const base = '/api/v1/workspaces/ws-1/channels/ch-1/collaboration/tasks';

  test('tạo việc gửi mô tả, người làm và hạn theo giờ UTC', () async {
    final transport = _RecordingApiTransport();
    final remote = ConversationRemoteDataSource(transport);

    final task = await remote.createCollaborationTask(
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      title: 'Gửi báo giá',
      description: 'Cho khách A',
      assigneeUserId: 'u-2',
      dueAt: DateTime.parse('2026-11-05T17:00:00+07:00'),
    );

    final call = transport.calls.single;
    expect(call.method, 'POST');
    expect(call.path, base);
    expect(call.data, {
      'title': 'Gửi báo giá',
      'description': 'Cho khách A',
      'assignee_user_id': 'u-2',
      'due_at': '2026-11-05T10:00:00.000Z',
    });
    expect(task.channelName, isNull);
    expect(task.createdBy, 'u-1');
    expect(task.description, 'Mô tả');
  });

  test(
    'sửa việc chỉ gửi trường đổi; chuỗi rỗng là bỏ giao / xoá hạn',
    () async {
      final transport = _RecordingApiTransport();
      final remote = ConversationRemoteDataSource(transport);

      await remote.updateCollaborationTask(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        taskId: 't/1',
        status: 'in_progress',
      );
      await remote.updateCollaborationTask(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        taskId: 't-1',
        assigneeUserId: '',
        clearDueAt: true,
      );

      expect(transport.calls[0].path, '$base/t%2F1');
      expect(transport.calls[0].data, {'status': 'in_progress'});
      expect(transport.calls[1].data, {'assignee_user_id': '', 'due_at': ''});
    },
  );

  test('xoá việc và "Việc của tôi" gọi đúng đường dẫn', () async {
    final transport = _RecordingApiTransport();
    final remote = ConversationRemoteDataSource(transport);

    await remote.deleteCollaborationTask(
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      taskId: 't-1',
    );
    final mine = await remote.listAssignedTasks(workspaceId: 'ws-1');

    expect(transport.calls[0].method, 'DELETE');
    expect(transport.calls[0].path, '$base/t-1');
    expect(transport.calls[1].path, '/api/v1/workspaces/ws-1/tasks/assigned');
    expect(transport.calls[1].query, {
      'status': 'active',
      'limit': 50,
      'offset': 0,
    });
    expect(mine.single.channelName, 'Dự án A');
    expect(mine.single.workspaceId, 'ws-1');
  });
}

final class _Call {
  _Call(this.method, this.path, this.data, this.query);

  final String method;
  final String path;
  final Object? data;
  final Map<String, dynamic>? query;
}

final class _RecordingApiTransport implements ApiTransport {
  final calls = <_Call>[];

  static const _task = {
    'id': 't-1',
    'workspace_id': 'ws-1',
    'channel_id': 'ch-1',
    'title': 'Gửi báo giá',
    'description': 'Mô tả',
    'status': 'open',
    'created_by': 'u-1',
    'created_at': '2026-11-02T03:00:00Z',
    'updated_at': '2026-11-02T03:00:00Z',
  };

  Response<T> _ok<T>(String path, Object? data) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'success': true, 'data': data} as T,
  );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add(_Call('GET', path, null, queryParameters));
    return _ok<T>(path, {
      'tasks': [
        {..._task, 'channel_name': 'Dự án A', 'channel_type': 'public'},
      ],
    });
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add(_Call('POST', path, data, queryParameters));
    return _ok<T>(path, _task);
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add(_Call('PATCH', path, data, queryParameters));
    return _ok<T>(path, _task);
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add(_Call('DELETE', path, data, queryParameters));
    return _ok<T>(path, null);
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
