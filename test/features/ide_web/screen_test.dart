import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/active_call_tracker.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/auth/presentation/widgets/app_lock_gate.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_access.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_bridge_dispatcher.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_callback_inbox.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_device_keys.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_prompter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_providers.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_rate_limiter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_session_cleaner.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_use_cases.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_view.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_device_key.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_failure.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_host_policy.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_launch.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_ports.dart';
import 'package:webtui_chat/features/ide_web/presentation/screens/ide_web_screen.dart';
import 'package:webtui_chat/features/ide_web/presentation/widgets/ide_web_prompt_sheet.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../support/system_font.dart';
import 'support/fakes.dart';

/// Đổi được lúc chạy để giả lập tắt khẩn.
final _enabled = StateProvider<bool>((_) => true);
final _token = StateProvider<String?>((_) => 'token');

final class _Rig {
  final repository = FakeIdeWebRepository(
    launch: Success(IdeWebDirectLaunch(launchId: 'l', entry: testEntry())),
  );
  final pending = FakePendingStore();
  final tokens = FakeTokenRepository();
  final browser = FakeBrowser();
  final files = FakeFileSaver();
  final mic = FakeMicPermission();
  final data = FakeDataCleaner();
  final launcher = FakeLauncher();
  final inbox = IdeWebCallbackInbox();
  final views = <FakeIdeWebView>[];
  final chip = FakeKeyChip();
  final locked = ValueNotifier<bool>(false);
  bool supported = true;
  bool viewThrows = false;
  late final markers = MemoryMarkerStore();
  late final cleaner = IdeWebSessionCleaner(data: data, markers: markers);
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      ideWebEnabledProvider.overrideWith((ref) => ref.watch(_enabled)),
      ideWebHostPolicyProvider.overrideWith(
        (ref) => ref.watch(_enabled) ? IdeWebHostPolicy(testBase) : null,
      ),
      authAccessTokenProvider.overrideWith((ref) async => ref.watch(_token)),
      ideWebRepositoryProvider.overrideWithValue(repository),
      ideWebPendingStoreProvider.overrideWithValue(pending),
      ideWebSessionReaderProvider.overrideWithValue(
        IdeWebSessionReader(
          tokens: tokens,
          currentUserId: () async => 'user-1',
        ),
      ),
      ideWebSessionCleanerProvider.overrideWithValue(cleaner),
      ideWebDeviceKeysProvider.overrideWithValue(
        IdeWebDeviceKeys(chip: chip, store: MemoryKeyStore()),
      ),
      ideWebAppInfoProvider.overrideWithValue(
        const IdeWebAppInfo(
          appVersion: '1',
          platform: 'android',
          osVersion: '15',
        ),
      ),
      ideWebBrowserProvider.overrideWithValue(browser),
      ideWebCallbackInboxProvider.overrideWithValue(inbox),
      ideWebRateLimiterProvider.overrideWithValue(IdeWebRateLimiter()),
      ideWebFileSaverFactoryProvider.overrideWithValue(() => files),
      ideWebMicPermissionProvider.overrideWithValue(mic),
      externalUrlLauncherProvider.overrideWithValue(launcher),
      ideWebViewFactoryProvider.overrideWithValue((_) {
        if (viewThrows) throw UnsupportedError('WebView');
        final view = FakeIdeWebView()..supported = supported;
        views.add(view);
        return view;
      }),
    ],
  );

  /// Lần mở đầu của máy luôn xoá một lần trước khi tạo WebView.
  static const firstOpenClears = 1;

  FakeIdeWebView get view => views.last;

  Future<void> open(
    WidgetTester tester, {
    bool dark = false,
    double textScale = 1,
    bool settle = true,
  }) async {
    addTearDown(container.dispose);
    WebTuiColors.apply(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => WebTuiColors.apply(Brightness.light));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? WebTuiTheme.dark() : WebTuiTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: ValueListenableBuilder<bool>(
              valueListenable: locked,
              builder: (_, value, _) =>
                  AppLockScope(obscured: value, child: child!),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const IdeWebScreen(),
                    ),
                  ),
                  child: const Text('mở'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await pump(tester);
  }

  /// Vòng xoay chạy mãi nên không dùng pumpAndSettle.
  Future<void> pump(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

Finder _key(String value) => find.byKey(Key(value));

void main() {
  setUpAll(loadSystemRobotoForTests);

  testWidgets('mở thẳng: gắn lớp native khi đã nghe sự kiện, rồi mới tải', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.open(tester);
    expect(_key('ide_web_view'), findsOneWidget);
    expect(rig.view.log.take(2), ['attach:true:true', 'open']);
    expect(rig.markers.value!.isUsedBy(testOwner), isTrue);
  });

  group('trạng thái', () {
    testWidgets('trình duyệt: chờ, callback về thì mở', (tester) async {
      final rig = _Rig()
        ..repository.launchResult = Success(testBrowserLaunch());
      await rig.open(tester);
      expect(_key('ide_web_waiting'), findsOneWidget);
      expect(rig.browser.opened.single.fragment, 't=ve');
      rig.inbox.deliver(callbackUri(state: 'la'));
      await rig.pump(tester);
      expect(_key('ide_web_waiting'), findsOneWidget);
      rig.inbox.deliver(callbackUri());
      rig.inbox.deliver(callbackUri());
      await rig.pump(tester);
      expect(_key('ide_web_view'), findsOneWidget);
      expect(rig.repository.completes, hasLength(1));
      expect(rig.views, hasLength(1));
    });

    testWidgets('iOS: callback trả ngay; người dùng huỷ thì về màn trước', (
      tester,
    ) async {
      final rig = _Rig()
        ..repository.launchResult = Success(testBrowserLaunch())
        ..browser.result = IdeWebBrowserCallback(callbackUri());
      await rig.open(tester);
      expect(_key('ide_web_view'), findsOneWidget);
      await tester.tap(_key('ide_web_close'));
      await rig.pump(tester);
      expect(find.text('mở'), findsOneWidget);
      rig.browser.result = const IdeWebBrowserCancelled();
      await tester.tap(find.text('mở'));
      await rig.pump(tester);
      expect(find.text('mở'), findsOneWidget);
      expect(find.byType(IdeWebScreen), findsNothing);
      expect(rig.repository.cancelled, ['launch-1']);
    });

    testWidgets('mở lạnh với callback có sẵn: hoàn tất, không mở lượt mới', (
      tester,
    ) async {
      final rig = _Rig()
        ..pending.value = PendingIdeWebLaunch(
          launchId: 'cu',
          state: testState,
          codeVerifier: 'v',
          scopeId: 'scope-1',
          userId: 'user-1',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        )
        ..inbox.deliver(callbackUri());
      await rig.open(tester);
      expect(_key('ide_web_view'), findsOneWidget);
      expect(rig.repository.launches, isEmpty);
      expect(rig.repository.completes.single['launch_id'], 'cu');
    });

    testWidgets('mở lạnh với callback lạ: mở lượt mới', (tester) async {
      final rig = _Rig()..inbox.deliver(callbackUri(state: 'la'));
      await rig.open(tester);
      expect(rig.repository.launches, hasLength(1));
      expect(_key('ide_web_view'), findsOneWidget);
    });

    testWidgets('chờ trình duyệt quá 10 phút: hết hạn, mở lại lượt mới', (
      tester,
    ) async {
      final rig = _Rig()
        ..repository.launchResult = Success(testBrowserLaunch());
      await rig.open(tester);
      await tester.pump(ideWebLaunchTtl);
      await rig.pump(tester);
      expect(_key('ide_web_expired'), findsOneWidget);
      expect(rig.repository.cancelled, ['launch-1']);
      await tester.tap(_key('ide_web_retry'));
      await rig.pump(tester);
      expect(rig.repository.launches, hasLength(2));
      await tester.tap(_key('ide_web_cancel'));
      await rig.pump(tester);
    });

    testWidgets('TC5: lỗi mạng, Thử lại mở lượt mới', (tester) async {
      final rig = _Rig()
        ..repository.launchResult = failResult(FailureKind.network);
      await rig.open(tester);
      expect(find.text('Chưa kết nối được VPSTTT IDE'), findsOneWidget);
      rig.repository.launchResult = Success(
        IdeWebDirectLaunch(launchId: 'l', entry: testEntry()),
      );
      await tester.tap(find.text('Thử lại'));
      await rig.pump(tester);
      expect(_key('ide_web_view'), findsOneWidget);
      expect(rig.repository.launches, hasLength(2));
      expect(
        rig.repository.launches.map((l) => l.codeChallenge).toSet(),
        hasLength(2),
      );
    });

    testWidgets('không tạo được WebView: báo chưa kết nối được', (
      tester,
    ) async {
      final rig = _Rig()..viewThrows = true;
      await rig.open(tester);
      expect(_key('ide_web_unavailable'), findsOneWidget);
    });

    testWidgets('thiếu cầu nối an toàn chỉ chặn khi máy chủ bật cầu nối', (
      tester,
    ) async {
      final rig = _Rig()..supported = false;
      await rig.open(tester);
      expect(_key('ide_web_too_old'), findsOneWidget);
      expect(rig.view.log, isNot(contains('open')));
      await tester.tap(_key('ide_web_close_action'));
      await rig.pump(tester);
      rig.repository.launchResult = Success(
        IdeWebDirectLaunch(launchId: 'l', entry: testEntry(bridge: false)),
      );
      await tester.tap(find.text('mở'));
      await rig.pump(tester);
      expect(_key('ide_web_view'), findsOneWidget);
    });

    testWidgets('chưa xoá được dữ liệu người trước: không tạo WebView', (
      tester,
    ) async {
      final rig = _Rig()
        ..markers.value = IdeWebDataMarker.usedBy(otherOwner.digest)
        ..data.error = StateError('native');
      await rig.open(tester);
      expect(_key('ide_web_unavailable'), findsOneWidget);
      expect(rig.views, isEmpty);
    });

    testWidgets('màn tự kiểm quyền: tắt thì không gọi máy chủ', (tester) async {
      final rig = _Rig()..container.read(_enabled.notifier).state = false;
      await rig.open(tester);
      expect(_key('ide_web_disabled'), findsOneWidget);
      expect(rig.repository.launches, isEmpty);
    });

    testWidgets('huỷ lúc đang tải: về màn trước, lượt về muộn bị bỏ', (
      tester,
    ) async {
      final rig = _Rig()..repository.launchGate = Completer<void>();
      await rig.open(tester);
      expect(_key('ide_web_loading'), findsOneWidget);
      await tester.tap(_key('ide_web_cancel'));
      await rig.pump(tester);
      rig.repository.launchGate!.complete();
      await rig.pump(tester);
      expect(find.byType(IdeWebScreen), findsNothing);
      expect(rig.views, isEmpty);
      expect(rig.repository.cancelled, ['l']);
    });
  });

  group('khi đang mở', () {
    testWidgets('401 ở cổng: hết hạn, WebView huỷ, dữ liệu xoá', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.view.add(const IdeWebPageFailed(IdeWebFailureKind.expired));
      await rig.pump(tester);
      expect(_key('ide_web_expired'), findsOneWidget);
      expect(rig.view.log.last, 'dispose');
      expect(rig.data.calls, _Rig.firstOpenClears + 1);
    });

    testWidgets('mất mạng: chỉ ngắt người xem, giữ dữ liệu', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.view.add(const IdeWebPageFailed(IdeWebFailureKind.unavailable));
      await rig.pump(tester);
      expect(_key('ide_web_unavailable'), findsOneWidget);
      expect(rig.data.calls, _Rig.firstOpenClears);
      expect(rig.repository.ended, 0);
    });

    testWidgets('tiến trình WebView chết: Mở lại bằng lượt mới', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.view.add(const IdeWebRenderGone());
      await rig.pump(tester);
      await tester.tap(_key('ide_web_retry'));
      await rig.pump(tester);
      expect(rig.views, hasLength(2));
      expect(_key('ide_web_view'), findsOneWidget);
    });

    testWidgets('tắt khẩn: đóng và xoá dữ liệu', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.container.read(_enabled.notifier).state = false;
      await rig.pump(tester);
      expect(_key('ide_web_disabled'), findsOneWidget);
      expect(rig.view.log.last, 'dispose');
      expect(rig.data.calls, _Rig.firstOpenClears + 1);
    });

    testWidgets('TC4: phiên chat kết thúc: màn đóng rồi mới xoá dữ liệu', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      unawaited(rig.cleaner.clearAll());
      await rig.pump(tester);
      expect(find.byType(IdeWebScreen), findsNothing);
      expect(rig.view.log.last, 'dispose');
      expect(rig.data.calls, _Rig.firstOpenClears + 1);
      expect(rig.view.emitted, contains('session.closing'));
    });

    testWidgets('token mất: màn đóng', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.container.read(_token.notifier).state = null;
      // Buộc Riverpod tính lại ngay (bộ lập lịch không chạy trong FakeAsync).
      expect(rig.container.read(authAccessTokenProvider).isLoading, isTrue);
      await rig.pump(tester);
      expect(find.byType(IdeWebScreen), findsNothing);
    });

    testWidgets('đóng màn không kết thúc phiên IDE ở máy chủ', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      await tester.tap(_key('ide_web_close'));
      await rig.pump(tester);
      expect(rig.repository.ended, 0);
      expect(rig.files.disposed, 1);
    });

    testWidgets('nút Quay lại: lùi trong IDE trước, hết thì đóng', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.view.canGoBack = true;
      await tester.binding.handlePopRoute();
      await rig.pump(tester);
      expect(_key('ide_web_view'), findsOneWidget);
      rig.view.canGoBack = false;
      await tester.binding.handlePopRoute();
      await rig.pump(tester);
      expect(find.byType(IdeWebScreen), findsNothing);
    });

    testWidgets('cầu nối: trả đúng replyId và id của trang', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.view.add(
        const IdeWebBridgeMessage(
          replyId: 'n-1',
          json: '{"v":1,"id":"p-1","method":"app.info"}',
          isMainFrame: true,
          origin: testOrigin,
        ),
      );
      await rig.pump(tester);
      final (replyId, payload) = rig.view.replies.single;
      expect(replyId, 'n-1');
      expect(payload['id'], 'p-1');
      expect(payload['ok'], isTrue);
    });

    testWidgets('đổi trang khi đang hỏi: hộp tự đóng, trang nhận cancelled', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      rig.view.add(
        const IdeWebBridgeMessage(
          replyId: 'n-1',
          json:
              '{"v":1,"id":"p-1","method":"device.create","params":{"purpose":"possession","challenge":"$testChallenge"}}',
          isMainFrame: true,
          origin: testOrigin,
        ),
      );
      await rig.pump(tester);
      expect(find.byType(IdeWebPromptSheet), findsOneWidget);
      rig.view.add(const IdeWebPageStarted());
      await rig.pump(tester);
      expect(find.byType(IdeWebPromptSheet), findsNothing);
      expect((rig.view.replies.single.$2['error'] as Map)['code'], 'cancelled');
      expect(rig.chip.keys, isEmpty);
    });

    testWidgets('liên kết ngoài luôn hỏi trước', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      final uri = Uri.parse('https://example.com/x');
      rig.view.add(IdeWebExternalLink(uri));
      rig.view.add(IdeWebExternalLink(uri));
      await rig.pump(tester);
      expect(find.text('example.com'), findsOneWidget);
      await tester.tap(_key('ide_web_prompt_cancel'));
      await rig.pump(tester);
      expect(rig.launcher.opened, isEmpty);
      rig.view.add(IdeWebExternalLink(uri));
      await rig.pump(tester);
      await tester.tap(_key('ide_web_prompt_ok'));
      await rig.pump(tester);
      expect(rig.launcher.opened, ['$uri']);
    });

    Future<bool> grantMic(_Rig rig, WidgetTester tester) async {
      bool? granted;
      rig.view.add(
        IdeWebPermissionAsked(
          microphoneOnly: true,
          mainUrl: '$testOrigin/appchat/',
          resolve: ({required granted}) async {},
        ),
      );
      await rig.pump(tester);
      await tester.tap(_key('ide_web_prompt_ok'));
      await rig.pump(tester);
      rig.view.add(
        IdeWebPermissionAsked(
          microphoneOnly: true,
          mainUrl: '$testOrigin/appchat/',
          resolve: ({required bool granted}) async {},
        ),
      );
      await rig.pump(tester);
      granted = rig.mic.asked >= 2;
      rig.view.add(const IdeWebCaptureChanged(active: true, any: true));
      await rig.pump(tester);
      return granted;
    }

    testWidgets('TC8: mic hỏi một lần, có chỉ báo, dừng khi xuống nền', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      expect(await grantMic(rig, tester), isTrue);
      expect(_key('ide_web_mic_chip'), findsOneWidget);
      // `inactive` (hộp Face ID, thanh thông báo) không dừng.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await rig.pump(tester);
      expect(rig.view.log, isNot(contains('stopCapture')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(rig.view.log, contains('stopCapture'));
      expect(rig.view.emitted, ['app.background']);
      rig.view.add(const IdeWebCaptureChanged(active: false, any: false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      await rig.pump(tester);
      expect(rig.view.emitted, ['app.background', 'app.foreground']);
      expect(_key('ide_web_mic_chip'), findsNothing);
    });

    testWidgets('mic dừng khi có cuộc gọi, âm thanh trong trang dừng', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      await grantMic(rig, tester);
      rig.container.read(activeCallTrackerProvider.notifier).begin('c');
      await rig.pump(tester);
      expect(rig.view.log, containsAll(['stopCapture', 'pauseMedia']));
      rig.view.add(const IdeWebCaptureChanged(active: false, any: false));
      await tester.pump(const Duration(seconds: 2));
      var granted = true;
      rig.view.add(
        IdeWebPermissionAsked(
          microphoneOnly: true,
          mainUrl: '$testOrigin/appchat/',
          resolve: ({required bool granted}) async {},
        ),
      );
      await rig.pump(tester);
      granted = rig.mic.asked > 2;
      expect(granted, isFalse);
    });

    testWidgets('mic dừng khi màn khác che và khi rời màn', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      await grantMic(rig, tester);
      unawaited(
        Navigator.of(
          tester.element(find.byType(IdeWebScreen)),
        ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
      );
      await rig.pump(tester);
      expect(rig.view.log, contains('stopCapture'));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('màn khác đè lên cả hộp hỏi: coi là rời màn, dừng mic', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      await grantMic(rig, tester);
      rig.view.add(IdeWebExternalLink(Uri.parse('https://example.com')));
      await rig.pump(tester);
      expect(find.byType(IdeWebPromptSheet), findsOneWidget);
      expect(rig.view.log, isNot(contains('stopCapture')));
      unawaited(
        Navigator.of(
          tester.element(find.byType(IdeWebScreen)),
        ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
      );
      await rig.pump(tester);
      expect(rig.view.log, contains('stopCapture'));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('liên kết ngoài hỏi có hạn', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      for (var i = 0; i < 5; i++) {
        rig.view.add(IdeWebExternalLink(Uri.parse('https://example.com')));
        await rig.pump(tester);
        await tester.tap(_key('ide_web_prompt_cancel'));
        await rig.pump(tester);
      }
      rig.view.add(IdeWebExternalLink(Uri.parse('https://example.com')));
      await rig.pump(tester);
      expect(find.byType(IdeWebPromptSheet), findsNothing);
      expect(rig.launcher.opened, isEmpty);
    });

    testWidgets('màn khác đang đè lên: không đóng nhầm màn đó', (tester) async {
      final rig = _Rig();
      await rig.open(tester);
      final navigator = Navigator.of(tester.element(find.byType(IdeWebScreen)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('màn cuộc gọi')),
          ),
        ),
      );
      await rig.pump(tester);
      // Trang không được đóng thay người dùng khi đang bị che.
      rig.view.add(
        const IdeWebBridgeMessage(
          replyId: 'r',
          json: '{"v":1,"id":"a","method":"app.close"}',
          isMainFrame: true,
          origin: testOrigin,
        ),
      );
      await rig.pump(tester);
      expect(
        (rig.view.replies.single.$2['error'] as Map<String, dynamic>)['code'],
        'cancelled',
      );
      expect(find.text('màn cuộc gọi'), findsOneWidget);
      // Phiên chat kết thúc: trang đóng ngay, màn IDE đợi tới lượt rồi tự rời.
      unawaited(rig.cleaner.clearAll());
      await rig.pump(tester);
      expect(rig.view.log, contains('dispose'));
      expect(find.text('màn cuộc gọi'), findsOneWidget);
      navigator.pop();
      await rig.pump(tester);
      expect(find.byType(IdeWebScreen), findsNothing);
      expect(find.text('mở'), findsOneWidget);
    });

    testWidgets('đang đóng dở mà đăng xuất: xoá dữ liệu sau khi trang ngừng', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      final calls = rig.data.calls;
      rig.view.disposeGate = Completer<void>();
      await tester.tap(_key('ide_web_close'));
      await rig.pump(tester);
      unawaited(rig.cleaner.clearAll());
      await rig.pump(tester);
      expect(rig.data.calls, calls);
      rig.view.disposeGate!.complete();
      await rig.pump(tester);
      expect(rig.data.calls, calls + 1);
    });

    testWidgets('khoá app: gỡ khung native, dừng mic, đóng hộp hỏi', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.open(tester);
      await grantMic(rig, tester);
      rig.view.add(IdeWebExternalLink(Uri.parse('https://example.com')));
      await rig.pump(tester);
      expect(find.byType(IdeWebPromptSheet), findsOneWidget);
      rig.locked.value = true;
      await rig.pump(tester);
      expect(_key('ide_web_view'), findsNothing);
      expect(find.byType(IdeWebPromptSheet), findsNothing);
      expect(rig.view.log, contains('stopCapture'));
      expect(rig.view.log, isNot(contains('dispose')));
      rig.view.add(const IdeWebCaptureChanged(active: false, any: false));
      await tester.pump(const Duration(seconds: 2));
      rig.locked.value = false;
      await rig.pump(tester);
      expect(_key('ide_web_view'), findsOneWidget);
    });
  });

  group('TC9: 8 trạng thái × sáng / tối × chữ to', () {
    final states = <String, void Function(_Rig)>{
      'ide_web_loading': (rig) => rig.repository.launchGate = Completer<void>(),
      'ide_web_waiting': (rig) =>
          rig.repository.launchResult = Success(testBrowserLaunch()),
      'ide_web_view': (_) {},
      'ide_web_unavailable': (rig) =>
          rig.repository.launchResult = failResult(FailureKind.timeout),
      'ide_web_disabled': (rig) => rig.repository.launchResult = failResult(
        FailureKind.forbidden,
        code: 'IDE_WEB_DISABLED',
      ),
      'ide_web_not_allowed': (rig) => rig.repository.launchResult = failResult(
        FailureKind.forbidden,
        code: 'IDE_WEB_NOT_ALLOWED',
      ),
      'ide_web_expired': (rig) => rig.repository.launchResult = failResult(
        FailureKind.unknown,
        code: 'IDE_WEB_LAUNCH_EXPIRED',
      ),
      'ide_web_too_old': (rig) => rig.supported = false,
    };
    for (final entry in states.entries) {
      for (final dark in [false, true]) {
        for (final english in [false, true]) {
          testWidgets(
            '${entry.key} ${dark ? 'tối' : 'sáng'} ${english ? 'en' : 'vi'}',
            (tester) async {
              tester.view
                ..physicalSize = const Size(320, 568)
                ..devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              if (english) AppStrings.current = const AppStringsEn();
              addTearDown(() => AppStrings.current = const AppStringsVi());
              for (final scale in [1.0, 2.0]) {
                final rig = _Rig();
                entry.value(rig);
                await rig.open(tester, dark: dark, textScale: scale);
                expect(tester.takeException(), isNull);
                expect(_key(entry.key), findsOneWidget);
                expect(find.text('VPSTTT IDE'), findsOneWidget);
                // Mọi nút đủ 48 và chạm tới được (cuộn nếu cần).
                for (final button
                    in find
                        .descendant(
                          of: _key(entry.key),
                          matching: find.byWidgetPredicate(
                            (w) => w is ButtonStyleButton,
                          ),
                        )
                        .evaluate()) {
                  expect(button.size!.height, greaterThanOrEqualTo(48));
                  await tester.ensureVisible(find.byWidget(button.widget));
                  await tester.pump();
                }
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox());
                rig.container.dispose();
                await rig.pump(tester);
              }
            },
          );
        }
      }
    }

    testWidgets('hộp xác nhận không tràn ở chữ to', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final prompt in [
        const IdeWebCreateKeyPrompt(IdeWebKeyPurpose.biometric),
        const IdeWebCreateKeyPrompt(IdeWebKeyPurpose.possession),
        const IdeWebDeleteKeyPrompt(),
        IdeWebSaveFilePrompt(name: 'a' * 120, bytes: 2 * 1024 * 1024),
        IdeWebOpenSavedFilePrompt('b' * 120),
        const IdeWebMicrophonePrompt(),
        IdeWebExternalLinkPrompt(Uri.parse('https://${'c' * 60}.example')),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: WebTuiTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
                textScaler: TextScaler.linear(2),
              ),
              child: IdeWebPromptSheet(prompt: prompt, host: testBase.host),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$prompt');
        // Nút không cắt chữ, đủ lớn, cuộn tới được.
        for (final key in ['ide_web_prompt_ok', 'ide_web_prompt_cancel']) {
          final button = _key(key);
          await tester.ensureVisible(button);
          await tester.pump();
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          final label = tester.renderObject<RenderParagraph>(
            find.descendant(of: button, matching: find.byType(RichText)),
          );
          expect(label.didExceedMaxLines, isFalse, reason: '$prompt $key');
        }
      }
    });

    testWidgets('chữ to: chỉ báo thu còn biểu tượng, tên màn không bị cắt', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig();
      await rig.open(tester, textScale: 1.6);
      rig.view.add(
        IdeWebPermissionAsked(
          microphoneOnly: true,
          mainUrl: '$testOrigin/appchat/',
          resolve: ({required granted}) async {},
        ),
      );
      await rig.pump(tester);
      await tester.tap(_key('ide_web_prompt_ok'));
      await rig.pump(tester);
      rig.view.add(const IdeWebCaptureChanged(active: true, any: true));
      await rig.pump(tester);
      expect(_key('ide_web_mic_chip'), findsOneWidget);
      expect(find.text('Đang thu'), findsNothing);
      expect(find.bySemanticsLabel('Đang thu micro'), findsOneWidget);
      final title = tester.renderObject<RenderParagraph>(
        find.text('VPSTTT IDE'),
      );
      expect(title.didExceedMaxLines, isFalse);
    });
  });
}
