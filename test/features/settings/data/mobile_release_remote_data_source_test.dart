import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/settings/data/datasources/mobile_release_remote_data_source.dart';

void main() {
  test('parses raw latest manifest as recommended update', () async {
    final dataSource = MobileReleaseRemoteDataSource(
      _FakeApiTransport({
        'platform': 'android',
        'channel': 'stable',
        'current_version': '1.1.0',
        'version': '1.1.0',
        'download_url':
            'https://chat.vpsttt.com/downloads/files/android/stable/app-prod-release.apk',
        'checksum_sha256': 'abc',
      }),
    );

    final policy = await dataSource.loadPolicy(
      platform: 'android',
      channel: 'stable',
      currentVersion: '1.0.0',
    );

    expect(policy.currentVersion, '1.0.0');
    expect(policy.recommendedVersion, '1.1.0');
    expect(policy.recommendsUpdate, isTrue);
    expect(
      policy.downloadUrl,
      'https://chat.vpsttt.com/downloads/files/android/stable/app-prod-release.apk',
    );
  });
}

final class _FakeApiTransport implements ApiTransport {
  const _FakeApiTransport(this.payload);

  final Object? payload;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: payload as T,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }
}
