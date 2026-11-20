import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_access.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel_factory.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';

import '../auth/support/core2_fakes.dart';
import 'support/fakes.dart';

const _scope = 'scope-a';

IdeDeviceCredentials _creds({String scope = _scope, String user = 'u_1'}) =>
    IdeDeviceCredentials(
      instanceId: 'i',
      chatUserId: user,
      deviceId: 'd_12345678',
      seed: base64Encode(List<int>.filled(32, 1)),
      serverScope: scope,
    );

final class _Opener {
  _Opener({this.chatUser = 'u_1', this.onOpen, this.drain = false});

  final String chatUser;

  /// Nghe sẵn luồng khung: ca kênh không bao giờ bắt tay, để `close()` của
  /// ổ cắm giả xong được.
  final bool drain;
  final void Function()? onOpen;
  final sockets = <FakeIdeSocket>[];
  Uri? uri;
  Map<String, String>? headers;

  Future<IdeSocket> call(Uri uri, Map<String, String> headers) async {
    this.uri = uri;
    this.headers = headers;
    onOpen?.call();
    final socket = FakeIdeSocket(chatUser: chatUser);
    if (drain) socket.messages.listen((_) {});
    sockets.add(socket);
    return socket;
  }
}

IdeChannelFactory _factory({
  required MemoryTokenRepository tokens,
  required _Opener opener,
  IdeDeviceCredentials? creds,
}) => IdeChannelFactory(
  wsBaseUri: Uri.parse('wss://chat.company.example/ws?token=leak'),
  serverScopeId: _scope,
  tokens: tokens,
  loadCredentials: () async => creds,
  openSocket: opener.call,
);

TypeMatcher<IdeHandshakeException> _handshake(String reason) =>
    isA<IdeHandshakeException>().having((e) => e.reason, 'reason', reason);

SelfHostedServerDiscovery _discovery({
  String domain = SelfHostedServerDiscovery.vpstttInternalHost,
  String zone = SelfHostedServerDiscovery.vpstttInternalZoneKind,
  bool ide = true,
}) => SelfHostedServerDiscovery(
  instanceId: '11111111-1111-4111-8111-111111111111',
  discoveryVersion: '1',
  domain: domain,
  name: 'Máy chủ thử',
  apiBaseUri: Uri.parse('https://$domain'),
  wsBaseUri: Uri.parse('wss://$domain/ws'),
  registrationMode: 'closed',
  appVersion: '1.0.0',
  apiContractVersion: 1,
  serverVersion: '1.0.0',
  minimumSupportedMobileVersion: '1.0.0',
  capabilities: SelfHostedCapabilities(ide: ide),
  zoneKind: zone,
);

