import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/call_privacy/application/use_cases/call_privacy_use_cases.dart';
import 'package:webtui_chat/features/call_privacy/data/datasources/call_privacy_remote_data_source.dart';
import 'package:webtui_chat/features/call_privacy/data/repositories/call_privacy_repository_impl.dart';
import 'package:webtui_chat/features/call_privacy/domain/entities/call_privacy.dart';

void main() {
  test('đọc cài đặt đúng path và bóc envelope', () async {
    final transport = _RecordingApiTransport({
      'success': true,
      'data': {
        'call_privacy': {'who_can_call_me': 'contacts'},
      },
    });
    final value = await CallPrivacyRemoteDataSource(
      transport,
    ).load(workspaceId: 'ws 1');

    expect(value, WhoCanCallMe.contacts);
    expect(transport.calls, ['GET /api/v1/workspaces/ws%201/me/call-privacy']);
  });

  test('lưu cài đặt bằng PUT với giá trị API', () async {
    final transport = _RecordingApiTransport({
      'data': {
        'call_privacy': {'who_can_call_me': 'nobody'},
      },
    });
    final value = await CallPrivacyRemoteDataSource(
      transport,
    ).update(workspaceId: 'ws-1', value: WhoCanCallMe.nobody);

    expect(value, WhoCanCallMe.nobody);
    expect(transport.calls, ['PUT /api/v1/workspaces/ws-1/me/call-privacy']);
    expect(transport.bodies.single, {'who_can_call_me': 'nobody'});
  });

  test('giá trị lạ coi như mọi người', () {
    expect(
      WhoCanCallMe.fromApi(' WORKSPACE_MEMBERS '),
      WhoCanCallMe.workspaceMembers,
    );
    expect(WhoCanCallMe.fromApi('bạn thân'), WhoCanCallMe.everyone);
  });

  test('use case từ chối khi chưa có workspace', () async {
    final transport = _RecordingApiTransport(const {});
    final repository = CallPrivacyRepositoryImpl(
      CallPrivacyRemoteDataSource(transport),
    );
    final result = await UpdateCallPrivacyUseCase(
      repository,
    ).execute('  ', WhoCanCallMe.nobody);

    expect(result, isA<FailureResult<WhoCanCallMe>>());
    expect(transport.calls, isEmpty);
  });
}

final class _RecordingApiTransport implements ApiTransport {
  _RecordingApiTransport(this._response);

  final Object _response;
  final calls = <String>[];
  final bodies = <Object?>[];

  Response<T> _ok<T>(String path) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: _response as T,
  );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add('GET $path');
    return _ok<T>(path);
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add('PUT $path');
    bodies.add(data);
    return _ok<T>(path);
  }

  @override
  Future<Response<T>> post<T>(
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
