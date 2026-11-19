import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_pairing_service.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_device_key_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_pair_api.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_pair_code.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_devices_screen.dart';

import '../support/fakes.dart';
import 'tools_env.dart';

const _ops = {'devices.list', 'devices.revoke'};
const _me = 'd_abcdefgh';
const _other = 'd_otherphone';
const _creds = IdeDeviceCredentials(
  instanceId: '0b9a6f4e-1c2d-4e3f-8a5b-6c7d8e9f0a1b',
  chatUserId: 'u_1',
  deviceId: _me,
  seed: 'c2VlZA==',
);

/// Máy chủ chat giả đủ cho gắn máy + gỡ máy.
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

Map<String, Object?> _list() => {
  'items': [
    {
      'device_id': _me,
      'name': 'Máy tôi',
      'created_at': 1700000000,
      'current': true,
    },
    {'device_id': _other, 'name': 'iPad cũ', 'last_used': 1700000100},
  ],
};

void main() {
  testWidgets('tải được, đánh dấu máy này', (t) async {
    await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => op == 'devices.list' ? _list() : {},
      ops: _ops,
    );
    expect(find.text('Máy này'), findsOneWidget);
    expect(find.byKey(const Key('ide_device_revoke_$_me')), findsOneWidget);
    expect(find.byKey(const Key('ide_device_revoke_$_other')), findsOneWidget);
  });

  testWidgets('rỗng / lỗi / forbidden', (t) async {
    await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => {'items': []},
      ops: _ops,
    );
    expect(find.text('Chưa có điện thoại nào'), findsOneWidget);
  });

  testWidgets('lỗi có nút thử lại', (t) async {
    await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => const IdeFakeError('internal'),
      ops: _ops,
    );
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('forbidden', (t) async {
    await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => const IdeFakeError('forbidden'),
      ops: _ops,
    );
    expect(find.text('Thử lại'), findsNothing);
    expect(find.byKey(const Key('ide_devices_list')), findsNothing);
  });

  testWidgets('không có devices.revoke thì ẩn nút thu hồi', (t) async {
    await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => op == 'devices.list' ? _list() : {},
      ops: {'devices.list'},
    );
    expect(find.byKey(const Key('ide_device_revoke_$_other')), findsNothing);
  });

  testWidgets('thu hồi máy khác là ★: hỏi lại rồi need_step', (t) async {
    var steps = 0;
    final env = await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => op == 'devices.revoke'
          ? ideFakeSilent
          : (op == 'devices.list' ? _list() : {}),
      ops: _ops,
      step: (r) async {
        steps++;
        expect(r.op, 'devices.revoke');
        return 'chu-ky';
      },
    );
    await t.tap(find.byKey(const Key('ide_device_revoke_$_other')));
    await settleAll(t);
    expect(sentOps(env, 'devices.revoke'), isEmpty);
    await t.tap(find.text('Thu hồi').last);
    await settle(t);
    expect(sentOps(env, 'devices.revoke').single, {'device_id': _other});
    final req = await emitNeedStep(t, env);
    expect(steps, 1);
    env.lastSocket!.emit({
      'type': 'result',
      'req': req,
      'ok': true,
      'data': {'current': false},
    });
    await settleAll(t);
  });

  testWidgets('thu hồi chính máy này: hỏi lại, rồi gỡ ghép trên máy', (
    t,
  ) async {
    final store = MemorySecureStore();
    final security = FakeIdeSecurity();
    final transport = _Transport();
    final pairing = IdePairingService(
      api: IdePairApi(transport),
      keys: IdeDeviceKeyStore(store),
      security: security,
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
          ? {'current': true}
          : (op == 'devices.list' ? _list() : {}),
      ops: _ops,
      overrides: [
        idePairingServiceProvider.overrideWithValue(pairing),
        ideCredentialsProvider.overrideWith((ref) async => _creds),
      ],
    );
    await t.tap(find.byKey(const Key('ide_device_revoke_$_me')));
    await settleAll(t);
    expect(find.text('Gỡ máy này?'), findsOneWidget);
    expect(sentOps(env, 'devices.revoke'), isEmpty);
    await t.tap(find.text('Gỡ ghép'));
    await settle(t);
    await settle(t);
    expect(sentOps(env, 'devices.revoke').single, {'device_id': _me});
    expect(transport.deleted, ['/api/v1/ide/pair/devices/$_me']);
    expect(store.values, isEmpty);
  });

  testWidgets('IDE báo current nhưng device_id khác: không xoá khoá cục bộ', (
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
    final env = await pumpTool(
      t,
      const IdeDevicesScreen(),
      (op, a) => op == 'devices.revoke'
          ? {'current': true}
          : (op == 'devices.list' ? _list() : {}),
      ops: _ops,
      overrides: [
        idePairingServiceProvider.overrideWithValue(pairing),
        ideCredentialsProvider.overrideWith((ref) async => _creds),
      ],
    );
    await t.tap(find.byKey(const Key('ide_device_revoke_$_other')));
    await settleAll(t);
    expect(find.text('Thu hồi máy này?'), findsOneWidget);
    await t.tap(find.text('Thu hồi').last);
    await settle(t);
    await settle(t);
    expect(sentOps(env, 'devices.revoke').single, {'device_id': _other});
    expect(transport.deleted, isEmpty);
    expect(store.values, isNotEmpty);
  });
}
