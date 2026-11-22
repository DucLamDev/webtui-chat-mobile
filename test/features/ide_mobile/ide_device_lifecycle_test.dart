import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/platform/biometric_auth_service.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_access_controller.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_download_service.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_pairing_service.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_step_up.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_device_key_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_pair_api.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_security.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_errors.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/files/ide_files_ui.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ide_access_gate.dart';

import 'support/fakes.dart';

/// Chip bảo mật giả: khoá xác nhận đã mất hiệu lực (đổi sinh trắc học).
final class _InvalidatedKeySecurity implements IdeDeviceSecurity {
  final deleted = <String>[];

  @override
  Future<DeviceOwnerAuthResult> authenticateDeviceOwner(String reason) async =>
      DeviceOwnerAuthResult.ok;

  @override
  Future<String> createStepKey(String alias) async => 'c3RlcA==';

  @override
  Future<void> deleteStepKey(String alias) async => deleted.add(alias);

  @override
  Future<String> signWithStepKey({
    required String alias,
    required List<int> data,
    required String reason,
  }) => throw const StepKeyException('key_invalid');

  @override
  Future<int?> uptimeMs() async => 0;
}

/// Transport giả chỉ ghi các lệnh gỡ máy.
final class _Transport implements ApiTransport {
  final deleted = <String>[];

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    deleted.add(path);
    return Response<T>(requestOptions: RequestOptions(path: path));
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
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

const _creds = IdeDeviceCredentials(
  instanceId: 'i_1',
  chatUserId: 'u_1',
  deviceId: 'd_abcdefgh',
  seed: 'c2VlZA==',
  serverScope: 'srv',
  stepAlias: 'webtui-ide-step-i_1-0011223344556677',
);

const _request = IdeStepRequest(
  stream: 's_1',
  req: 'r_1',
  challenge: 'Y2g=',
  summary: 'Chạy deploy',
  op: 'deploy.run',
  args: {'env': 'prod'},
);

void main() {
  group('khoá xác nhận mất hiệu lực (đổi sinh trắc học)', () {
    test('kênh native trả key_invalid giữ đúng mã lỗi', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('webtui/biometric');
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'key_invalid');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await expectLater(
        const BiometricAuthService().signWithStepKey(
          alias: 'a',
          data: const [1],
          reason: 'r',
        ),
        throwsA(
          isA<StepKeyException>().having((e) => e.code, 'code', 'key_invalid'),
        ),
      );
    });

    test('IdeStepUp báo lỗi riêng và gọi dọn bản gắn', () async {
      var cleaned = 0;
      final up = IdeStepUp(
        security: _InvalidatedKeySecurity(),
        present: (_) async => true,
        alias: () => _creds.stepKeyAlias,
        onKeyInvalidated: () async => cleaned++,
      );
      await expectLater(
        up.confirm(_request),
        throwsA(
          isA<IdeStepKeyInvalidated>().having(
            (e) => e.message,
            'message',
            'Sinh trắc học trên máy đã thay đổi. Cần gắn lại máy với IDE.',
          ),
        ),
      );
      expect(cleaned, 1);
      expect(
        ideFilesErrorText(const IdeStepKeyInvalidated()),
        'Sinh trắc học trên máy đã thay đổi. Cần gắn lại máy với IDE.',
      );
    });

    test('provider: xoá bản gắn + khoá, báo cần gắn lại', () async {
      final store = MemorySecureStore();
      final keys = IdeDeviceKeyStore(store);
      await keys.save(_creds);
      final security = _InvalidatedKeySecurity();
      final transport = _Transport();
      final pairing = IdePairingService(
        api: IdePairApi(transport),
        keys: keys,
        security: security,
        currentUserId: () async => 'u_1',
        serverScopeId: 'srv',
      );
      final c = ProviderContainer(
        overrides: [
          ideDeviceSecurityProvider.overrideWithValue(security),
          idePairingServiceProvider.overrideWithValue(pairing),
          ideCredentialsProvider.overrideWith((ref) async => _creds),
        ],
      );
      addTearDown(c.dispose);
      await c.read(ideCredentialsProvider.future);
      c.read(ideStepPresenterProvider.notifier).state = (_) async => true;
      c.read(ideCapabilitiesProvider.notifier).state = const IdeReady(
        ops: {'deploy.run'},
      );

      await expectLater(
        c.read(ideStepUpProvider).confirm(_request),
        throwsA(isA<IdeStepKeyInvalidated>()),
      );
      expect(store.values[SecureStoreKey.ideDevice], isNull);
      expect(security.deleted, [_creds.stepKeyAlias]);
      expect(transport.deleted, ['/api/v1/ide/pair/devices/d_abcdefgh']);
      expect(
        c.read(ideRepairNoticeProvider),
        'Sinh trắc học trên máy đã thay đổi. Cần gắn lại máy với IDE.',
      );
      expect(c.read(ideCapabilitiesProvider), isNull);
    });
  });

  group('đổi tài khoản: xoá hẳn bản gắn của người cũ', () {
    IdePairingService service(MemorySecureStore store, FakeIdeSecurity s) =>
        IdePairingService(
          api: IdePairApi(_Transport()),
          keys: IdeDeviceKeyStore(store),
          security: s,
          currentUserId: () async => 'u_2',
          serverScopeId: 'srv',
        );

    test('người khác đăng nhập: kho trống, khoá xác nhận bị xoá', () async {
      final store = MemorySecureStore();
      final security = FakeIdeSecurity();
      await IdeDeviceKeyStore(store).save(_creds);
      expect(await service(store, security).loadCurrent('u_2'), isNull);
      expect(store.values, isEmpty);
      expect(security.deleted, [_creds.stepKeyAlias]);
      // Người cũ đăng nhập lại cũng không còn bản gắn: phải gắn lại.
      expect(
        await IdeDeviceKeyStore(
          store,
        ).load(chatUserId: 'u_1', serverScope: 'srv'),
        isNull,
      );
    });

    test('cùng người, máy chủ khác: cũng xoá', () async {
      final store = MemorySecureStore();
      final security = FakeIdeSecurity();
      await IdeDeviceKeyStore(store).save(_creds);
      final other = IdePairingService(
        api: IdePairApi(_Transport()),
        keys: IdeDeviceKeyStore(store),
        security: security,
        currentUserId: () async => 'u_1',
        serverScopeId: 'srv-khac',
      );
      expect(await other.loadCurrent('u_1'), isNull);
      expect(store.values, isEmpty);
    });

    test('đúng người, đúng máy chủ: giữ nguyên', () async {
      final store = MemorySecureStore();
      final security = FakeIdeSecurity();
      await IdeDeviceKeyStore(store).save(_creds);
      final same = IdePairingService(
        api: IdePairApi(_Transport()),
        keys: IdeDeviceKeyStore(store),
        security: security,
        currentUserId: () async => 'u_1',
        serverScopeId: 'srv',
      );
      expect((await same.loadCurrent('u_1'))?.deviceId, 'd_abcdefgh');
      expect(security.deleted, isEmpty);
    });
  });

  group('xoá nội dung IDE khi ở nền quá 15 phút', () {
    test(
      'quá 15 phút: xoá; 5-15 phút: chỉ hỏi lại; dưới 5 phút: giữ',
      () async {
        var now = DateTime(2026, 11, 22, 9);
        final security = FakeIdeSecurity();
        var wipes = 0;
        final c = IdeAccessController(
          security,
          now: () => now,
          onWipe: () => wipes++,
        );
        Future<bool> away(Duration d) {
          c.onBackground();
          now = now.add(d);
          security.uptime = (security.uptime ?? 0) + d.inMilliseconds;
          return c.onForeground();
        }

        await c.ensureUnlocked('r');
        expect(await away(const Duration(minutes: 4)), isTrue);
        expect(wipes, 0);

        expect(await away(const Duration(minutes: 15)), isFalse);
        expect(wipes, 0, reason: 'đúng 15 phút chưa phải "hơn 15 phút"');

        await c.ensureUnlocked('r');
        expect(await away(const Duration(minutes: 15, seconds: 1)), isFalse);
        expect(wipes, 1);
        expect(c.unlocked, isFalse);
        await c.ensureUnlocked('r');
        expect(security.authCalls, 3);
      },
    );

    test(
      'đồng hồ máy chỉ lùi giờ hệ thống vẫn xoá theo đồng hồ native',
      () async {
        var now = DateTime(2026, 11, 22, 9);
        final security = FakeIdeSecurity();
        var wipes = 0;
        final c = IdeAccessController(
          security,
          now: () => now,
          onWipe: () => wipes++,
        );
        await c.ensureUnlocked('r');
        c.onBackground();
        now = now.add(const Duration(minutes: 1));
        security.uptime = 20 * 60 * 1000;
        expect(await c.onForeground(), isFalse);
        expect(wipes, 1);
      },
    );

    test('provider: xoá thì dựng lại trạng thái IDE', () async {
      final security = FakeIdeSecurity();
      final c = ProviderContainer(
        overrides: [
          authAccessTokenProvider.overrideWith((ref) async => 'tok'),
          ideDeviceSecurityProvider.overrideWithValue(security),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authAccessTokenProvider.future);
      final access = c.read(ideAccessControllerProvider);
      await access.ensureUnlocked('r');
      c.read(ideCapabilitiesProvider.notifier).state = const IdeReady(
        ops: {'ai.sessions'},
      );
      access.onBackground();
      security.uptime = 16 * 60 * 1000;
      expect(await access.onForeground(), isFalse);
      expect(c.read(ideMemoryEpochProvider), 1);
      expect(c.read(ideCapabilitiesProvider), isNull);
    });

    testWidgets('cổng IDE dựng lại nội dung khi bộ nhớ bị xoá', (tester) async {
      var builds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ideDeviceSecurityProvider.overrideWithValue(FakeIdeSecurity()),
            ideServerStatusProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: IdeAccessGate(child: _CountInit(onInit: () => builds++)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('nội dung'), findsOneWidget);
      expect(builds, 1);
      final c = ProviderScope.containerOf(
        tester.element(find.text('nội dung')),
      );
      c.read(ideMemoryEpochProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(builds, 2);
    });
  });

  group('tệp tải từ IDE: chưa lưu ra ngoài app, xoá tệp tạm', () {
    test('mặc định không cho lưu ra ngoài app', () {
      expect(ideSaveToDeviceEnabled, isFalse);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(ideSaveToDeviceProvider), isFalse);
    });

    test('save không gọi bộ lưu, discard xoá thư mục tạm', () async {
      final root = await Directory.systemTemp.createTemp('ide-test-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final dir = await root.createTemp('ide-dl-');
      final file = File('${dir.path}/a.pdf')..writeAsStringSync('x');
      final saver = _RecordingSaver();
      final connection = IdeConnection(
        openChannel: () => throw UnimplementedError(),
      );
      final rpc = IdeRpcClient(connection);
      addTearDown(() async {
        rpc.dispose();
        await connection.dispose();
      });
      final service = IdeDownloadService(
        rpc,
        saver: saver,
        tempDir: () async => root,
      );
      final f = IdeDownloadedFile(
        file: file,
        name: 'a.pdf',
        mime: 'application/pdf',
        size: 1,
      );
      expect(
        await service.save(f),
        'Chưa lưu được tệp IDE ra ngoài app trên điện thoại.',
      );
      expect(saver.calls, 0);
      await service.discard(f);
      expect(dir.existsSync(), isFalse);
    });
  });
}

class _CountInit extends StatefulWidget {
  const _CountInit({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_CountInit> createState() => _CountInitState();
}

class _CountInitState extends State<_CountInit> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('nội dung');
}

final class _RecordingSaver implements IdeFileSaver {
  int calls = 0;

  @override
  Future<String?> save(
    File file,
    String name,
    String mime, {
    Future<bool> Function()? confirmOpen,
  }) async {
    calls++;
    return null;
  }
}
