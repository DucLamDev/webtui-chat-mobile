import 'package:dio/dio.dart';

final class WebTuiOpenApiClientBoundary {
  const WebTuiOpenApiClientBoundary(this._dio);

  final Dio _dio;

  Dio get dioForGeneratedClient => _dio;
}

abstract interface class GeneratedOpenApiClientFactory<TClient> {
  TClient create(Dio dio);
}
