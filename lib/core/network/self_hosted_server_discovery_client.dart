import 'package:dio/dio.dart';

import 'self_hosted_server_discovery.dart';
import 'self_hosted_server_uri.dart';

final class SelfHostedServerConnectionException implements Exception {
  const SelfHostedServerConnectionException();
}

final class SelfHostedServerDiscoveryClient {
  SelfHostedServerDiscoveryClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              followRedirects: true,
            ),
          );

  final Dio _dio;

  Future<SelfHostedServerDiscovery> discover(String rawDomain) async {
    final serverUri = parseSelfHostedServerUri(rawDomain);
    try {
      final response = await _dio.getUri<Object>(
        serverUri
            .resolve('/api/v1/discovery')
            .replace(queryParameters: {'domain': serverUri.host}),
      );
      if (response.statusCode != 200) {
        throw StateError('Server không trả discovery WebTUI Chat hợp lệ.');
      }
      return SelfHostedServerDiscovery.fromApiResponse(
        payload: response.data,
        requestedServer: serverUri,
      );
    } on DioException {
      throw const SelfHostedServerConnectionException();
    }
  }
}
