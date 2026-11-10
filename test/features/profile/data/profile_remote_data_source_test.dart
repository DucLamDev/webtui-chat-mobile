import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';

void main() {
  test(
    'đọc và sửa hồ sơ truyền workspace đang chọn, ngày giữ nguyên',
    () async {
      final api = _Api();
      var workspaceId = 'workspace-a';
      final remote = ProfileRemoteDataSource(
        api,
        loadWorkspaceId: () async => workspaceId,
      );
      final profile = await remote.me();
      expect(api.query, {'workspace_id': 'workspace-a'});
      expect(profile.work.title, 'Kỹ sư');
      expect(profile.work.location, 'Hà Nội');
      expect(profile.work.startDate, DateTime(2026, 2, 28));
      workspaceId = 'workspace-b';
      await remote.updateMe(const UpdateProfileCommand(title: 'Trưởng nhóm'));
      expect(api.query, {'workspace_id': 'workspace-b'});
      expect(api.data, {'title': 'Trưởng nhóm'});
    },
  );

  test('ngày không hợp lệ không tự nhảy sang tháng sau', () {
    final profile = userProfileFromMap({
      'profile': {'start_date': '2026-02-31'},
    });
    expect(profile.work.startDate, isNull);
  });
}

final class _Api implements ApiTransport {
  Map<String, dynamic>? query;
  Object? data;
  Response<T> response<T>(String path) => Response<T>(
    requestOptions: RequestOptions(path: path),
    data:
        {
              'data': {
                'id': 'user-1',
                'profile': {
                  'title': 'Kỹ sư',
                  'location': 'Hà Nội',
                  'start_date': '2026-02-28',
                },
              },
            }
            as T,
  );
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    query = queryParameters;
    return response(path);
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    query = queryParameters;
    this.data = data;
    return response(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
