import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/privacy/background_privacy.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_access.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_pairing_service.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_device_key_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_pair_api.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_pair_code.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_server_access.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ide_access_gate.dart';

import 'support/fakes.dart';

/// Transport giả: GET trả [getBody] hoặc ném lỗi [status]; POST luôn lỗi
/// [status] với [errorBody].
final class _Transport implements ApiTransport {
  _Transport({this.getBody, this.status = 200, this.errorBody});

  final Object? getBody;
  final int status;
  final Object? errorBody;
  final paths = <String>[];

  Never _fail(String path) => throw DioException(
    requestOptions: RequestOptions(path: path),
    response: Response(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: errorBody,
    ),
    type: DioExceptionType.badResponse,
  );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    paths.add(path);
    if (status != 200) _fail(path);
    return Response<T>(
      data: getBody as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    paths.add(path);
    _fail(path);
  }

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

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}

Map<String, Object?> _denied(String? reason) => {
  'error': {
    'code': 'IDE_ACCESS_DENIED',
    'message': 'denied',
    'details': {'reason': ?reason},
  },
};

SelfHostedServerDiscovery _discovery() => SelfHostedServerDiscovery(
  instanceId: '11111111-1111-4111-8111-111111111111',
  discoveryVersion: '1',
  domain: SelfHostedServerDiscovery.vpstttInternalHost,
  name: 'Máy chủ thử',
  apiBaseUri: Uri.parse(
    'https://${SelfHostedServerDiscovery.vpstttInternalHost}',
  ),
  wsBaseUri: Uri.parse(
    'wss://${SelfHostedServerDiscovery.vpstttInternalHost}/ws',
  ),
  registrationMode: 'closed',
  appVersion: '1.0.0',
  apiContractVersion: 1,
  serverVersion: '1.0.0',
  minimumSupportedMobileVersion: '1.0.0',
  capabilities: const SelfHostedCapabilities(ide: true),
  zoneKind: SelfHostedServerDiscovery.vpstttInternalZoneKind,
);

