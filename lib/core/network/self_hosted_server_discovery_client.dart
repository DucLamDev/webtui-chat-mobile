import 'package:dio/dio.dart';

import 'self_hosted_server_discovery.dart';
import 'self_hosted_server_uri.dart';

final class SelfHostedServerConnectionException implements Exception {
  const SelfHostedServerConnectionException();
}

final class SelfHostedServerDiscoveryClient {
  SelfHostedServerDiscoveryClient({required String mobileVersion, Dio? dio})
    : _mobileVersion = mobileVersion,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              // Discovery establishes the trust boundary for every subsequent
              // request. Never let another host answer through a redirect.
              followRedirects: false,
            ),
          );

  final Dio _dio;
  final String _mobileVersion;

  Future<SelfHostedServerDiscovery> discover(String rawDomain) async {
    final serverUri = parseSelfHostedServerUri(rawDomain);
    try {
      final response = await _dio.getUri<Object>(
        serverUri
            .resolve('/api/v1/discovery')
            .replace(queryParameters: {'domain': serverUri.host}),
      );
      if (response.statusCode != 200) {
        throw StateError('Server không trả thông tin discovery hợp lệ.');
      }
      return SelfHostedServerDiscovery.fromApiResponse(
        payload: response.data,
        requestedServer: serverUri,
        mobileVersion: _mobileVersion,
      );
    } on DioException {
      throw const SelfHostedServerConnectionException();
    }
  }
}
