import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel_factory.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';

import '../auth/support/core2_fakes.dart';

void main() {
  IdeChannelFactory build(IdeSocketOpener opener) => IdeChannelFactory(
    wsBaseUri: Uri.parse('wss://chat.example.test/ws'),
    serverScopeId: 'scope-a',
    tokens: MemoryTokenRepository(accessToken: 'token-x'),
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
    'HTTP 401 và 403 khi nâng cấp WS là unauthorized (không nối lại)',
    () async {
      for (final status in [401, 403]) {
        final error = await failWith(status);
        expect(error.reason, 'unauthorized');
        expect(error.deviceId, 'dev-1');
      }
    },
  );

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