void main() {
  const guard = AuthTokenMutationGuard(
    instanceScopeId: _scope,
    generation: 'g1',
  );

  group('IdeChannelFactory: chặn trước khi mở socket', () {
    test('chưa gắn máy: not_paired, không mở socket', () async {
      final opener = _Opener();
      final f = _factory(
        tokens: MemoryTokenRepository(guard: guard, accessToken: 'tok'),
        opener: opener,
      );
      await expectLater(f.open(), throwsA(_handshake('not_paired')));
      expect(opener.sockets, isEmpty);
    });

    test('khoá gắn của máy chủ khác: not_paired, không mở socket', () async {
      final opener = _Opener();
      final f = _factory(
        tokens: MemoryTokenRepository(guard: guard, accessToken: 'tok'),
        opener: opener,
        creds: _creds(scope: 'scope-khac'),
      );
      await expectLater(f.open(), throwsA(_handshake('not_paired')));
      expect(opener.sockets, isEmpty);
    });

    test('chưa đăng nhập / phiên thuộc máy chủ khác: no_session', () async {
      for (final g in <AuthTokenMutationGuard?>[
        null,
        const AuthTokenMutationGuard(
          instanceScopeId: 'scope-khac',
          generation: 'g1',
        ),
      ]) {
        final opener = _Opener();
        final f = _factory(
          tokens: MemoryTokenRepository(guard: g, accessToken: 'tok'),
          opener: opener,
          creds: _creds(),
        );
        await expectLater(f.open(), throwsA(_handshake('no_session')));
        expect(opener.sockets, isEmpty);
      }
    });

    test('không có token (rỗng / chỉ khoảng trắng): no_session', () async {
      for (final t in <String?>[null, '', '   ']) {
        final opener = _Opener();
        final f = _factory(
          tokens: MemoryTokenRepository(guard: guard, accessToken: t),
          opener: opener,
          creds: _creds(),
        );
        await expectLater(f.open(), throwsA(_handshake('no_session')));
        expect(opener.sockets, isEmpty);
      }
    });
  });

  group('IdeChannelFactory: phiên đổi giữa chừng', () {
    test('phiên đổi lúc đang mở socket: đóng socket, no_session', () async {
      final tokens = MemoryTokenRepository(guard: guard, accessToken: 'tok');
      final opener = _Opener(
        drain: true,
        onOpen: () => tokens.guard = const AuthTokenMutationGuard(
          instanceScopeId: _scope,
          generation: 'g2',
        ),
      );
      final f = _factory(tokens: tokens, opener: opener, creds: _creds());
      await expectLater(f.open(), throwsA(_handshake('no_session')));
      expect(opener.sockets.single.closed, isTrue);
      expect(opener.sockets.single.sentOfType('auth'), isEmpty);
    });
  });

  group('IdeChannelFactory: bắt tay', () {
    test('IDE báo chat_user khác người đã gắn: wrong_user, không ký', () async {
      final opener = _Opener(chatUser: 'u_2');
      final f = _factory(
        tokens: MemoryTokenRepository(guard: guard, accessToken: 'tok'),
        opener: opener,
        creds: _creds(),
      );
      await expectLater(
        f.open(),
        throwsA(
          _handshake(
            'wrong_user',
          ).having((e) => e.deviceId, 'deviceId', 'd_12345678'),
        ),
      );
      expect(opener.sockets.single.sentOfType('auth'), isEmpty);
    });

    test('token chỉ ở header, không trên URL; ký và nối được', () async {
      final opener = _Opener();
      final f = _factory(
        tokens: MemoryTokenRepository(guard: guard, accessToken: ' tok-1 '),
        opener: opener,
        creds: _creds(),
      );
      final channel = await f.open();
      addTearDown(channel.close);

      final uri = opener.uri!;
      expect(uri.path, '/api/v1/ide/ws');
      expect(uri.query, isEmpty);
      expect(uri.toString(), isNot(contains('tok')));
      expect(opener.headers, {
        'Authorization': 'Bearer tok-1',
        'X-IDE-Device': 'd_12345678',
      });
      final auth = opener.sockets.single.sentOfType('auth').single;
      expect(auth['sig'], isA<String>());
      expect(auth['sig'], isNot('sig'));
      expect(channel.deviceId, 'd_12345678');
    });
  });

  group('ideEnabledProvider', () {
    bool enabled(SelfHostedServerDiscovery? d) {
      final c = ProviderContainer(
        overrides: [activeServerDiscoveryProvider.overrideWithValue(d)],
      );
      addTearDown(c.dispose);
      return c.read(ideEnabledProvider);
    }

    test('chỉ bật khi máy chủ nội bộ VPSTTT và báo capabilities.ide', () {
      expect(enabled(_discovery()), isTrue);
      expect(enabled(null), isFalse);
      expect(enabled(_discovery(ide: false)), isFalse);
      expect(enabled(_discovery(domain: 'chat.company.example')), isFalse);
      expect(enabled(_discovery(zone: 'dedicated')), isFalse);
      expect(
        enabled(_discovery(domain: 'chat.company.example', zone: 'dedicated')),
        isFalse,
      );
    });
  });

  group('IdeChannelFactory: mã lỗi HTTP khi nâng cấp WS', () {
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

    test(
      'HTTP 403 khi nâng cấp WS là forbidden (dừng, không nối lại)',
      () async {
        final error = await failWith(403);
        expect(error.reason, 'forbidden');
        expect(error.deviceId, 'dev-1');
        expect(error.fatal, isTrue);
      },
    );

    test('HTTP 401 không có hàm làm mới token: session_expired', () async {
      final error = await failWith(401);
      expect(error.reason, 'session_expired');
      expect(error.fatal, isTrue);
    });

    test(
      'HTTP 401: làm mới token MỘT lần rồi nối lại bằng token mới',
      () async {
        final tokens = MemoryTokenRepository(accessToken: 'token-old');
        final sent = <String?>[];
        var refreshes = 0;
        final factory = build(
          (uri, headers) async {
            sent.add(headers['Authorization']);
            // Lần 1: token cũ hết hạn. Lần 2: đã nối được tới máy chủ, IDE tắt.
            throw WebSocketException(
              'not upgraded',
              sent.length == 1 ? 401 : 503,
            );
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
      },
    );

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

    test(
      'làm mới hỏng vì mạng (failed / ném lỗi): KHÔNG báo hết phiên, ném lỗi '
      'mạng để nối lại có giãn cách',
      () async {
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
      },
    );

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
  });
}