void main() {
  group('tab IDE chỉ trên Android và iOS', () {
    test('theo TargetPlatform', () {
      expect(ideSupportedPlatform(TargetPlatform.android), isTrue);
      expect(ideSupportedPlatform(TargetPlatform.iOS), isTrue);
      for (final p in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(ideSupportedPlatform(p), isFalse, reason: '$p');
      }
    });

    test('ideEnabledProvider tắt trên nền tảng khác dù máy chủ bật', () {
      bool enabledOn(TargetPlatform platform) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final c = ProviderContainer(
            overrides: [
              activeServerDiscoveryProvider.overrideWithValue(_discovery()),
            ],
          );
          addTearDown(c.dispose);
          return c.read(ideEnabledProvider);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }

      expect(enabledOn(TargetPlatform.android), isTrue);
      expect(enabledOn(TargetPlatform.iOS), isTrue);
      expect(enabledOn(TargetPlatform.linux), isFalse);
      expect(enabledOn(TargetPlatform.windows), isFalse);
      expect(enabledOn(TargetPlatform.macOS), isFalse);
    });
  });

  group('GET /ide/status', () {
    test('máy chủ cũ (chỉ connected): không khoá', () {
      final s = IdeServerStatus.fromJson({'connected': true});
      expect(s.enabled, isNull);
      expect(s.access, isNull);
      expect(s.deniedReason, isNull);
    });

    test('access.allowed=false: khoá theo reason', () {
      final s = IdeServerStatus.fromJson({
        'connected': true,
        'enabled': true,
        'access': {'allowed': false, 'reason': 'mfa_required'},
      });
      expect(s.deniedReason, 'mfa_required');
      expect(
        IdeServerStatus.fromJson({
          'access': {'allowed': false},
        }).deniedReason,
        'unavailable',
      );
      expect(
        IdeServerStatus.fromJson({
          'enabled': true,
          'access': {'allowed': true, 'reason': ''},
        }).deniedReason,
        isNull,
      );
    });

    test('enabled=false: IDE tạm tắt; trường sai kiểu coi như thiếu', () {
      expect(
        IdeServerStatus.fromJson({'enabled': false}).deniedReason,
        'disabled',
      );
      expect(
        IdeServerStatus.fromJson({
          'enabled': 'no',
          'access': {'allowed': 'no'},
        }).deniedReason,
        isNull,
      );
    });

    test('lời giải thích theo từng lý do', () {
      expect(
        ideAccessDeniedText('disabled'),
        'IDE đang tạm tắt trên máy chủ này.',
      );
      expect(
        ideAccessDeniedText('mfa_required'),
        'Bật xác thực 2 lớp cho tài khoản để dùng IDE trên điện thoại.',
      );
      expect(
        ideAccessDeniedText('mfa_stale'),
        'Đăng nhập lại, có bước xác thực 2 lớp, để tiếp tục dùng IDE.',
      );
      expect(
        ideAccessDeniedText('email_unverified'),
        'Xác minh email của tài khoản để dùng IDE.',
      );
      for (final r in ['unavailable', 'something_new', '']) {
        expect(
          ideAccessDeniedText(r),
          'Chưa kiểm được quyền dùng IDE. Thử lại sau.',
        );
      }
    });

    test('IdePairApi.status đọc envelope', () async {
      final api = IdePairApi(
        _Transport(
          getBody: {
            'data': {
              'connected': false,
              'enabled': true,
              'access': {'allowed': false, 'reason': 'email_unverified'},
            },
          },
        ),
      );
      final s = await api.status();
      expect(s.connected, isFalse);
      expect(s.deniedReason, 'email_unverified');
    });
  });

  group('403 IDE_ACCESS_DENIED khi gắn máy', () {
    final code = IdePairCode.tryParse(
      'webtui-ide-pair:v1:0b9a6f4e-1c2d-4e3f-8a5b-6c7d8e9f0a1b:'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    )!;

    test('API báo accessDenied kèm details.reason', () async {
      final api = IdePairApi(
        _Transport(status: 403, errorBody: _denied('mfa_stale')),
      );
      await expectLater(
        api.requestPair(
          code: 'X',
          pubkey: 'p',
          stepPubkey: 's',
          deviceName: 'd',
        ),
        throwsA(
          isA<IdePairException>()
              .having((e) => e.kind, 'kind', IdePairErrorKind.accessDenied)
              .having((e) => e.accessReason, 'reason', 'mfa_stale'),
        ),
      );
      // 403 khác mã: không phải từ chối quyền IDE.
      await expectLater(
        IdePairApi(
          _Transport(
            status: 403,
            errorBody: {
              'error': {'code': 'FORBIDDEN'},
            },
          ),
        ).requestPair(code: 'X', pubkey: 'p', stepPubkey: 's', deviceName: 'd'),
        throwsA(
          isA<IdePairException>().having(
            (e) => e.kind,
            'kind',
            IdePairErrorKind.other,
          ),
        ),
      );
    });

    test('dịch vụ gắn máy trả accessDenied và báo lý do', () async {
      final reasons = <String>[];
      final store = MemorySecureStore();
      final security = FakeIdeSecurity();
      final service = IdePairingService(
        api: IdePairApi(_Transport(status: 403, errorBody: _denied(null))),
        keys: IdeDeviceKeyStore(store),
        security: security,
        currentUserId: () async => 'u_1',
        serverScopeId: 'srv',
        onAccessDenied: reasons.add,
        pollEvery: Duration.zero,
      );
      final out = await service.pair(code: code, deviceName: 'Máy');
      expect(out, IdePairOutcome.accessDenied);
      expect(reasons, ['unavailable']);
      // Khoá vừa tạo bị dọn, không lưu bản gắn.
      expect(security.deleted, security.created);
      expect(store.values, isEmpty);
    });
  });

  group('màn khoá IDE theo quyền máy chủ', () {
    Future<void> pump(
      WidgetTester tester,
      IdeServerStatus? status, {
      FakeIdeSecurity? security,
    }) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('trang chủ')),
          GoRoute(
            path: '/ide',
            builder: (_, _) => const IdeAccessGate(child: Text('trong IDE')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ideDeviceSecurityProvider.overrideWithValue(
              security ?? FakeIdeSecurity(),
            ),
            ideServerStatusProvider.overrideWith((ref) async => status),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      router.go('/ide');
      await tester.pumpAndSettle();
    }

    testWidgets('máy chủ cũ / không đọc được: giữ hành vi cũ', (tester) async {
      await pump(tester, const IdeServerStatus(connected: true));
      expect(find.text('trong IDE'), findsOneWidget);
      await pump(tester, null);
      expect(find.text('trong IDE'), findsOneWidget);
    });

    testWidgets('access.allowed=false: màn khoá, không dựng nội dung IDE', (
      tester,
    ) async {
      final security = FakeIdeSecurity();
      await pump(
        tester,
        const IdeServerStatus(
          connected: true,
          enabled: true,
          access: IdeServerAccess(allowed: false, reason: 'mfa_required'),
        ),
        security: security,
      );
      expect(find.byKey(const Key('ide_access_locked')), findsOneWidget);
      expect(
        find.text(
          'Bật xác thực 2 lớp cho tài khoản để dùng IDE trên điện thoại.',
        ),
        findsOneWidget,
      );
      expect(find.text('trong IDE'), findsNothing);
      // Bị chặn thì không hỏi vân tay.
      expect(security.authCalls, 0);
    });

    testWidgets('IDE tạm tắt trên máy chủ', (tester) async {
      await pump(
        tester,
        const IdeServerStatus(connected: false, enabled: false),
      );
      expect(find.text('IDE đang tạm tắt trên máy chủ này.'), findsOneWidget);
      expect(find.text('trong IDE'), findsNothing);
    });

    testWidgets(
      'nhận 403 IDE_ACCESS_DENIED khi đang mở: chuyển sang màn khoá',
      (tester) async {
        await pump(tester, const IdeServerStatus(connected: true));
        expect(find.text('trong IDE'), findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.text('trong IDE')),
        );
        container.read(ideAccessDeniedReasonProvider.notifier).state =
            'email_unverified';
        await tester.pumpAndSettle();
        expect(find.text('trong IDE'), findsNothing);
        expect(
          find.text('Xác minh email của tài khoản để dùng IDE.'),
          findsOneWidget,
        );
      },
    );
  });

  group('trạm tắt IDE (lý do đóng disabled)', () {
    test('stream rpc bị đóng disabled: không nối lại, báo disabled', () async {
      final sockets = <FakeIdeSocket>[];
      final connection = IdeConnection(
        openChannel: () {
          final socket = FakeIdeSocket(ops: const ['ai.sessions']);
          sockets.add(socket);
          return IdeChannel.connect(
            socket: socket,
            signAuth: fakeSignAuth,
            pingEvery: const Duration(hours: 1),
          );
        },
        backoff: const [Duration(milliseconds: 5)],
      );
      connection.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connection.status.phase, IdeLinkPhase.ready);
      sockets.single.emit({'type': 'ide_closed', 'reason': 'disabled'});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sockets, hasLength(1));
      expect(connection.status.phase, IdeLinkPhase.idle);
      expect(connection.status.reason, 'disabled');
      await connection.dispose();
    });

    test('bắt tay bị từ chối disabled là lỗi dừng hẳn', () {
      expect(const IdeHandshakeException('disabled').fatal, isTrue);
      expect(const IdeChannelClose('disabled').disabled, isTrue);
    });

    test(
      '503 IDE_ACCESS_DENIED ở GET /ide/status: khoá, lý do unavailable',
      () async {
        final s = await IdePairApi(
          _Transport(status: 503, errorBody: _denied('unavailable')),
        ).status();
        expect(s.deniedReason, 'unavailable');
        // 429 ở GET /ide/status: không khoá (ném lỗi, provider giữ hành vi cũ).
        await expectLater(
          IdePairApi(
            _Transport(
              status: 429,
              errorBody: {
                'error': {'code': 'RATE_LIMITED'},
              },
            ),
          ).status(),
          throwsA(isA<IdePairException>()),
        );
      },
    );
  });

  group('kết nối IDE gặp not_allowed', () {
    test('không tự nối lại, trạng thái idle kèm lý do', () async {
      var opens = 0;
      final connection = IdeConnection(
        openChannel: () async {
          opens++;
          throw const IdeHandshakeException(ideNotAllowedReason);
        },
        backoff: const [Duration(milliseconds: 5)],
      );
      connection.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(opens, 1);
      expect(connection.status.phase, IdeLinkPhase.idle);
      expect(connection.status.reason, 'not_allowed');
      await connection.dispose();
    });
  });

  group('chặn chụp / quay màn hình ở mọi màn IDE', () {
    testWidgets('vào màn IDE thì giữ, màn con chồng lên vẫn giữ, rời thì nhả', (
      tester,
    ) async {
      BackgroundPrivacyController.resetSecureHolds();
      addTearDown(BackgroundPrivacyController.resetSecureHolds);
      final calls = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('webtui/privacy'),
        (call) async {
          if (call.method == 'setSecureScreen') calls.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('webtui/privacy'),
          null,
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('trang chủ')),
          GoRoute(
            path: '/ide',
            builder: (_, _) => const IdeAccessGate(child: Text('màn gốc')),
          ),
          GoRoute(
            path: '/ide/con',
            builder: (_, _) => const IdeAccessGate(child: Text('màn con')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ideDeviceSecurityProvider.overrideWithValue(FakeIdeSecurity()),
            ideServerStatusProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      router.go('/ide');
      await tester.pumpAndSettle();
      expect(calls, [true]);
      expect(BackgroundPrivacyController.secureHolds, 1);

      unawaited(router.push('/ide/con'));
      await tester.pumpAndSettle();
      expect(find.text('màn con'), findsOneWidget);
      expect(BackgroundPrivacyController.secureHolds, 2);

      router.pop();
      await tester.pumpAndSettle();
      expect(calls, [true]);
      expect(BackgroundPrivacyController.secureHolds, 1);

      router.go('/');
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      expect(BackgroundPrivacyController.secureHolds, 0);
    });
  });
}
