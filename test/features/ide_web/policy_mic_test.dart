import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_mic_guard.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_prompter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_rate_limiter.dart';
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
    final policy = IdeWebHostPolicy(testBase, testAuthBase);
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
      // Tên miền đăng nhập của IDE: chỉ hai tiền tố, còn lại như trang ngoài.
      'https://ide.example.net/appchat/auth/': IdeWebUrlClass.authFlow,
      'https://IDE.example.net:443/appchat/auth/?flow=x':
          IdeWebUrlClass.authFlow,
      'https://ide.example.net/appchat/auth/pin?flow=a/b..c':
          IdeWebUrlClass.authFlow,
      'https://ide.example.net/appchat/download/ve-1': IdeWebUrlClass.download,
      'https://ide.example.net/appchat/download/a.b_c~d-e':
          IdeWebUrlClass.download,
      'https://ide.example.net/': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/authx/': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/downloads/x': IdeWebUrlClass.external,
      'https://ide.example.net/x/appchat/auth/': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth/#x': IdeWebUrlClass.external,
      'https://ide.example.net:8443/appchat/auth/': IdeWebUrlClass.external,
      'https://ide.example.net.evil.example/appchat/auth/':
          IdeWebUrlClass.external,
      'https://evil.example/appchat/auth/': IdeWebUrlClass.external,
      'https://chat.example.com/appchat/auth/': IdeWebUrlClass.external,
      'https://u@ide.example.net/appchat/auth/': IdeWebUrlClass.blocked,
      'https://ide.example.net@evil.example/appchat/auth/':
          IdeWebUrlClass.blocked,
      'http://ide.example.net/appchat/auth/': IdeWebUrlClass.blocked,
      // Đường dẫn độc hại: `Uri` gỡ `..` nên phải xét chuỗi gốc.
      'https://ide.example.net/appchat/auth/../download/x':
          IdeWebUrlClass.external,
      'https://ide.example.net/appchat/download/../auth/':
          IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth/./x': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth//x': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth/%2e%2e/x': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth/%2Fx': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/download/%41': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth/a\\b': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/auth/a b': IdeWebUrlClass.external,
      'https://ide.example.net/appchat/%61uth/': IdeWebUrlClass.external,
    };
    table.forEach(
      (url, kind) => expect(policy.classifyText(url), kind, reason: url),
    );
    expect(policy.classifyText(null), IdeWebUrlClass.blocked);
  });

  test(
    'không có host đăng nhập: không có lớp authFlow, tải tệp ở host nhúng',
    () {
      final policy = IdeWebHostPolicy(testBase);
      expect(policy.authHost, isNull);
      expect(policy.authOrigin, isNull);
      const table = {
        'https://ide.chat.example.com/appchat/': IdeWebUrlClass.internal,
        'https://ide.chat.example.com/appchat/auth/': IdeWebUrlClass.internal,
        'https://ide.chat.example.com/appchat/download/ve-1':
            IdeWebUrlClass.download,
        'https://IDE.chat.example.com:443/appchat/download/a.b':
            IdeWebUrlClass.download,
        'https://ide.chat.example.com/appchat/download/':
            IdeWebUrlClass.download,
        'https://ide.chat.example.com/appchat/downloads/x':
            IdeWebUrlClass.internal,
        'https://ide.chat.example.com/appchat/download/../x':
            IdeWebUrlClass.internal,
        'https://ide.chat.example.com/appchat/download/%41':
            IdeWebUrlClass.internal,
        'https://ide.chat.example.com/appchat/download/x#f':
            IdeWebUrlClass.internal,
        'https://ide.chat.example.com:8443/appchat/download/x':
            IdeWebUrlClass.blocked,
        'https://u@ide.chat.example.com/appchat/download/x':
            IdeWebUrlClass.blocked,
        'https://ide.example.net/appchat/auth/': IdeWebUrlClass.external,
        'https://ide.example.net/appchat/download/x': IdeWebUrlClass.external,
      };
      table.forEach(
        (url, kind) => expect(policy.classifyText(url), kind, reason: url),
      );
      IdeWebNavigation go(String url, {bool main = true}) => policy.navigation(
        url: url,
        isMainFrame: main,
        blankExpected: false,
        newWindowAsSubframe: false,
      );
      expect(
        go('$testOrigin/appchat/download/ve-1'),
        IdeWebNavigation.openDownload,
      );
      expect(go('$testOrigin/appchat/'), IdeWebNavigation.allow);
      expect(
        go('$testOrigin/appchat/download/ve-1', main: false),
        IdeWebNavigation.block,
      );
      expect(go('$testAuthOrigin/appchat/auth/'), IdeWebNavigation.askExternal);
      expect(
        policy.isBrowserUrl(Uri.parse('$testAuthOrigin/appchat/auth/')),
        isFalse,
      );
      expect(
        policy.isEnterUrl(Uri.parse('$testOrigin/_appchat/enter')),
        isTrue,
      );
    },
  );

  test('điều hướng: trong IDE cho đi, ngoài hỏi, còn lại chặn', () {
    final policy = IdeWebHostPolicy(testBase, testAuthBase);
    IdeWebNavigation go(
      String url, {
      bool main = true,
      bool blank = false,
      bool ios = false,
    }) => policy.navigation(
      url: url,
      isMainFrame: main,
      blankExpected: blank,
      newWindowAsSubframe: ios,
    );
    for (final ios in [false, true]) {
      expect(go('$testOrigin/appchat/', ios: ios), IdeWebNavigation.allow);
      expect(
        go('$testOrigin/appchat/', main: false, ios: ios),
        IdeWebNavigation.allow,
      );
      expect(go('https://x.example/', ios: ios), IdeWebNavigation.askExternal);
      for (final url in [
        'webtui://x',
        'javascript:1',
        'file:///x',
        'http://x',
      ]) {
        expect(go(url, ios: ios), IdeWebNavigation.block);
        expect(go(url, main: false, ios: ios), IdeWebNavigation.block);
      }
      expect(go('about:blank', ios: ios), IdeWebNavigation.block);
      expect(go('about:blank', blank: true, ios: ios), IdeWebNavigation.allow);
      expect(
        go('about:blank', main: false, blank: true, ios: ios),
        IdeWebNavigation.block,
      );
    }
    // Liên kết `target=_blank` trên iOS không có khung đích.
    expect(
      go('https://x.example/', main: false, ios: true),
      IdeWebNavigation.askExternal,
    );
    expect(go('https://x.example/', main: false), IdeWebNavigation.block);
  });

  test('điều hướng tới trang đăng nhập / tải tệp IDE: mở trình duyệt', () {
    final policy = IdeWebHostPolicy(testBase, testAuthBase);
    IdeWebNavigation go(String url, {bool main = true, bool ios = false}) =>
        policy.navigation(
          url: url,
          isMainFrame: main,
          blankExpected: false,
          newWindowAsSubframe: ios,
        );
    const auth = '$testAuthOrigin/appchat/auth/?flow=x';
    const download = '$testAuthOrigin/appchat/download/ve';
    for (final ios in [false, true]) {
      expect(go(auth, ios: ios), IdeWebNavigation.openAuth);
      expect(go(download, ios: ios), IdeWebNavigation.openDownload);
      expect(
        go('$testAuthOrigin/appchat/', ios: ios),
        IdeWebNavigation.askExternal,
      );
      expect(
        go('$testAuthOrigin/appchat/auth/../download/x', ios: ios),
        IdeWebNavigation.askExternal,
      );
    }
    // Khung phụ vẫn chặn; `target=_blank` trên iOS như khung chính.
    expect(go(auth, main: false), IdeWebNavigation.block);
    expect(go(download, main: false), IdeWebNavigation.block);
    expect(go(auth, main: false, ios: true), IdeWebNavigation.openAuth);
    expect(go(download, main: false, ios: true), IdeWebNavigation.openDownload);
  });

  test('browser_url: đúng tên miền đăng nhập, tiền tố, không fragment', () {
    final policy = IdeWebHostPolicy(testBase, testAuthBase);
    expect(policy.authOrigin, testAuthOrigin);
    for (final url in [
      '$testAuthOrigin/appchat/auth/?flow=x',
      '$testAuthOrigin/appchat/auth/start',
    ]) {
      expect(policy.isBrowserUrl(Uri.parse(url)), isTrue, reason: url);
    }
    for (final url in [
      '$testOrigin/_appchat/start#t=x',
      '$testOrigin/appchat/auth/?flow=x',
      '$testAuthOrigin/appchat/auth/?flow=x#f',
      '$testAuthOrigin/appchat/download/x',
      '$testAuthOrigin:8443/appchat/auth/',
      'https://u@ide.example.net/appchat/auth/',
      'http://ide.example.net/appchat/auth/',
      '$testAuthOrigin/appchat/auth//x',
    ]) {
      expect(policy.isBrowserUrl(Uri.parse(url)), isFalse, reason: url);
    }
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
        policy: IdeWebHostPolicy(testBase, testAuthBase),
        prompter: prompter,
        permission: permission,
        limiter: IdeWebRateLimiter(clock: () => now),
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
      mic.onCaptureChanged(active: true, any: true);
      expect(mic.capturing.value, isTrue);
      final stop = mic.stop();
      mic.onCaptureChanged(active: false, any: false);
      await stop;
      expect(view.log, ['stopCapture']);
      expect(mic.capturing.value, isFalse);
    });

    test(
      'dừng: vẫn thu thì tải trang trống, quay lại mở lại trang chính',
      () async {
        await ask();
        mic.onCaptureChanged(active: true, any: true);
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
        mic.onCaptureChanged(active: true, any: true);
        expect(mic.capturing.value, isFalse);
        await ask();
        now = now.add(const Duration(minutes: 1));
        status = inCall;
        view.capture = true;
        mic.onCaptureChanged(active: true, any: true);
        await settle();
        expect(mic.capturing.value, isFalse);
        expect(view.log, ['stopCapture']);
      },
    );

    test('quay lại trước khi hết hạn chờ: không tải trang trống', () async {
      await ask();
      mic.onCaptureChanged(active: true, any: true);
      view.capture = true;
      status = inCall;
      final stop = mic.stop();
      status = ok;
      mic.onCaptureChanged(active: true, any: true);
      await stop;
      expect(view.log, ['stopCapture']);
      expect(mic.blanked, isFalse);
      expect(mic.capturing.value, isTrue);
    });

    test(
      'quay lại đúng lúc đang tải trang trống: tự mở lại trang chính',
      () async {
        await ask();
        mic.onCaptureChanged(active: true, any: true);
        view.capture = true;
        status = inCall;
        view.onBlank = () => status = ok;
        await mic.stop();
        expect(view.log, ['stopCapture', 'blank', 'home']);
        expect(mic.blanked, isFalse);
      },
    );

    test(
      'trang lách lệnh dừng, hệ điều hành bịt tiếng lúc ở nền: vẫn bị cắt',
      () async {
        await ask();
        mic.onCaptureChanged(active: true, any: true);
        view.capture = true;
        status = inCall;
        // Xuống nền: hệ điều hành bịt tiếng nhưng luồng thu vẫn mở.
        mic.onCaptureChanged(active: false, any: true);
        expect(mic.capturing.value, isFalse);
        await mic.stop();
        expect(view.log, contains('blank'));
      },
    );

    test(
      'bịt tiếng rồi có tiếng lại lúc lớp khoá che: cắt, không chỉ xin dừng',
      () async {
        await ask();
        mic.onCaptureChanged(active: true, any: true);
        now = now.add(const Duration(minutes: 5));
        mic.onCaptureChanged(active: false, any: true);
        status = inCall;
        view.capture = true;
        mic.onCaptureChanged(active: true, any: true);
        await settle();
        expect(view.log, ['stopCapture', 'blank']);
      },
    );

    test('hộp hỏi micro có hạn, quá hạn thì từ chối lặng', () async {
      prompter.answer = false;
      for (var i = 0; i < 8; i++) {
        expect(await ask(), isFalse);
      }
      expect(prompter.prompts, hasLength(5));
      now = now.add(const Duration(minutes: 1));
      prompter.answer = true;
      expect(await ask(), isTrue);
    });

    test('vừa cấp xong thì màn bị che: dừng thật', () async {
      await ask();
      status = inCall;
      view.capture = true;
      mic.onCaptureChanged(active: true, any: true);
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
          'captureState' => {'active': false, 'any': true},
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
      expect(await channel.captureOpen(), isTrue);
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

    test('màn cũ ngừng nghe muộn không tắt sự kiện của màn mới', () async {
      const events = EventChannel('webtui/ide_web_host/events');
      MockStreamHandlerEventSink? sink;
      var cancels = 0;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, value) => sink = value,
          onCancel: (_) {
            cancels++;
            sink = null;
          },
        ),
      );
      addTearDown(() => messenger.setMockStreamHandler(events, null));
      const channel = MethodChannelIdeWebHost();
      final old = channel.events(1).listen((_) {});
      await settle();
      final received = <IdeWebViewEvent>[];
      final fresh = channel.events(2).listen(received.add);
      await settle();
      await old.cancel();
      await settle();
      expect(cancels, 0);
      sink!.success({'type': 'render_gone'});
      await settle();
      expect(received.single, isA<IdeWebRenderGone>());
      await fresh.cancel();
      await settle();
      expect(cancels, 1);
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
      List<bool> capture(Map<String, Object?> value) {
        final event =
            parseIdeWebHostEvent({'type': 'capture', ...value}, 3)!
                as IdeWebCaptureChanged;
        return [event.active, event.any];
      }

      expect(capture({'active': true}), [true, true]);
      expect(capture({'active': false, 'any': true}), [false, true]);
      expect(capture({'active': false, 'any': false}), [false, false]);
      expect(
        parseIdeWebHostEvent({'type': 'render_gone'}, 3),
        isA<IdeWebRenderGone>(),
      );
      expect(parseIdeWebHostEvent({'type': 'la'}, 3), isNull);
      expect(parseIdeWebHostEvent('x', 3), isNull);
    });

    test('ide_web_auth', () async {
      const browser = MethodChannelIdeWebBrowser();
      final url = Uri.parse('$testAuthOrigin/appchat/auth/?flow=x');
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
