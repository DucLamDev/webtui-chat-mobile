import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel_factory.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';

import '../auth/support/core2_fakes.dart';

void main() {
  IdeChannelFactory build(
    IdeSocketOpener opener, {
    MemoryTokenRepository? tokens,
    Future<IdeTokenRefresh> Function(AuthTokenMutationGuard guard)? refresh,
  }) => IdeChannelFactory(
    wsBaseUri: Uri.parse('wss://chat.example.test/ws'),
    serverScopeId: 'scope-a',
    tokens: tokens ?? MemoryTokenRepository(accessToken: 'token-x'),
    refreshAccessToken: refresh,
    loadCredentials: () async => const IdeDeviceCredentials(
      instanceId: 'i',
      chatUserId: 'u',
      deviceId: 'dev-1',
      seed: 'c2VlZA==',
      serverScope: 'scope-a',
    ),
    openSocket: opener,
  );

  Future<IdeHandshakeException> failWith(int? status) async {
    final factory = build(
      (uri, headers) async =>
          throw WebSocketException('was not upgraded to websocket', status),
    );
    try {
      await factory.open();
    } on IdeHandshakeException catch (error) {
      return error;
    }
    fail('phải ném IdeHandshakeException');
  }

  test('HTTP 403 khi nâng cấp WS là forbidden (dừng, không nối lại)', () async {
    final error = await failWith(403);
    expect(error.reason, 'forbidden');
    expect(error.deviceId, 'dev-1');
    expect(error.fatal, isTrue);
  });

  test('HTTP 401 không có hàm làm mới token: session_expired', () async {
    final error = await failWith(401);
    expect(error.reason, 'session_expired');
    expect(error.fatal, isTrue);
  });

  test('HTTP 401: làm mới token MỘT lần rồi nối lại bằng token mới', () async {
    final tokens = MemoryTokenRepository(accessToken: 'token-old');
    final sent = <String?>[];
    var refreshes = 0;
    final factory = build(
      (uri, headers) async {
        sent.add(headers['Authorization']);
        // Lần 1: token cũ hết hạn. Lần 2: đã nối được tới máy chủ, IDE tắt.
        throw WebSocketException('not upgraded', sent.length == 1 ? 401 : 503);
      },
      tokens: tokens,
      refresh: (guard) async {
        refreshes++;
        tokens.accessToken = 'token-new';
        return IdeTokenRefresh.refreshed;
      },
    );
    await expectLater(
      factory.open(),
      throwsA(
        isA<IdeHandshakeException>().having(
          (e) => e.reason,
          'reason',
          'ide_offline',
        ),
      ),
    );
    expect(refreshes, 1);
    expect(sent, ['Bearer token-old', 'Bearer token-new']);
  });

  test('vẫn 401 sau khi làm mới: dừng, không làm mới lần hai', () async {
    var refreshes = 0;
    var opens = 0;
    final factory = build(
      (uri, headers) async {
        opens++;
        throw const WebSocketException('not upgraded', 401);
      },
      refresh: (guard) async {
        refreshes++;
        return IdeTokenRefresh.refreshed;
      },
    );
    await expectLater(
      factory.open(),
      throwsA(
        isA<IdeHandshakeException>().having(
          (e) => e.reason,
          'reason',
          'session_expired',
        ),
      ),
    );
    expect(refreshes, 1);
    expect(opens, 2);
  });

  test('máy chủ từ chối làm mới: session_expired, không thử lại', () async {
    var opens = 0;
    final factory = build((uri, headers) async {
      opens++;
      throw const WebSocketException('not upgraded', 401);
    }, refresh: (guard) async => IdeTokenRefresh.rejected);
    await expectLater(
      factory.open(),
      throwsA(
        isA<IdeHandshakeException>().having(
          (e) => e.reason,
          'reason',
          'session_expired',
        ),
      ),
    );
    expect(opens, 1);
  });

  test('làm mới hỏng vì mạng (failed / ném lỗi): KHÔNG báo hết phiên, ném lỗi '
      'mạng để nối lại có giãn cách', () async {
    for (final refresh
        in <Future<IdeTokenRefresh> Function(AuthTokenMutationGuard)>[
          (guard) async => IdeTokenRefresh.failed,
          (guard) async => throw StateError('mất mạng'),
        ]) {
      var opens = 0;
      final factory = build((uri, headers) async {
        opens++;
        throw const WebSocketException('not upgraded', 401);
      }, refresh: refresh);
      await expectLater(
        factory.open(),
        throwsA(
          isA<WebSocketException>().having(
            (e) => e.httpStatusCode,
            'status',
            401,
          ),
        ),
      );
      expect(opens, 1);
    }
  });

  test('REST vừa làm mới token trong lúc nối: dùng token mới, không làm mới '
      'thêm', () async {
    final tokens = MemoryTokenRepository(accessToken: 'token-old');
    final sent = <String?>[];
    var refreshes = 0;
    final factory = build(
      (uri, headers) async {
        sent.add(headers['Authorization']);
        if (sent.length == 1) {
          tokens.accessToken = 'token-rest';
          throw const WebSocketException('not upgraded', 401);
        }
        throw const WebSocketException('not upgraded', 503);
      },
      tokens: tokens,
      refresh: (guard) async {
        refreshes++;
        return IdeTokenRefresh.refreshed;
      },
    );
    await expectLater(factory.open(), throwsA(isA<IdeHandshakeException>()));
    expect(refreshes, 0);
    expect(sent, ['Bearer token-old', 'Bearer token-rest']);
  });

  test('làm mới đúng phiên đang nối (truyền guard)', () async {
    AuthTokenMutationGuard? seen;
    final factory = build(
      (uri, headers) async =>
          throw const WebSocketException('not upgraded', 401),
      refresh: (guard) async {
        seen = guard;
        return IdeTokenRefresh.rejected;
      },
    );
    await expectLater(factory.open(), throwsA(isA<IdeHandshakeException>()));
    expect(seen, isNotNull);
  });

  test('HTTP 503 là ide_offline (nối lại có giãn cách)', () async {
    expect((await failWith(503)).reason, 'ide_offline');
  });

  test('lỗi mạng khác được ném lại nguyên văn để nối lại', () async {
    final factory = build(
      (uri, headers) async => throw const WebSocketException('mất mạng'),
    );
    await expectLater(factory.open(), throwsA(isA<WebSocketException>()));
  });
}
