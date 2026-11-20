import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_step_up.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_device_key_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_canonical_json.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_credentials.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_errors.dart';

import 'support/fakes.dart';

List<int> _hex(String h) => [
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
];

String _toHex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Ed25519 (RFC 8032, vector 1)', () {
    final seed = base64Encode(
      _hex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'),
    );

    test('khoá công khai khớp vector', () async {
      final pub = await IdeDeviceKeyStore.publicKeyBase64(seed);
      expect(
        _toHex(base64Decode(pub)),
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      );
    });

    test('chữ ký thông điệp rỗng khớp vector', () async {
      final sig = await IdeDeviceKeyStore.signText(seed, '');
      expect(
        _toHex(base64Decode(sig)),
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );
    });

    test('signAuth ký đúng chuỗi webtui-ide-auth:v1', () async {
      final viaAuth = await IdeDeviceKeyStore.signAuth(
        seed: seed,
        nonce: 'bm9uY2U=',
        stream: 's_x',
        chatUser: 'u_1',
      );
      final direct = await IdeDeviceKeyStore.signText(
        seed,
        'webtui-ide-auth:v1|bm9uY2U=|s_x|u_1',
      );
      expect(viaAuth, direct);
    });
  });

  group('CANON JSON', () {
    test('xếp khoá mọi cấp, không khoảng trắng', () {
      expect(
        ideCanonicalJson({
          'b': 1,
          'a': {
            'z': true,
            'y': null,
            'x': [3, 'q'],
          },
        }),
        '{"a":{"x":[3,"q"],"y":null,"z":true},"b":1}',
      );
    });

    test('giữ nguyên tiếng Việt và emoji, không escape ngoài ASCII', () {
      expect(ideCanonicalJson({'tên': 'Đức Lâm 😀'}), '{"tên":"Đức Lâm 😀"}');
    });

    test('escape dấu nháy, gạch chéo ngược và ký tự điều khiển', () {
      expect(
        ideCanonicalJson({'k': 'a"b\\c\n\r\t\b\f\u0001\u001f'}),
        r'{"k":"a\"b\\c\n\r\t\b\f\u0001\u001f"}',
      );
    });

    test('thứ tự khoá theo byte UTF-8', () {
      // "é" (U+00E9) đứng sau "z" khi so byte.
      expect(ideCanonicalJson({'é': 1, 'z': 2}), '{"z":2,"é":1}');
    });

    test('chuỗi ký step có sha256 của CANON và args thiếu = null', () {
      final text = ideStepSigningString(
        stream: 's_1',
        req: 'r_1',
        challenge: 'Y2g=',
        op: 'deploy.run',
        args: null,
      );
      final canon = '{"args":null,"op":"deploy.run"}';
      final digest = sha256.convert(utf8.encode(canon)).toString();
      expect(text, 'webtui-ide-step:v1|s_1|r_1|Y2g=|$digest');
    });

    test('từ chối số thực (Dart / Python in khác nhau)', () {
      for (final v in [1.5, 1e-7, 1e16, double.nan]) {
        expect(() => ideCanonicalJson({'x': v}), throwsArgumentError);
      }
      expect(
        ideCanonicalJson({'x': 10000000000000000}),
        '{"x":10000000000000000}',
      );
    });
  });

  group('step-up ECDSA P-256', () {
    final request = IdeStepRequest(
      stream: 's_1',
      req: 'r_9',
      challenge: 'Y2g=',
      summary: 'Chạy deploy',
      op: 'deploy.run',
      args: {'env': 'prod', 'note': 'xong 😀'},
    );

    test('chữ ký kiểm được trên đúng chuỗi ký', () async {
      final security = FakeIdeSecurity();
      final stepUp = IdeStepUp(
        security: security,
        present: (_) async => true,
        alias: () => 'a',
      );
      final sig = await stepUp.confirm(request);
      expect(sig, isNotNull);
      final text = ideStepSigningString(
        stream: 's_1',
        req: 'r_9',
        challenge: 'Y2g=',
        op: 'deploy.run',
        args: request.args,
      );
      expect(security.key.verifyDerBase64(utf8.encode(text), sig!), isTrue);
      expect(security.key.verifyDerBase64(utf8.encode('$text!'), sig), isFalse);
    });

    test('người dùng không xác nhận hoặc huỷ vân tay thì trả null', () async {
      final declined = IdeStepUp(
        security: FakeIdeSecurity(),
        present: (_) async => false,
        alias: () => 'a',
      );
      expect(await declined.confirm(request), isNull);
      final security = FakeIdeSecurity()..stepCancelled = true;
      final cancelled = IdeStepUp(
        security: security,
        present: (_) async => true,
        alias: () => 'a',
      );
      expect(await cancelled.confirm(request), isNull);
    });

    test('hai lời hỏi vân tay cùng lúc thì xếp hàng', () async {
      var open = 0;
      var maxOpen = 0;
      final gate = Completer<void>();
      final security = FakeIdeSecurity();
      Future<bool> present(IdeStepSummary _) async {
        open++;
        if (open > maxOpen) maxOpen = open;
        await gate.future;
        open--;
        return true;
      }

      // Hai nguồn khác nhau (RPC client, phiên AI) dùng chung một hàng chờ.
      final a = IdeStepUp(
        security: security,
        present: present,
        alias: () => 'a',
      );
      final b = IdeStepUp(
        security: security,
        present: present,
        alias: () => 'a',
      );
      final fa = a.confirm(request);
      final fb = b.confirm(request);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(maxOpen, 1);
      gate.complete();
      expect(await fa, isNotNull);
      expect(await fb, isNotNull);
      expect(maxOpen, 1);
    });

    test('args có số thực: báo lỗi, không ký', () async {
      final security = FakeIdeSecurity();
      final stepUp = IdeStepUp(
        security: security,
        present: (_) async => true,
        alias: () => 'a',
      );
      final bad = IdeStepRequest(
        stream: 's_1',
        req: 'r_9',
        challenge: 'Y2g=',
        summary: '',
        op: 'deploy.run',
        args: {'ratio': 0.5},
      );
      await expectLater(stepUp.confirm(bad), throwsA(isA<IdeStepFailed>()));
    });
  });

  group('kho khoá máy', () {
    test('clearSession xoá khoá ide (kho thật theo khuôn)', () async {
      final store = MemorySecureStore();
      final keys = IdeDeviceKeyStore(store);
      await keys.save(
        IdeDeviceCredentials(
          instanceId: 'i',
          chatUserId: 'u_1',
          deviceId: 'd_12345678',
          seed: base64Encode(List<int>.filled(32, 1)),
          serverScope: 'srv',
        ),
      );
      expect(await keys.load(chatUserId: 'u_1', serverScope: 'srv'), isNotNull);
      expect(await keys.load(chatUserId: 'u_2', serverScope: 'srv'), isNull);
      expect(await keys.load(chatUserId: 'u_1', serverScope: 'other'), isNull);
      await keys.clear();
      expect(store.values.containsKey(SecureStoreKey.ideDevice), isFalse);
    });
  });
}
