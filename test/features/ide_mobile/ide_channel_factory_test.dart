import 'dart:convert';

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
}
