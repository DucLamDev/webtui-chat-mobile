import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/collaboration_document_history_remote_data_source.dart';
import 'package:webtui_chat/features/conversations/data/datasources/rich_message_remote_data_source.dart';

void main() {
  test('Callback chỉ gửi action_id, đọc cờ trùng từ envelope', () async {
    final api = _Transport({
      'interaction': {
        'interaction_id': 'i',
        'action_id': 'confirm',
        'duplicate': true,
        'created_at': '2026-11-10T00:00:00Z',
      },
    });
    final result = await RichMessageRemoteDataSource(api).invokeAction(
      workspaceId: 'w',
      channelId: 'c',
      messageId: 'm',
      actionId: 'confirm',
    );
    expect(api.path, '/api/v1/workspaces/w/channels/c/messages/m/actions');
    expect(api.body, {'action_id': 'confirm'});
    expect(result.duplicate, true);
    expect(result.interactionId, 'i');
  });
  test('Biểu mẫu mã hóa định danh và giữ kiểu giá trị', () async {
    final api = _Transport({
      'submission': {
        'submission_id': 's',
        'form_id': 'f/x',
        'submitted_at': '2026-11-10T00:00:00Z',
      },
    });
    final result = await RichMessageRemoteDataSource(api).submitForm(
      workspaceId: 'w',
      channelId: 'c',
      messageId: 'm',
      formId: 'f/x',
      values: {'count': 2, 'accepted': true},
    );
    expect(
      api.path,
      '/api/v1/workspaces/w/channels/c/messages/m/forms/f%2Fx/submissions',
    );
    expect(api.body, {
      'values': {'count': 2, 'accepted': true},
    });
    expect(result.submissionId, 's');
  });
  test('Khôi phục gửi phiên bản hiện tại để chống ghi đè', () async {
    final api = _Transport({
      'document': {
        'kind': 'notes',
        'version': 8,
        'content': {'text': 'Bản cũ'},
      },
    });
    final result = await CollaborationDocumentHistoryRemoteDataSource(api)
        .restoreVersion(
          workspaceId: 'w',
          channelId: 'c',
          kind: 'notes',
          version: 3,
          expectedVersion: 7,
        );
    expect(
      api.path,
      '/api/v1/workspaces/w/channels/c/collaboration/documents/notes/versions/3/restore',
    );
    expect(api.body, {'expected_version': 7});
    expect(result.version, 8);
  });
}

final class _Transport implements ApiTransport {
  _Transport(this.payload);
  final Map<String, Object?> payload;
  String? path;
  Object? body;
  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    body = data;
    return Response<T>(
      data: {'success': true, 'data': payload} as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
