import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_pairing_service.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_device_key_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_pair_api.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_pair_code.dart';

import 'support/fakes.dart';

const _uuid = '0b9a6f4e-1c2d-4e3f-8a5b-6c7d8e9f0a1b';
const _code = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'; // 26 ký tự A-Z

final class _PairTransport implements ApiTransport {
  _PairTransport(this.polls);

  /// Mỗi phần tử: thân JSON trả về, hoặc số = mã HTTP lỗi.
  final List<Object> polls;
  Map<String, Object?>? posted;
  int pollCount = 0;
  int postStatus = 200;

  Response<T> _res<T>(String path, Object? data, [int status = 200]) =>
      Response<T>(
        data: data as T,
        requestOptions: RequestOptions(path: path),
        statusCode: status,
      );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    posted = Map<String, Object?>.from(data! as Map);
    if (postStatus != 200) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: postStatus,
          data: {
            'error': {'code': postStatus == 503 ? 'IDE_OFFLINE' : 'X'},
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return _res(path, {
      'data': {'pair_request_id': 'p_1'},
    });
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final next = polls[pollCount < polls.length ? pollCount : polls.length - 1];
    pollCount++;
    if (next is int) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: next,
          data: {
            'error': {'code': 'NOT_FOUND'},
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return _res(path, {'data': next});
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

void main() {
  group('phân tích mã QR', () {
    test('đúng định dạng', () {
      final c = IdePairCode.tryParse(
        'webtui-ide-pair:v1:${_uuid.toUpperCase()}:$_code',
      );
      expect(c, isNotNull);
      expect(c!.instanceId, _uuid);
      expect(c.code, _code);
    });

    test('sai thì trả null', () {
      for (final bad in [
        '',
        'webtui-ide-pair:v1:$_uuid',
        'webtui-ide-pair:v2:$_uuid:$_code',
        'webtui-ide-pair:v1:$_uuid:${_code.substring(1)}',
        'webtui-ide-pair:v1:$_uuid:${_code.toLowerCase()}',
        'webtui-ide-pair:v1:$_uuid:ABCDEFGHIJKLMNOPQRSTUVWXY1',
        'webtui-ide-pair:v1:not-a-uuid:$_code',
        ' webtui-ide-pair:v1:$_uuid:$_code',
        'https://example.com/webtui-ide-pair:v1:$_uuid:$_code',
        'webtui-ide-pair:v1:$_uuid:$_code\nx',
      ]) {
        expect(IdePairCode.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('gắn máy với transport giả', () {
    late MemorySecureStore store;
    late FakeIdeSecurity security;
    final code = IdePairCode.tryParse('webtui-ide-pair:v1:$_uuid:$_code')!;

    IdePairingService service(_PairTransport t) => IdePairingService(
      api: IdePairApi(t),
      keys: IdeDeviceKeyStore(store),
      security: security,
      currentUserId: () async => 'u_1',
      serverScopeId: 'srv',
      pollEvery: Duration.zero,
      maxWait: const Duration(seconds: 2),
    );

    setUp(() {
      store = MemorySecureStore();
      security = FakeIdeSecurity();
    });

    test('thành công: gửi đúng thân, lưu khoá', () async {
      final t = _PairTransport([
        {'status': 'pending'},
        {'status': 'ok', 'device_id': 'd_abcdefgh'},
      ]);
      var waited = false;
      final out = await service(t).pair(
        code: code,
        deviceName: '  Máy của tôi  ',
        onWaiting: () => waited = true,
      );
      expect(out, IdePairOutcome.ok);
      expect(waited, isTrue);
      expect(t.posted!['code'], _code);
      expect(t.posted!['device_name'], 'Máy của tôi');
      expect(t.posted!['step_pubkey'], 'c3RlcC1wdWJrZXk=');
      expect((t.posted!['pubkey'] as String).length, 44); // 32 byte base64
      final saved = await IdeDeviceKeyStore(
        store,
      ).load(chatUserId: 'u_1', serverScope: 'srv');
      expect(saved!.deviceId, 'd_abcdefgh');
      final alias = security.created.single;
      expect(alias, matches(RegExp('^webtui-ide-step-$_uuid-[0-9a-f]{16}\$')));
      expect(saved.stepKeyAlias, alias);
      expect(security.deleted, isEmpty);
    });

    test(
      'gắn lại hỏng: giữ khoá + bản ghi đang dùng, xoá khoá vừa tạo',
      () async {
        await service(
          _PairTransport([
            {'status': 'ok', 'device_id': 'd_abcdefgh'},
          ]),
        ).pair(code: code, deviceName: 'x');
        final first = security.created.single;
        final out = await service(
          _PairTransport([
            {'status': 'rejected'},
          ]),
        ).pair(code: code, deviceName: 'x');
        expect(out, IdePairOutcome.rejected);
        final second = security.created.last;
        expect(second, isNot(first));
        expect(security.deleted, [second]);
        final saved = await IdeDeviceKeyStore(
          store,
        ).load(chatUserId: 'u_1', serverScope: 'srv');
        expect(saved!.stepKeyAlias, first);
      },
    );

    test('gắn lại thành công: xoá khoá của lần gắn cũ', () async {
      for (final id in ['d_abcdefgh', 'd_ijklmnop']) {
        await service(
          _PairTransport([
            {'status': 'ok', 'device_id': id},
          ]),
        ).pair(code: code, deviceName: 'x');
      }
      expect(security.created, hasLength(2));
      expect(security.deleted, [security.created.first]);
      final saved = await IdeDeviceKeyStore(
        store,
      ).load(chatUserId: 'u_1', serverScope: 'srv');
      expect(saved!.deviceId, 'd_ijklmnop');
      expect(saved.stepKeyAlias, security.created.last);
    });

    test('mã máy sai mẫu: không lưu, bỏ khoá vừa tạo', () async {
      for (final id in ['d_x', 'd_abc defgh', 'x_abcdefgh', 'd_${'a' * 65}']) {
        final out = await service(
          _PairTransport([
            {'status': 'ok', 'device_id': id},
          ]),
        ).pair(code: code, deviceName: 'x');
        expect(out, IdePairOutcome.failed, reason: id);
      }
      expect(store.values, isEmpty);
      expect(security.deleted, security.created);
    });

    test('đăng xuất / đổi người trong lúc chờ: không lưu khoá', () async {
      var token = 'tok-a';
      final s = IdePairingService(
        api: IdePairApi(
          _PairTransport([
            {'status': 'ok', 'device_id': 'd_abcdefgh'},
          ]),
        ),
        keys: IdeDeviceKeyStore(store),
        security: security,
        currentUserId: () async => 'u_1',
        serverScopeId: 'srv',
        sessionToken: () => token,
        pollEvery: Duration.zero,
      );
      final out = await s.pair(
        code: code,
        deviceName: 'x',
        onWaiting: () => token = 'tok-b',
      );
      expect(out, IdePairOutcome.failed);
      expect(store.values, isEmpty);
      expect(security.deleted, security.created);
    });

    test('kho bảo mật từ chối ghi: báo lỗi, bỏ khoá mới', () async {
      store.failWrites = true;
      final out = await service(
        _PairTransport([
          {'status': 'ok', 'device_id': 'd_abcdefgh'},
        ]),
      ).pair(code: code, deviceName: 'x');
      expect(out, IdePairOutcome.failed);
      expect(security.deleted, security.created);
    });

    test('IDE gỡ máy: chỉ xoá khi bản ghi còn là máy đó', () async {
      await service(
        _PairTransport([
          {'status': 'ok', 'device_id': 'd_abcdefgh'},
        ]),
      ).pair(code: code, deviceName: 'x');
      final s = service(_PairTransport([]));
      // Stream cũ của máy khác đóng vì revoked: giữ bản ghi mới.
      expect(await s.forgetRevokedDevice('d_oldoldold'), isFalse);
      expect(await s.forgetRevokedDevice(''), isFalse);
      expect(store.values, isNotEmpty);
      expect(security.deleted, isEmpty);

      expect(await s.forgetRevokedDevice('d_abcdefgh'), isTrue);
      expect(store.values, isEmpty);
      expect(security.deleted, security.created);
    });

    test('máy không tạo được khoá: báo đúng lý do, không gọi IDE', () async {
      for (final (code0, outcome) in [
        ('notEnrolled', IdePairOutcome.noLockScreen),
        ('biometricRequired', IdePairOutcome.biometricRequired),
        ('unsupported', IdePairOutcome.unsupported),
        ('unavailable', IdePairOutcome.failed),
      ]) {
        security.createError = code0;
        final t = _PairTransport([]);
        expect(await service(t).pair(code: code, deviceName: 'x'), outcome);
        expect(t.posted, isNull);
      }
      expect(store.values, isEmpty);
    });

    test('tên máy cắt còn 60 ký tự', () async {
      final t = _PairTransport([
        {'status': 'ok', 'device_id': 'd_abcdefgh'},
      ]);
      await service(t).pair(code: code, deviceName: 'a' * 100);
      expect((t.posted!['device_name'] as String).length, 60);
    });

    test('từ chối, hết hạn, mã lạ (404) đều không lưu khoá', () async {
      expect(
        await service(
          _PairTransport([
            {'status': 'rejected'},
          ]),
        ).pair(code: code, deviceName: 'x'),
        IdePairOutcome.rejected,
      );
      expect(
        await service(
          _PairTransport([
            {'status': 'expired'},
          ]),
        ).pair(code: code, deviceName: 'x'),
        IdePairOutcome.expired,
      );
      expect(
        await service(_PairTransport([404])).pair(code: code, deviceName: 'x'),
        IdePairOutcome.invalid,
      );
      expect(store.values, isEmpty);
    });

    test('IDE ngoại tuyến (503) và quá nhiều lần (429)', () async {
      final off = _PairTransport([
        {'status': 'pending'},
      ])..postStatus = 503;
      expect(
        await service(off).pair(code: code, deviceName: 'x'),
        IdePairOutcome.offline,
      );
      final many = _PairTransport([
        {'status': 'pending'},
      ])..postStatus = 429;
      expect(
        await service(many).pair(code: code, deviceName: 'x'),
        IdePairOutcome.rateLimited,
      );
    });

    test('chờ quá lâu thì báo hết thời gian', () async {
      final s = IdePairingService(
        api: IdePairApi(
          _PairTransport([
            {'status': 'pending'},
          ]),
        ),
        keys: IdeDeviceKeyStore(store),
        security: security,
        currentUserId: () async => 'u_1',
        serverScopeId: 'srv',
        pollEvery: const Duration(milliseconds: 5),
        maxWait: const Duration(milliseconds: 40),
      );
      expect(
        await s.pair(code: code, deviceName: 'x'),
        IdePairOutcome.timedOut,
      );
    });
  });
}
