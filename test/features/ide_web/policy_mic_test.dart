import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_mic_guard.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_prompter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_view.dart';
import 'package:webtui_chat/features/ide_web/data/method_channel_ide_web_browser.dart';
import 'package:webtui_chat/features/ide_web/data/method_channel_ide_web_host.dart';
import 'package:webtui_chat/features/ide_web/data/platform_ide_web_file_saver.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_file.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_host_policy.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_ports.dart';

import 'support/fakes.dart';

/// TC8: địa chỉ, micro, tệp, kênh native.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('phân loại địa chỉ', () {
    final policy = IdeWebHostPolicy(testBase);
    const table = {
      'https://ide.chat.example.com': IdeWebUrlClass.internal,
      'https://ide.chat.example.com/appchat/x?y#z': IdeWebUrlClass.internal,
      'https://IDE.chat.example.com:443/': IdeWebUrlClass.internal,
      'https://user@ide.chat.example.com/': IdeWebUrlClass.blocked,
      'https://ide.chat.example.com:8443/': IdeWebUrlClass.blocked,
      'http://ide.chat.example.com/': IdeWebUrlClass.blocked,
      'https://ide.chat.example.com.evil.example/': IdeWebUrlClass.external,
      'https://evil.example/ide.chat.example.com': IdeWebUrlClass.external,
      'https://ide.chat.example.com@evil.example/': IdeWebUrlClass.blocked,
      'https://chat.example.com/': IdeWebUrlClass.external,
      'https://ide.chat.examplé.com/': IdeWebUrlClass.external,
      'intent://x#Intent;scheme=https;end': IdeWebUrlClass.blocked,
      'data:text/html,x': IdeWebUrlClass.blocked,
      'javascript:alert(1)': IdeWebUrlClass.blocked,
      'file:///etc/passwd': IdeWebUrlClass.blocked,
      'content://x/y': IdeWebUrlClass.blocked,
      'blob:https://ide.chat.example.com/1': IdeWebUrlClass.blocked,
      'about:blank': IdeWebUrlClass.blocked,
      'webtui://ide-web/callback': IdeWebUrlClass.blocked,
      'http://[': IdeWebUrlClass.blocked,
      '': IdeWebUrlClass.blocked,
    };
    table.forEach(
      (url, kind) => expect(policy.classifyText(url), kind, reason: url),
    );
    expect(policy.classifyText(null), IdeWebUrlClass.blocked);
  });

  group('micro', () {
    late FakeIdeWebView view;
    late FakePrompter prompter;
    late FakeMicPermission permission;
    late IdeWebScreenStatus status;
    late IdeWebMicGuard mic;
    late DateTime now;
    const ok = IdeWebScreenStatus(
      visible: true,
      resumed: true,
      locked: false,
      inCall: false,
    );
    const inCall = IdeWebScreenStatus(
      visible: true,
      resumed: true,
      locked: false,
      inCall: true,
    );
    setUp(() {
      view = FakeIdeWebView();
      prompter = FakePrompter();
      permission = FakeMicPermission();
      status = ok;
      now = DateTime.utc(2026);
      mic = IdeWebMicGuard(
        view: view,
        policy: IdeWebHostPolicy(testBase),
        prompter: prompter,
        permission: permission,
        status: () => status,
        stopGrace: const Duration(milliseconds: 1),
        clock: () => now,
      );
    });
    Future<bool> ask({bool micOnly = true, String? url = testOrigin}) =>
        mic.decide(microphoneOnly: micOnly, mainUrl: url);

    test('đủ điều kiện: hỏi một lần mỗi phiên màn', () async {
      expect(await ask(), isTrue);
      expect(await ask(), isTrue);
      expect(prompter.prompts, [isA<IdeWebMicrophonePrompt>()]);
      expect(permission.asked, 2);
    });

    test('thiếu từng điều kiện thì từ chối, không hỏi', () async {
      expect(await ask(micOnly: false), isFalse);
      expect(await ask(url: 'https://evil.example'), isFalse);
      expect(await ask(url: null), isFalse);
      for (final s in const [
        IdeWebScreenStatus(
          visible: false,
          resumed: true,
          locked: false,
          inCall: false,
        ),
        IdeWebScreenStatus(
          visible: true,
          resumed: false,
          locked: false,
          inCall: false,
        ),
        IdeWebScreenStatus(
          visible: true,
          resumed: true,
          locked: true,
          inCall: false,
        ),
        inCall,
      ]) {
        status = s;
        expect(await ask(), isFalse);
      }
      expect(prompter.prompts, isEmpty);
      expect(permission.asked, 0);
    });

    test('người dùng hoặc hệ điều hành từ chối', () async {
      prompter.answer = false;
      expect(await ask(), isFalse);
      expect(permission.asked, 0);
      prompter.answer = true;
      permission.granted = false;
      expect(await ask(), isFalse);
    });

    test('có cuộc gọi trong lúc hỏi: kiểm lại và từ chối', () async {
      prompter.gate = Completer<bool>();
      final future = ask();
      // Trang xin chồng: từ chối ngay.
      expect(await ask(), isFalse);
      status = inCall;
      prompter.gate!.complete(true);
      expect(await future, isFalse);
    });

    test('dừng: trang chịu dừng thì không tải trang trống', () async {
      await ask();
      mic.onCaptureChanged(active: true);
      expect(mic.capturing.value, isTrue);
      final stop = mic.stop();
      mic.onCaptureChanged(active: false);
      await stop;
      expect(view.log, ['stopCapture']);
      expect(mic.capturing.value, isFalse);
    });

    test(
      'dừng: vẫn thu thì tải trang trống, quay lại mở lại trang chính',
      () async {
        await ask();
        mic.onCaptureChanged(active: true);
        view.capture = true;
        status = inCall;
        await mic.stop();
        expect(view.log, ['stopCapture', 'blank']);
        expect(mic.blanked, isTrue);
        await mic.resume();
        expect(view.log, isNot(contains('home')));
        status = ok;
        await mic.resume();
        await mic.resume();
        expect(view.log.where((e) => e == 'home'), hasLength(1));
      },
    );

    test(
      'cuộc gọi / tin thoại của app không bị coi là trang đang thu',
      () async {
        mic.onCaptureChanged(active: true);
        expect(mic.capturing.value, isFalse);
        await ask();
        now = now.add(const Duration(minutes: 1));
        status = inCall;
        view.capture = true;
        mic.onCaptureChanged(active: true);
        await settle();
        expect(mic.capturing.value, isFalse);
        expect(view.log, ['stopCapture']);
      },
    );

    test('vừa cấp xong thì màn bị che: dừng thật', () async {
      await ask();
      status = inCall;
      view.capture = true;
      mic.onCaptureChanged(active: true);
      await settle();
      expect(view.log, ['stopCapture', 'blank']);
    });
  });

  group('kênh native', () {
    const host = MethodChannel('webtui/ide_web_host');
    const auth = MethodChannel('webtui/ide_web_auth');
    final calls = <MethodCall>[];
    tearDown(() {
      calls.clear();
      messenger
        ..setMockMethodCallHandler(host, null)
        ..setMockMethodCallHandler(auth, null);
    });

    test('ide_web_host đúng tên hàm và đối số', () async {
      messenger.setMockMethodCallHandler(host, (call) async {
        calls.add(call);
        return switch (call.method) {
          'attach' => {'supported': true},
          'captureState' => {'active': true},
          _ => null,
        };
      });
      const channel = MethodChannelIdeWebHost();
      expect(
        await channel.attach(
          webViewId: 3,
          allowedOrigin: testOrigin,
          bridgeEnabled: true,
        ),
        isTrue,
      );
      await channel.postReply(webViewId: 3, replyId: 'r', payload: 'p');
      await channel.emit(webViewId: 3, payload: 'p');
      expect(await channel.captureActive(), isTrue);
      await channel.stopCapture(3);
      await channel.detach(3);
      await channel.clearAll();
      expect(calls.map((c) => c.method), [
        'attach',
        'postReply',
        'emit',
        'captureState',
        'stopCapture',
        'detach',
        'clearAllData',
      ]);
      expect(calls.first.arguments, {
        'webViewId': 3,
        'allowedOrigin': testOrigin,
        'bridgeEnabled': true,
      });
      expect(calls[1].arguments, {
        'webViewId': 3,
        'replyId': 'r',
        'payload': 'p',
      });
    });

    test('sự kiện: chỉ nhận đúng WebView, dữ liệu lạ bị bỏ', () {
      final message = {
        'type': 'message',
        'webViewId': 3,
        'id': 'r',
        'json': '{}',
        'isMainFrame': true,
        'origin': testOrigin,
      };
      final event = parseIdeWebHostEvent(message, 3)! as IdeWebBridgeMessage;
      expect(event.replyId, 'r');
      expect(event.isMainFrame, isTrue);
      expect(parseIdeWebHostEvent(message, 4), isNull);
      expect(parseIdeWebHostEvent({...message, 'json': 1}, 3), isNull);
      expect(
        (parseIdeWebHostEvent({...message, 'isMainFrame': 'true'}, 3)!
                as IdeWebBridgeMessage)
            .isMainFrame,
        isFalse,
      );
      expect(
        parseIdeWebHostEvent({'type': 'capture', 'active': true}, 3),
        isA<IdeWebCaptureChanged>(),
      );
      expect(
        parseIdeWebHostEvent({'type': 'render_gone'}, 3),
        isA<IdeWebRenderGone>(),
      );
      expect(parseIdeWebHostEvent({'type': 'la'}, 3), isNull);
      expect(parseIdeWebHostEvent('x', 3), isNull);
    });

    test('ide_web_auth', () async {
      const browser = MethodChannelIdeWebBrowser();
      final url = Uri.parse('$testOrigin/_appchat/start#t=x');
      Object? answer;
      messenger.setMockMethodCallHandler(auth, (call) async {
        calls.add(call);
        return answer;
      });
      Future<IdeWebBrowserResult> open(Uri u) =>
          browser.authenticate(u, scheme: 'webtui');
      answer = {'mode': 'deeplink'};
      expect(await open(url), isA<IdeWebBrowserOpened>());
      expect(calls.single.arguments, {
        'url': '$url',
        'callbackScheme': 'webtui',
      });
      answer = {'mode': 'cancelled'};
      expect(await open(url), isA<IdeWebBrowserCancelled>());
      answer = {'mode': 'result', 'url': '${callbackUri()}'};
      expect((await open(url) as IdeWebBrowserCallback).uri, callbackUri());
      answer = {'mode': 'la'};
      expect(await open(url), isA<IdeWebBrowserFailed>());
      calls.clear();
      expect(
        await open(Uri.parse('http://x.example')),
        isA<IdeWebBrowserFailed>(),
      );
      expect(calls, isEmpty);
      messenger.setMockMethodCallHandler(auth, null);
      expect(await open(url), isA<IdeWebBrowserFailed>());
    });
  });

  group('lưu tệp', () {
    const channel = MethodChannel('webtui/downloads');
    late Directory root;
    late IdeWebFile file;
    setUp(() {
      root = Directory.systemTemp.createTempSync('ide-web-test-');
      file = IdeWebFile.fromBridge(
        name: 'a.txt',
        mime: 'text/plain',
        dataBase64: base64.encode([1, 2, 3]),
      );
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      root.deleteSync(recursive: true);
    });
    PlatformIdeWebFileSaver saver(
      TargetPlatform platform, {
      List<String>? opened,
    }) => PlatformIdeWebFileSaver(
      tempDir: () async => root,
      platform: platform,
      openFile: (path) async {
        opened?.add(path);
        return true;
      },
    );

    test('Android: lưu vào Tải về rồi xoá tệp tạm', () async {
      late Map<Object?, Object?> args;
      messenger.setMockMethodCallHandler(channel, (call) async {
        args = call.arguments as Map<Object?, Object?>;
        expect(File(args['path']! as String).readAsBytesSync(), [1, 2, 3]);
        return true;
      });
      expect(
        await saver(
          TargetPlatform.android,
        ).save(file, confirmOpen: () async => fail('không hỏi')),
        IdeWebFileSaveResult.saved,
      );
      expect(args['name'], 'a.txt');
      expect(args['mime'], 'text/plain');
      expect(root.listSync(), isEmpty);
    });

    test('Android cũ: hỏi rồi mở; từ chối thì xoá', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      final opened = <String>[];
      final s = saver(TargetPlatform.android, opened: opened);
      expect(
        await s.save(file, confirmOpen: () async => false),
        IdeWebFileSaveResult.cancelled,
      );
      expect(root.listSync(), isEmpty);
      expect(
        await s.save(file, confirmOpen: () async => true),
        IdeWebFileSaveResult.saved,
      );
      expect(opened, hasLength(1));
      await s.disposeTemp();
      expect(root.listSync(), isEmpty);
    });

    test('iOS: bảng chia sẻ, tệp tạm xoá lúc đóng màn', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'shareFile');
        return null;
      });
      final s = saver(TargetPlatform.iOS);
      await s.save(file, confirmOpen: () async => false);
      expect(root.listSync(), hasLength(1));
      await s.disposeTemp();
      expect(root.listSync(), isEmpty);
    });

    test('lỗi native', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) => throw PlatformException(code: 'BAD_PATH'),
      );
      expect(
        await saver(
          TargetPlatform.android,
        ).save(file, confirmOpen: () async => true),
        IdeWebFileSaveResult.failed,
      );
    });
  });
}
