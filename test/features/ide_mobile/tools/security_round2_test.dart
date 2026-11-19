import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_pairing_service.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_step_up.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_service.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_device_key_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_pair_api.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_demo_models.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_pair_code.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_talk_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_demo_dialogs.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_devices_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ide_step_sheet.dart';

import '../support/fakes.dart';
import 'tools_env.dart';

const _me = 'd_abcdefgh';
const _creds = IdeDeviceCredentials(
  instanceId: '0b9a6f4e-1c2d-4e3f-8a5b-6c7d8e9f0a1b',
  chatUserId: 'u_1',
  deviceId: _me,
  seed: 'c2VlZA==',
);

/// Máy chủ chat giả: chỉ ghi lại lệnh gỡ máy.
final class _Transport implements ApiTransport {
  final deleted = <String>[];

  Response<T> _res<T>(String path, Object? data) => Response<T>(
    data: data as T,
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
  );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _res(path, {
    'data': {'pair_request_id': 'p_1'},
  });

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _res(path, {
    'data': {'status': 'ok', 'device_id': _me},
  });

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    deleted.add(path);
    return _res(path, {
      'data': {'removed': true},
    });
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
}

Future<void> _pumpHost(WidgetTester t, void Function(BuildContext) open) =>
    t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('mo'),
            ),
          ),
        ),
      ),
    );

void main() {
  test('đối tượng thao tác lấy từ tham số app gửi, theo thứ tự ưu tiên', () {
    expect(ideStepTarget({'name': 'srv-1', 'project': 'web'}), 'srv-1');
    expect(ideStepTarget({'device_id': 'd_x'}), 'd_x');
    expect(ideStepTarget({'project': ' web '}), 'web');
    expect(ideStepTarget({'name': 7}), '');
    expect(ideStepTarget(null), '');
  });

  test('lời tóm tắt IDE gửi: lọc ký tự đảo chiều, cắt 500 ký tự', () {
    final s = ideStepSummaryText(
      IdeStepSummary(summary: '\u202E${'a' * 1000}', op: 'servers.remove'),
    );
    expect(s.contains('\u202E'), isFalse);
    expect(s.startsWith('<U+202E>'), isTrue);
    expect(s.runes.length, 501);
    expect(s.endsWith('…'), isTrue);
  });

  testWidgets('hộp vân tay: lời dài cuộn được, có dòng đối tượng do app ghi', (
    t,
  ) async {
    await _pumpHost(
      t,
      (c) => showIdeStepSheet(
        c,
        IdeStepSummary(
          summary: 'Gỡ máy chủ an toàn\n' * 200,
          op: 'servers.remove',
          target: 'srv-1\u202E',
        ),
      ),
    );
    await t.tap(find.text('mo'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Đối tượng: srv-1<U+202E>'), findsOneWidget);
    expect(find.text('Thao tác: gỡ máy chủ'), findsOneWidget);
    // Nút Xác nhận vẫn trong màn hình dù lời tóm tắt rất dài.
    expect(find.text('Xác nhận').hitTestable(), findsOneWidget);
  });

  testWidgets('hộp mật khẩu DB bật chặn chụp màn hình, đóng thì tắt', (
    t,
  ) async {
    final calls = <Object?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('webtui/privacy'),
      (call) async {
        if (call.method == 'setSecureScreen') calls.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('webtui/privacy'),
        null,
      ),
    );
    await _pumpHost(
      t,
      (c) => showDbSecretDialog(
        c,
        IdeDbSecret(const IdeDbInfo(host: 'db'), 'mat-khau'),
      ),
    );
    await t.tap(find.text('mo'));
    await t.pumpAndSettle();
    expect(calls, [true]);
    await t.tap(find.byKey(const Key('ide_db_close')));
    await t.pumpAndSettle();
    expect(calls, [true, false]);
  });

  test('tin chat quá dài bị cắt', () {
    final m = IdeTalkMessage.tryParse({
      'id': 'm1',
      'role': 'assistant',
      'text': 'x' * (ideTalkMaxMessageChars + 50),
    })!;
    expect(m.text.length, ideTalkMaxMessageChars + 1);
  });

  test('link chia sẻ quá dài không được dùng', () async {
    final env = IdeRpcEnv(
      (op, a) => {
        'link': 'l' * (ideTalkMaxLinkChars + 1),
        'url': 'https://x/${'y' * ideTalkMaxLinkChars}',
      },
      ops: ['talk.share'],
      step: (_) async => 'chu-ky',
    );
    await env.up();
    final r = await IdeTalkService(env.rpc).share('a' * 32);
    expect(r.link, '');
    expect(r.url, isNull);
    await env.dispose();
  });

  testWidgets('gỡ máy này rồi rời màn khi đang chờ: vẫn xoá ghép trên máy', (
    t,
  ) async {
    final store = MemorySecureStore();
    final transport = _Transport();
    final pairing = IdePairingService(
      api: IdePairApi(transport),
      keys: IdeDeviceKeyStore(store),
      security: FakeIdeSecurity(),
      currentUserId: () async => 'u_1',
      serverScopeId: 'srv',
      pollEvery: Duration.zero,
      maxWait: const Duration(seconds: 2),
    );
    await t.runAsync(
      () async => pairing.pair(
        code: IdePairCode.tryParse(
          'webtui-ide-pair:v1:0b9a6f4e-1c2d-4e3f-8a5b-6c7d8e9f0a1b:ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        )!,
        deviceName: 'x',
      ),
    );
    expect(store.values, isNotEmpty);
    final env = await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => op == 'devices.revoke'
          ? ideFakeSilent
          : {
              'items': [
                {'device_id': _me, 'name': 'Máy tôi', 'current': true},
              ],
            },
      ops: {'devices.list', 'devices.revoke'},
      overrides: [
        idePairingServiceProvider.overrideWithValue(pairing),
        ideCredentialsProvider.overrideWith((ref) async => _creds),
      ],
    );
    await t.tap(find.byKey(const Key('ide_device_revoke_$_me')));
    await settleAll(t);
    await t.tap(find.text('Gỡ ghép'));
    await settle(t);
    final req = env.lastSocket!
        .sentOfType('op')
        .lastWhere((f) => f['op'] == 'devices.revoke')['req'];
    // Người dùng rời màn trước khi IDE trả lời.
    GoRouter.of(t.element(find.byType(IdeDevicesScreen))).go('/ide/jobs/x');
    for (var i = 0; i < 5; i++) {
      await settle(t);
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(IdeDevicesScreen), findsNothing);
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {'current': true},
    });
    await settle(t);
    await settle(t);
    expect(transport.deleted, ['/api/v1/ide/pair/devices/$_me']);
    expect(store.values, isEmpty);
  });
}
