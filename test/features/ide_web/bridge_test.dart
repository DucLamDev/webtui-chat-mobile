import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_bridge_dispatcher.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_device_keys.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_prompter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_rate_limiter.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_bridge_protocol.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_ports.dart';

import 'support/fakes.dart';

/// TC7: cầu nối.
final class _Rig {
  _Rig() {
    dispatcher = newDispatcher();
  }

  final chip = FakeKeyChip();
  final files = FakeFileSaver();
  final prompter = FakePrompter();
  final store = MemoryKeyStore();
  final logs = <String>[];
  DateTime now = DateTime.utc(2026);
  bool active = true;
  bool session = true;
  late final limiter = IdeWebRateLimiter(clock: () => now);
  late final keys = IdeWebDeviceKeys(chip: chip, store: store);
  late IdeWebBridgeDispatcher dispatcher;
  int _id = 0;

  IdeWebBridgeDispatcher newDispatcher() => IdeWebBridgeDispatcher(
    owner: testOwner,
    origin: testOrigin,
    appInfo: const IdeWebAppInfo(
      appVersion: '1.66.0',
      platform: 'android',
      osVersion: '15',
    ),
    keys: keys,
    files: files,
    prompter: prompter,
    limiter: limiter,
    isActive: () => active,
    isSessionCurrent: () async => session,
    log: (method, code) => logs.add('$method $code'),
  );

  Future<Map<String, dynamic>> raw(
    String text, {
    bool mainFrame = true,
    String origin = testOrigin,
  }) async =>
      jsonDecode(
            await dispatcher.handle(
              raw: text,
              isMainFrame: mainFrame,
              messageOrigin: origin,
            ),
          )
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> call(String method, [Object? params]) => raw(
    jsonEncode({
      'v': 1,
      'id': 'r${_id++}',
      'method': method,
      'params': ?params,
    }),
  );

  Future<String> createKey([String purpose = 'possession']) async {
    final reply = await call('device.create', {
      'purpose': purpose,
      'challenge': testChallenge,
    });
    return (reply['result'] as Map<String, dynamic>)['key_id'] as String;
  }

  Future<Map<String, dynamic>> sign(String keyId) =>
      call('device.sign', {'key_id': keyId, 'challenge': testChallenge});
}

String? code(Map<String, dynamic> reply) =>
    (reply['error'] as Map<String, dynamic>?)?['code'] as String?;

