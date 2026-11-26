import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/ide_web/data/ide_web_api.dart';
import 'package:webtui_chat/features/ide_web/data/webview_flutter_ide_view.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_failure.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_host_policy.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_launch.dart';

import 'support/fakes.dart';

final class _Transport implements ApiTransport {
  Object? response;
  DioException? error;
  bool hang = false;
  final calls = <(String, String, Object?)>[];

  Future<Response<T>> _do<T>(String method, String path, Object? data) async {
    calls.add((method, path, data));
    if (hang) await Completer<void>().future;
    if (error != null) throw error!;
    return Response<T>(
      data: response as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _do('POST', path, data);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _do('DELETE', path, data);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> put<T>(
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
}

DioException _bad(int status, [String? code]) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: status,
    data: code == null
        ? null
        : {
            'error': {'code': code, 'message': 'lỗi'},
          },
  ),
);

void main() {
  const request = IdeWebLaunchRequest(
    platform: 'android',
    appVersion: '1.66.0',
    codeChallenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
  );

  test('TC2: thân launch đúng mẫu, không có tên / email / quyền', () async {
    final transport = _Transport()
      ..response = {'data': fixture('app-launch-response-browser.json')};
    final result = await IdeWebApi(transport).launch(request);
    final (method, path, data) = transport.calls.single;
    expect(method, 'POST');
    expect(path, '/api/v1/integrations/vpsttt-ide/launch');
    expect(data, fixture('app-launch-request.json'));
    final launch = (result as Success<IdeWebLaunch>).value;
    expect(launch, isA<IdeWebBrowserLaunch>());
    launch as IdeWebBrowserLaunch;
    const state = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
    expect(launch.state, state);
    expect(launch.browserUrl.host, 'ide.example.net');
    expect(launch.browserUrl.path, '/appchat/auth/');
    expect(launch.browserUrl.queryParameters['flow'], state);
    expect(
      IdeWebHostPolicy(
        Uri.parse('https://ide.chat.example.com'),
        Uri.parse('https://ide.example.net'),
      ).isBrowserUrl(launch.browserUrl),
      isTrue,
    );
    expect('$launch', isNot(contains(state)));
  });

  test('mode webview và complete đọc đúng mẫu', () async {
    final transport = _Transport()
      ..response = {'data': fixture('app-launch-response-webview.json')};
    final api = IdeWebApi(transport);
    final launch =
        (await api.launch(request)).valueOrNull! as IdeWebDirectLaunch;
    expect(launch.entry.bridgeEnabled, isTrue);
    expect(launch.state, 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8');
    expect(launch.entry.expiresAt, DateTime.utc(2026, 11, 25, 8, 1));
    expect(launch.launchExpiresAt, DateTime.utc(2026, 11, 25, 8, 10));
    expect(
      IdeWebHostPolicy(
        Uri.parse('https://ide.chat.example.com'),
        Uri.parse('https://ide.example.net'),
      ).isEnterUrl(launch.entry.enterUrl),
      isTrue,
    );
    expect('$launch', isNot(contains(launch.state)));

    transport
      ..response = {'data': fixture('app-complete-response.json')}
      ..calls.clear();
    final body = fixture('app-complete-request.json');
    final entry = (await api.complete(
      launchId: 'a/b',
      code: body['code'] as String,
      state: body['state'] as String,
      codeVerifier: body['code_verifier'] as String,
    )).valueOrNull;
    expect(transport.calls.single.$2, endsWith('/launches/a%2Fb/complete'));
    expect(transport.calls.single.$3, body);
    expect(entry!.gateToken, 'token-cong');
    expect('$entry', isNot(contains('token-cong')));
  });

  test('TC3: mã mở nằm trong thân POST, không nằm trong URL', () {
    final entry = testEntry();
    final body = String.fromCharCodes(ideWebEnterBody(entry));
    expect(body, 'gate_token=token-cong&open_code=ma-mo');
    expect('${entry.enterUrl}', isNot(contains('ma-mo')));
    expect(entry.enterUrl.hasQuery, isFalse);
  });

  test('cancel và kết thúc phiên đúng đường', () async {
    final transport = _Transport();
    final api = IdeWebApi(transport);
    await api.cancel('l1');
    await api.endCurrentSession();
    expect(transport.calls.map((c) => '${c.$1} ${c.$2}'), [
      'POST /api/v1/integrations/vpsttt-ide/launches/l1/cancel',
      'DELETE /api/v1/integrations/vpsttt-ide/sessions/current',
    ]);
  });

  test('trả lời thiếu trường / mode lạ là lỗi, không lộ giá trị', () async {
    for (final data in [
      {'mode': 'other', 'launch_id': 'x'},
      {...fixture('app-launch-response-webview.json')}..remove('open_code'),
      {...fixture('app-launch-response-webview.json')}..remove('state'),
      {...fixture('app-launch-response-webview.json')}
        ..remove('launch_expires_at'),
      {
        ...fixture('app-launch-response-webview.json'),
        'launch_expires_at': 'mai',
      },
      // `Uri` tự gỡ `..`: chuỗi gốc phải bị chặn trước.
      {
        ...fixture('app-launch-response-browser.json'),
        'browser_url': 'https://ide.example.net/appchat/auth/../download/v',
      },
      {
        ...fixture('app-launch-response-browser.json'),
        'browser_url': 'https://ide.example.net/appchat/%2e%2e/auth/',
      },
      {...fixture('app-launch-response-browser.json'), 'state': 5},
      null,
    ]) {
      final result = await IdeWebApi(
        _Transport()..response = {'data': data},
      ).launch(request);
      expect(result.failureOrNull?.kind, FailureKind.decoding);
      expect('${result.failureOrNull?.cause}', isNot(contains('token-cong')));
      expect(
        ideWebFailureKindOf(result.failureOrNull!),
        IdeWebFailureKind.unavailable,
      );
    }
  });

  test('TC2/TC5: ánh xạ lỗi', () async {
    Future<IdeWebFailureKind> map(DioException error) async =>
        ideWebFailureKindOf(
          (await IdeWebApi(
            _Transport()..error = error,
          ).launch(request)).failureOrNull!,
        );
    const table = {
      'IDE_WEB_DISABLED': (403, IdeWebFailureKind.disabled),
      'IDE_WEB_NOT_ALLOWED': (403, IdeWebFailureKind.notAllowed),
      'IDE_WEB_UNAVAILABLE': (503, IdeWebFailureKind.unavailable),
      'IDE_WEB_LAUNCH_NOT_FOUND': (404, IdeWebFailureKind.expired),
      'IDE_WEB_LAUNCH_EXPIRED': (410, IdeWebFailureKind.expired),
      'IDE_WEB_STATE_MISMATCH': (400, IdeWebFailureKind.expired),
      'IDE_WEB_CODE_REJECTED': (400, IdeWebFailureKind.expired),
      'IDE_WEB_CODE_USED': (409, IdeWebFailureKind.expired),
      'IDE_WEB_RATE_LIMITED': (429, IdeWebFailureKind.rateLimited),
    };
    for (final entry in table.entries) {
      expect(
        await map(_bad(entry.value.$1, entry.key)),
        entry.value.$2,
        reason: entry.key,
      );
    }
    for (final status in [404, 500, 502, 503, 504]) {
      expect(
        await map(_bad(status)),
        IdeWebFailureKind.unavailable,
        reason: '$status',
      );
    }
    expect(await map(_bad(401)), IdeWebFailureKind.expired);
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.badCertificate,
      DioExceptionType.unknown,
    ]) {
      expect(
        await map(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: type,
          ),
        ),
        IdeWebFailureKind.unavailable,
        reason: '$type',
      );
    }
  });

  test('TC5: máy chủ treo quá hạn thì báo chưa kết nối được', () async {
    final result = await IdeWebApi(
      _Transport()..hang = true,
      timeout: const Duration(milliseconds: 10),
    ).launch(request);
    expect(result.failureOrNull?.kind, FailureKind.timeout);
  });

  test('trả lời của cổng', () {
    expect(ideWebFailureKindOfGate(401, null), IdeWebFailureKind.expired);
    expect(
      ideWebFailureKindOfGate(401, 'disabled'),
      IdeWebFailureKind.disabled,
    );
    expect(
      ideWebFailureKindOfGate(401, 'forbidden'),
      IdeWebFailureKind.notAllowed,
    );
    expect(ideWebFailureKindOfGate(502, null), IdeWebFailureKind.unavailable);
    expect(ideWebFailureKindOfGate(404, null), isNull);
  });
}
