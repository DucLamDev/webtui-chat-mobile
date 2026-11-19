import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/auth/data/repositories/account_repository_impl.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';
import 'package:webtui_chat/features/auth/domain/repositories/device_identity_repository.dart';

void main() {
  test('sends an optional trimmed ownership successor', () async {
    final api = _RecordingApiTransport();
    final repository = AccountRepositoryImpl(api, _FakeDevice());

    final result = await repository.deleteAccount(
      confirmation: 'DELETE',
      reauthToken: 'reauth-token-1',
      ownershipSuccessorEmail: ' successor@example.com ',
    );

    expect(result.isSuccess, isTrue);
    expect(api.path, '/api/v1/users/me');
    expect(api.data, {
      'confirmation': 'DELETE',
      'ownership_successor_email': 'successor@example.com',
    });
    // Token xác thực lại đi cùng mã thiết bị đã dùng để lấy nó.
    expect(api.headers?['X-Reauth-Token'], 'reauth-token-1');
    expect(api.headers?['X-Device-ID'], 'device-1');
  });

  test('omits an empty ownership successor', () async {
    final api = _RecordingApiTransport();
    final repository = AccountRepositoryImpl(api, _FakeDevice());

    await repository.deleteAccount(
      confirmation: 'DELETE',
      reauthToken: 'reauth-token-1',
      ownershipSuccessorEmail: '   ',
    );

    expect(api.data, {'confirmation': 'DELETE'});
  });
}

final class _RecordingApiTransport implements ApiTransport {
  String? path;
  Object? data;
  Map<String, dynamic>? headers;

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    this.data = data;
    headers = options?.headers;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 204,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
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

final class _FakeDevice implements DeviceIdentityRepository {
  @override
  Future<DeviceIdentity> currentDevice() async => const DeviceIdentity(
    id: 'device-1',
    platform: 'android',
    displayName: 'Pixel',
  );
}
