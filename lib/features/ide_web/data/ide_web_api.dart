import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/result/result.dart';
import '../../../core/result/result_guard.dart';
import '../../../l10n/app_strings.dart';
import '../domain/ide_web_host_policy.dart';
import '../domain/ide_web_launch.dart';
import '../domain/ide_web_ports.dart';

/// API mở VPSTTT IDE của máy chủ chat. Điện thoại không nói thẳng với cổng IDE.
final class IdeWebApi implements IdeWebRepository {
  const IdeWebApi(this._api, {this.timeout = ideWebNetworkTimeout});

  final ApiTransport _api;
  final Duration timeout;

  static const _base = '/api/v1/integrations/vpsttt-ide';

  Options get _options =>
      Options(sendTimeout: timeout, receiveTimeout: timeout);

  Future<Result<T>> _guard<T>(Future<T> Function() body) =>
      guardResult(() async {
        try {
          return await body().timeout(timeout);
        } on TimeoutException {
          throw FailureException(
            Failure(
              kind: FailureKind.timeout,
              message: tr(
                'Kết nối quá hạn. Vui lòng thử lại.',
                'Connection timed out. Please try again.',
              ),
            ),
          );
        }
      });

  @override
  Future<Result<IdeWebLaunch>> launch(IdeWebLaunchRequest request) =>
      _guard(() async {
        final response = await _api.post<Object?>(
          '$_base/launch',
          data: request.toJson(),
          options: _options,
        );
        final data = jsonMap(envelopeData(response.data));
        final launchId = _text(data, 'launch_id');
        switch (data['mode']) {
          case 'browser':
            return IdeWebBrowserLaunch(
              launchId: launchId,
              state: _text(data, 'state'),
              browserUrl: _safeUri(data, 'browser_url'),
              expiresAt: _time(data),
            );
          case 'webview':
            return IdeWebDirectLaunch(
              launchId: launchId,
              state: _text(data, 'state'),
              entry: _entry(data),
              launchExpiresAt: _time(data, 'launch_expires_at'),
            );
          default:
            throw const FormatException('mode');
        }
      });

  @override
  Future<Result<IdeWebEntry>> complete({
    required String launchId,
    required String code,
    required String state,
    required String codeVerifier,
  }) => _guard(() async {
    final response = await _api.post<Object?>(
      '$_base/launches/${Uri.encodeComponent(launchId)}/complete',
      data: {'code': code, 'state': state, 'code_verifier': codeVerifier},
      options: _options,
    );
    return _entry(jsonMap(envelopeData(response.data)));
  });

  @override
  Future<Result<void>> cancel(String launchId) => _guard(() async {
    await _api.post<Object?>(
      '$_base/launches/${Uri.encodeComponent(launchId)}/cancel',
      options: _options,
    );
  });

  @override
  Future<Result<void>> endCurrentSession() => _guard(() async {
    await _api.delete<Object?>('$_base/sessions/current', options: _options);
  });

  static IdeWebEntry _entry(JsonMap data) => IdeWebEntry(
    enterUrl: _uri(data, 'enter_url'),
    gateToken: _text(data, 'gate_token'),
    openCode: _text(data, 'open_code'),
    expiresAt: _time(data),
    bridgeEnabled: data['bridge_enabled'] == true,
  );

  // Lỗi đọc chỉ nêu tên trường, không kèm giá trị (có mã một lần).
  static String _text(JsonMap data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) throw FormatException(key);
    return value;
  }

  static Uri _uri(JsonMap data, String key) =>
      Uri.tryParse(_text(data, key)) ?? (throw FormatException(key));

  /// `Uri` tự gỡ `..` / `.`: kiểm đường dẫn trên chuỗi gốc trước.
  static Uri _safeUri(JsonMap data, String key) =>
      ideWebRawPathIsSafe(_text(data, key))
      ? _uri(data, key)
      : throw FormatException(key);

  static DateTime _time(JsonMap data, [String key = 'expires_at']) =>
      DateTime.tryParse(_text(data, key)) ?? (throw FormatException(key));
}