void main() {
  late _Rig rig;
  setUp(() => rig = _Rig());

  test('mẫu yêu cầu của hợp đồng đi đúng đường', () async {
    final sample = fixture('bridge-messages.json');
    final reply = await rig.raw(jsonEncode(sample['request']));
    expect(reply['id'], 'req-1');
    expect(code(reply), 'key_missing');
    expect(
      jsonDecode(
        encodeBridgeError(
          'req-1',
          BridgeErrorCode.forbiddenOrigin,
          'Trang này không được phép.',
        ),
      ),
      sample['error'],
    );
    expect(
      jsonDecode(encodeBridgeResult('req-1', {'signature': '…'})),
      sample['ok'],
    );
    expect(
      jsonDecode(encodeBridgeEvent(BridgeEvent.background)),
      sample['event'],
    );
  });

  test('app.info có đúng 7 hàm', () async {
    final reply = await rig.call('app.info');
    final result = reply['result'] as Map<String, dynamic>;
    expect(result['methods'], [
      'app.info',
      'device.status',
      'device.create',
      'device.sign',
      'device.delete',
      'file.save',
      'app.close',
    ]);
    expect(result['bridge_version'], 1);
    expect(result['os_version'], '15');
  });

  test('vòng đời khoá', () async {
    final id = await rig.createKey();
    final status =
        (await rig.call('device.status'))['result'] as Map<String, dynamic>;
    expect((status['keys'] as List).single, {
      'key_id': id,
      'purpose': 'possession',
      'created_at': isA<String>(),
      'usable': true,
    });
    expect((await rig.sign(id))['result'], {'signature': isA<String>()});
    // Không hỏi hộp xác nhận khi ký; có hỏi khi tạo, xoá.
    expect(rig.prompter.prompts, [isA<IdeWebCreateKeyPrompt>()]);
    expect(
      (await rig.call('device.delete', {'key_id': id}))['result'],
      isEmpty,
    );
    expect(rig.prompter.prompts.last, isA<IdeWebDeleteKeyPrompt>());
    expect(code(await rig.sign(id)), 'key_missing');
  });

  test('origin lạ và iframe bị từ chối, trả đúng id', () async {
    const request = '{"v":1,"id":"a1","method":"app.info"}';
    for (final origin in [
      'https://evil.example',
      'http://ide.chat.example.com',
      'https://ide.chat.example.com.evil.example',
      'https://ide.chat.example.com:8443',
      'null',
      '',
    ]) {
      final reply = await rig.raw(request, origin: origin);
      expect(code(reply), 'forbidden_origin', reason: origin);
      expect(reply['id'], 'a1');
    }
    expect(code(await rig.raw(request, mainFrame: false)), 'forbidden_origin');
    expect((await rig.raw(request))['ok'], isTrue);
  });

  test('yêu cầu sai dạng', () async {
    final cases = <String, String>{
      '': 'bad_request',
      '{': 'bad_request',
      '[]': 'bad_request',
      'null': 'bad_request',
      '{"v":1,"id":"a","method":"app.info","x":1}': 'bad_request',
      '{"v":"1","id":"b","method":"app.info"}': 'bad_request',
      '{"v":2,"id":"c","method":"app.info"}': 'unsupported_version',
      '{"v":1,"id":"d d","method":"app.info"}': 'bad_request',
      '{"v":1,"id":"","method":"app.info"}': 'bad_request',
      '{"v":1,"id":"${'e' * 65}","method":"app.info"}': 'bad_request',
      '{"v":1,"id":5,"method":"app.info"}': 'bad_request',
      '{"v":1,"id":"f","method":"app.unknown"}': 'unknown_method',
      '{"v":1,"id":"g","method":"__proto__"}': 'unknown_method',
      '{"v":1,"id":"h","method":"toString"}': 'unknown_method',
      '{"v":1,"id":"i","method":5}': 'bad_request',
      '{"v":1,"id":"j","method":"app.info","params":[]}': 'bad_request',
      '{"v":1,"id":"k","method":"app.info","params":{"__proto__":{}}}':
          'bad_request',
      '{"v":1,"id":"l","method":"device.sign","params":{"key_id":"x"}}':
          'bad_request',
      '{"v":1,"id":"m","method":"device.sign","params":{"key_id":"x","challenge":"$testChallenge","alias":"y"}}':
          'bad_request',
      '{"v":1,"id":"n","method":"device.sign","params":{"key_id":"../x","challenge":"$testChallenge"}}':
          'bad_request',
      '{"v":1,"id":"o","method":"device.create","params":{"purpose":"root","challenge":"$testChallenge"}}':
          'bad_request',
      '{"v":1,"id":"p","method":"device.create","params":{"purpose":"biometric","challenge":"ngan"}}':
          'bad_request',
      '{"v":1,"id":"q","method":"device.create","params":{"purpose":{},"challenge":1}}':
          'bad_request',
    };
    for (final entry in cases.entries) {
      expect(code(await rig.raw(entry.key)), entry.value, reason: entry.key);
    }
    expect(rig.chip.keys, isEmpty);
    expect(rig.prompter.prompts, isEmpty);
  });

  test('id chỉ dùng một lần trong một trang', () async {
    const request = '{"v":1,"id":"a","method":"app.info"}';
    expect((await rig.raw(request))['ok'], isTrue);
    expect(code(await rig.raw(request)), 'bad_request');
    rig.dispatcher.onNavigation();
    expect((await rig.raw(request))['ok'], isTrue);
  });

  test('quá cỡ', () async {
    final big = 'a' * (bridgeMaxBytes + 1);
    expect(code(await rig.call('app.info', {'x': big})), 'too_large');
    // Có chữ file.save nhưng không phải hàm đó.
    expect(
      code(await rig.call('device.delete', {'key_id': 'file.save$big'})),
      'too_large',
    );
    expect(
      code(
        await rig.raw(
          '{"v":1,"id":"z","method":"file.save","params":"${'a' * bridgeMaxFileBytes}"}',
        ),
      ),
      'too_large',
    );
    // Ký tự nhiều byte cũng tính theo byte.
    expect(
      code(await rig.call('app.info', {'x': 'ệ' * (bridgeMaxBytes ~/ 3 + 1)})),
      'too_large',
    );
  });

  test('giới hạn tần suất, kể cả sau khi đóng mở lại màn', () async {
    for (var i = 0; i < 5; i++) {
      await rig.createKey();
    }
    Future<String?> create() async => code(
      await rig.call('device.create', {
        'purpose': 'possession',
        'challenge': testChallenge,
      }),
    );
    expect(await create(), 'rate_limited');
    rig.dispatcher.close();
    rig.dispatcher = rig.newDispatcher();
    expect(await create(), 'rate_limited');
    rig.now = rig.now.add(const Duration(hours: 1));
    expect(await create(), isNull);

    final id = rig.store.value!.keys.first.keyId;
    for (var i = 0; i < 10; i++) {
      expect(code(await rig.sign(id)), isNull);
    }
    expect(code(await rig.sign(id)), 'rate_limited');
    for (var i = 0; i < 30; i++) {
      expect(code(await rig.call('app.info')), isNull);
    }
    expect(code(await rig.call('device.status')), 'rate_limited');
  });

  test('một việc một lúc, chờ tối đa 8, tràn thì busy', () async {
    final id = await rig.createKey();
    rig.chip.signGate = Completer<void>();
    final futures = [for (var i = 0; i < 10; i++) rig.sign(id)];
    await settle();
    rig.chip.signGate!.complete();
    final codes = [for (final reply in await Future.wait(futures)) code(reply)];
    expect(codes.where((c) => c == null), hasLength(9));
    expect(codes.last, 'busy');
    expect(rig.chip.signed, hasLength(10));
  });

  test(
    'đổi trang: việc chờ bị huỷ, kết quả cũ không trả, vẫn trả lời',
    () async {
      final id = await rig.createKey();
      rig.chip.signGate = Completer<void>();
      final running = rig.sign(id);
      final waiting = rig.sign(id);
      await settle();
      rig.dispatcher.onNavigation();
      expect(code(await waiting), 'cancelled');
      rig.chip.signGate!.complete();
      final reply = await running;
      expect(code(reply), 'cancelled');
      expect(reply['id'], isNotEmpty);
      // Hàng đợi không kẹt.
      expect(code(await rig.sign(id)), isNull);
      expect(rig.chip.signed, hasLength(3));
    },
  );

  test('đổi trang giữa lúc tạo khoá: khoá bị xoá', () async {
    rig.chip.createGate = Completer<void>();
    final creating = rig.call('device.create', {
      'purpose': 'biometric',
      'challenge': testChallenge,
    });
    await settle();
    rig.dispatcher.onNavigation();
    rig.chip.createGate!.complete();
    expect(code(await creating), 'cancelled');
    expect(rig.chip.keys, isEmpty);
  });

  test('hộp xác nhận: từ chối hoặc màn không còn hiện thì không làm', () async {
    rig.prompter.answer = false;
    expect(
      code(
        await rig.call('device.create', {
          'purpose': 'possession',
          'challenge': testChallenge,
        }),
      ),
      'cancelled',
    );
    rig
      ..prompter.answer = true
      ..active = false;
    expect(
      code(
        await rig.call('device.create', {
          'purpose': 'possession',
          'challenge': testChallenge,
        }),
      ),
      'cancelled',
    );
    expect(rig.chip.keys, isEmpty);
  });

  test('ký bị chặn khi màn khoá / nền hoặc phiên chat đã hết', () async {
    final id = await rig.createKey();
    rig.active = false;
    expect(code(await rig.sign(id)), 'cancelled');
    rig
      ..active = true
      ..session = false;
    expect(code(await rig.sign(id)), 'cancelled');
    expect(code(await rig.call('device.status')), 'cancelled');
    expect(rig.chip.signed, hasLength(1));
  });

  test('mã lỗi của chip đi thẳng ra trang', () async {
    final id = await rig.createKey('biometric');
    for (final error in [
      'cancelled',
      'not_enrolled',
      'unsupported',
      'failed',
    ]) {
      rig.chip.signError = error;
      expect(code(await rig.sign(id)), error);
    }
    rig.chip.signError = 'key_invalid';
    expect(code(await rig.sign(id)), 'key_invalid');
  });

  group('file.save', () {
    Future<Map<String, dynamic>> save(
      String name, {
      String mime = 'text/plain',
      String? data,
    }) => rig.call('file.save', {
      'name': name,
      'mime': mime,
      'data_base64': data ?? base64.encode(utf8.encode('xin chào')),
    });

    test('lưu sau khi hỏi, tên đã làm sạch, MIME theo đuôi', () async {
      final reply = await save(
        '../../a\u202Eb/ba\u0000o cao.pdf',
        mime: 'text/csv',
      );
      expect(reply['result'], {'saved': true});
      final prompt = rig.prompter.prompts.single as IdeWebSaveFilePrompt;
      expect(prompt.name, 'bao cao.pdf');
      expect(rig.files.saved.single.name, 'bao cao.pdf');
      expect(rig.files.saved.single.mime, 'application/pdf');
      expect(utf8.decode(rig.files.saved.single.bytes), 'xin chào');
    });

    test('chặn đuôi / loại nguy hiểm, kể cả mẹo tên', () async {
      for (final name in [
        'a.apk',
        'a.EXE',
        'a.html',
        'a.mobileconfig',
        'a.apk.',
        'a.apk ',
        'a.ap\u200Bk',
      ]) {
        expect(code(await save(name)), 'unsupported', reason: name);
      }
      rig.now = rig.now.add(const Duration(minutes: 2));
      expect(
        code(
          await save('a.txt', mime: 'application/vnd.android.package-archive'),
        ),
        'unsupported',
      );
      expect(rig.files.saved, isEmpty);
      expect(rig.prompter.prompts, isEmpty);
    });

    test('sai dạng, quá 10 MB, huỷ, lỗi', () async {
      expect(code(await save('a.txt', data: '***')), 'bad_request');
      expect(code(await save('a.txt', mime: 'la')), 'bad_request');
      expect(
        code(
          await save('a.txt', data: 'AAAA' * (4 * 1024 * 1024 - 1) + 'AA=='),
        ),
        'too_large',
      );
      expect(
        code(await save('a.txt', data: 'AAAA' * (10 * 1024 * 1024 ~/ 3 + 2))),
        'too_large',
      );
      rig.files.result = IdeWebFileSaveResult.cancelled;
      expect(code(await save('a.txt')), 'cancelled');
      rig.files.result = IdeWebFileSaveResult.failed;
      expect(code(await save('a.txt')), 'failed');
      rig.prompter.answer = false;
      expect(code(await save('a.txt')), 'cancelled');
    });
  });

  test('app.close trả lời rồi mới đóng', () async {
    final reply = await rig.call('app.close');
    expect(reply['ok'], isTrue);
    expect(rig.prompter.closed, 0);
    await settle();
    expect(rig.prompter.closed, 1);
  });

  test('đã đóng thì chỉ trả cancelled', () async {
    rig.dispatcher.close();
    expect(code(await rig.call('app.info')), 'cancelled');
  });

  test('nhật ký chỉ có tên hàm và mã', () async {
    final id = await rig.createKey();
    await rig.sign(id);
    await rig.raw('{"v":1,"id":"bi-mat","method":"la"}');
    expect(rig.logs, [
      'device.create ok',
      'device.sign ok',
      '- unknown_method',
    ]);
  });
}
