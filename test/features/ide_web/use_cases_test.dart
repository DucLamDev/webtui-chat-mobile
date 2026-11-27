import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/oidc_pkce.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_device_keys.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_use_cases.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_host_policy.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_launch.dart';

import 'support/fakes.dart';

final class _Rig {
  final repository = FakeIdeWebRepository();
  final pending = FakePendingStore();
  final tokens = FakeTokenRepository();
  String? userId = 'user-1';
  DateTime now = DateTime.utc(2026, 11, 25, 8);
  IdeWebHostPolicy? policy = IdeWebHostPolicy(testBase, testAuthBase);

  late final sessions = IdeWebSessionReader(
    tokens: tokens,
    currentUserId: () async => userId,
  );
  late final start = StartIdeWebUseCase(
    repository: repository,
    pending: pending,
    sessions: sessions,
    keys: IdeWebDeviceKeys(chip: FakeKeyChip(), store: MemoryKeyStore()),
    policy: () => policy,
    platform: 'android',
    appVersion: '1.0.0',
    clock: () => now,
  );
  late final complete = CompleteIdeWebUseCase(
    repository: repository,
    pending: pending,
    sessions: sessions,
    policy: () => policy,
    clock: () => now,
  );
}

void main() {
  test(
    'mở bằng trình duyệt: PKCE đúng, verifier chỉ nằm trong kho chờ',
    () async {
      final rig = _Rig();
      final result = await rig.start.execute();
      expect(result.valueOrNull, isA<IdeWebStartBrowser>());
      final sent = rig.repository.launches.single.toJson();
      expect(
        sent['code_challenge'],
        oidcPkceChallengeS256(rig.pending.value!.codeVerifier),
      );
      expect('$sent', isNot(contains(rig.pending.value!.codeVerifier)));
      expect('${rig.pending.value}', 'PendingIdeWebLaunch(<redacted>)');
      // Đọc lại đúng từ kho (app bị tắt rồi mở lại).
      final restored = PendingIdeWebLaunch.fromJson(
        rig.pending.value!.toJson(),
      )!;
      expect(restored.codeVerifier, rig.pending.value!.codeVerifier);
    },
  );

  test(
    'browser_url đúng hợp đồng: trang đăng nhập trên tên miền IDE',
    () async {
      final rig = _Rig()
        ..repository.launchResult = Success(
          testBrowserLaunch(
            url: '$testAuthOrigin/appchat/auth/start?flow=abc&x=1',
          ),
        );
      final result = await rig.start.execute();
      expect(
        (result.valueOrNull! as IdeWebStartBrowser).url.host,
        'ide.example.net',
      );
      expect(rig.pending.value!.elevation, isFalse);
    },
  );

  test('lượt đăng nhập trình duyệt: complete xong không giữ lượt', () async {
    final rig = _Rig();
    await rig.start.execute();
    expect(await rig.complete.execute(callbackUri()), isA<IdeWebCompleted>());
    // Máy chủ chỉ nhận complete một lần cho lượt trình duyệt.
    expect(rig.pending.value, isNull);
  });

  test('địa chỉ máy chủ trả sai host / đường thì bỏ lượt, không mở', () async {
    for (final url in [
      // Dạng cũ trên host nhúng đã bỏ.
      '$testOrigin/_appchat/start#t=x',
      '$testOrigin/appchat/auth/?flow=x',
      'https://evil.example/appchat/auth/?flow=x',
      'https://ide.example.net.evil.example/appchat/auth/?flow=x',
      'https://chat.example.com/appchat/auth/?flow=x',
      'http://ide.example.net/appchat/auth/?flow=x',
      'https://ide.example.net:8443/appchat/auth/?flow=x',
      'https://u@ide.example.net/appchat/auth/?flow=x',
      'https://ide.example.net/appchat/auth/?flow=x#f',
      'https://ide.example.net/appchat/auth',
      'https://ide.example.net/appchat/authx/?flow=x',
      'https://ide.example.net/appchat/download/ve',
      'https://ide.example.net/other/appchat/auth/',
      'https://ide.example.net/appchat/auth//x',
      'https://ide.example.net/appchat/auth/%2Fx',
    ]) {
      final rig = _Rig()
        ..repository.launchResult = Success(testBrowserLaunch(url: url));
      final result = await rig.start.execute();
      expect(result.failureOrNull?.code, 'IDE_WEB_UNAVAILABLE', reason: url);
      expect(rig.pending.value, isNull);
      expect(rig.repository.cancelled, ['launch-1']);
    }
  });

  test('tắt tính năng hoặc chưa đăng nhập: không gọi máy chủ', () async {
    final off = _Rig()..policy = null;
    expect((await off.start.execute()).failureOrNull?.code, 'IDE_WEB_DISABLED');
    final signedOut = _Rig()..tokens.guard = null;
    expect((await signedOut.start.execute()).isFailure, isTrue);
    expect(off.repository.launches, isEmpty);
    expect(signedOut.repository.launches, isEmpty);
  });

  test('huỷ / đổi phiên lúc đang gọi: bỏ lượt ở máy chủ', () async {
    for (final change in <void Function(_Rig)>[
      (rig) => rig.start.abandon(),
      (rig) => rig.tokens.guard = const AuthTokenMutationGuard(
        instanceScopeId: 'scope-1',
        generation: 'g2',
      ),
      (rig) => rig.tokens.token = null,
    ]) {
      final rig = _Rig()..repository.launchGate = Completer<void>();
      final future = rig.start.execute();
      await settle();
      change(rig);
      rig.repository.launchGate!.complete();
      expect((await future).failureOrNull?.code, 'IDE_WEB_LAUNCH_CANCELLED');
      expect(rig.repository.cancelled, ['launch-1']);
      expect(rig.pending.value, isNull);
    }
  });

  group('TC3: callback', () {
    Future<_Rig> waiting() async {
      final rig = _Rig();
      await rig.start.execute();
      return rig;
    }

    test('đúng: xoá bản ghi TRƯỚC khi gọi, gửi đúng verifier', () async {
      final rig = await waiting();
      final verifier = rig.pending.value!.codeVerifier;
      var cleared = false;
      rig.repository.onComplete = () => cleared = rig.pending.value == null;
      final done = await rig.complete.execute(callbackUri());
      expect(done, isA<IdeWebCompleted>());
      expect(cleared, isTrue);
      expect(rig.repository.completes.single, {
        'launch_id': 'launch-1',
        'code': 'ma-callback',
        'state': testState,
        'code_verifier': verifier,
      });
    });

    test('lặp (hệ điều hành phát hai lần): chỉ một lần gọi', () async {
      final rig = await waiting();
      final results = await Future.wait([
        rig.complete.execute(callbackUri()),
        rig.complete.execute(callbackUri()),
      ]);
      expect(results.whereType<IdeWebCompleted>(), hasLength(1));
      expect(results.whereType<IdeWebCallbackIgnored>(), hasLength(1));
      expect(rig.repository.completes, hasLength(1));
    });

    test('callback lạ bỏ êm, không xoá lượt đúng', () async {
      final rig = await waiting();
      for (final uri in [
        callbackUri(state: 'khac'),
        callbackUri(state: ''),
        callbackUri(code: ''),
        Uri.parse('webtui://ide-web/other?state=$testState&code=a'),
        Uri.parse('webtui://oidc/callback?state=$testState&code=a'),
        Uri.parse('webtui://ide-web/callback?state=$testState&state=x&code=a'),
        Uri.parse('webtui://ide-web/callback?state=$testState&code=a#x'),
        Uri.parse('https://ide-web/callback?state=$testState&code=a'),
      ]) {
        expect(
          await rig.complete.execute(uri),
          isA<IdeWebCallbackIgnored>(),
          reason: '$uri',
        );
        expect(await rig.complete.matches(uri), isFalse);
      }
      expect(rig.pending.value, isNotNull);
      expect(await rig.complete.matches(callbackUri()), isTrue);
      expect(rig.repository.completes, isEmpty);
    });

    test('quá 10 phút: hết hạn, báo máy chủ bỏ lượt', () async {
      final rig = await waiting();
      rig.now = rig.now.add(ideWebLaunchTtl);
      final done = await rig.complete.execute(callbackUri());
      expect(
        (done as IdeWebCompletionFailed).failure.code,
        'IDE_WEB_LAUNCH_EXPIRED',
      );
      expect(rig.repository.completes, isEmpty);
      expect(rig.repository.cancelled, ['launch-1']);
    });

    test('đổi người / máy chủ: không gửi gì', () async {
      final user = await waiting()
        ..userId = 'user-2';
      final scope = await waiting()
        ..tokens.guard = const AuthTokenMutationGuard(
          instanceScopeId: 'scope-2',
          generation: 'g1',
        );
      for (final rig in [user, scope]) {
        expect(
          await rig.complete.execute(callbackUri()),
          isA<IdeWebCompletionFailed>(),
        );
        expect(rig.repository.completes, isEmpty);
        expect(rig.pending.value, isNull);
      }
    });

    test('app bị tắt rồi mở lại (thế hệ phiên mới): vẫn hoàn tất', () async {
      final rig = await waiting();
      rig.tokens.guard = const AuthTokenMutationGuard(
        instanceScopeId: 'scope-1',
        generation: 'sau-khi-mo-lai',
      );
      expect(await rig.complete.execute(callbackUri()), isA<IdeWebCompleted>());
    });

    test('đăng xuất trong lúc gọi: kết quả bị bỏ', () async {
      final rig = await waiting();
      rig.repository.onComplete = () => rig.tokens.token = null;
      final done = await rig.complete.execute(callbackUri());
      expect(
        (done as IdeWebCompletionFailed).failure.code,
        'IDE_WEB_LAUNCH_CANCELLED',
      );
    });

    test('enter_url lạ bị từ chối', () async {
      final rig = await waiting();
      rig.repository.completeResult = Success(
        testEntry(enterUrl: 'https://evil.example/_appchat/enter'),
      );
      expect(
        await rig.complete.execute(callbackUri()),
        isA<IdeWebCompletionFailed>(),
      );
    });

    test('không xoá được bản ghi thì không gửi mã', () async {
      final rig = await waiting();
      rig.pending.clearError = StateError('kho');
      expect(
        await rig.complete.execute(callbackUri()),
        isA<IdeWebCompletionFailed>(),
      );
      expect(rig.repository.completes, isEmpty);
    });
  });

  group('lượt webview: giữ lượt chờ để nâng quyền', () {
    _Rig webview() => _Rig()
      ..repository.launchResult = Success(
        IdeWebDirectLaunch(
          launchId: 'launch-1',
          state: testState,
          entry: testEntry(),
          launchExpiresAt: DateTime.utc(2026, 11, 25, 8, 10),
        ),
      );

    test('ghi lượt chờ đúng state, verifier, hạn launch_expires_at', () async {
      final rig = webview();
      final result = await rig.start.execute();
      expect(result.valueOrNull, isA<IdeWebStartView>());
      final pending = rig.pending.value!;
      expect(pending.launchId, 'launch-1');
      expect(pending.state, testState);
      expect(pending.scopeId, 'scope-1');
      expect(pending.userId, 'user-1');
      expect(pending.expiresAt, DateTime.utc(2026, 11, 25, 8, 10));
      expect(pending.elevation, isTrue);
      expect(
        rig.repository.launches.single.codeChallenge,
        oidcPkceChallengeS256(pending.codeVerifier),
      );
      final restored = PendingIdeWebLaunch.fromJson(pending.toJson())!;
      expect(restored.elevation, isTrue);
      // Bản ghi cũ (trước bản này) không có trường: là lượt đăng nhập.
      expect(
        PendingIdeWebLaunch.fromJson(
          {...pending.toJson()}..remove('elevation'),
        )!.elevation,
        isFalse,
      );
    });

    test('không có host đăng nhập, cầu nối tắt: mở thẳng WebView', () async {
      final rig = _Rig()
        ..policy = IdeWebHostPolicy(testBase)
        ..repository.launchResult = Success(
          testDirectLaunch(id: 'launch-1', entry: testEntry(bridge: false)),
        );
      final view = (await rig.start.execute()).valueOrNull;
      expect(view, isA<IdeWebStartView>());
      expect((view! as IdeWebStartView).entry.bridgeEnabled, isFalse);
      expect(rig.repository.cancelled, isEmpty);
    });

    test('không có host đăng nhập: lượt browser bị từ chối', () async {
      final rig = _Rig()..policy = IdeWebHostPolicy(testBase);
      expect(
        (await rig.start.execute()).failureOrNull?.code,
        'IDE_WEB_UNAVAILABLE',
      );
      expect(rig.pending.value, isNull);
    });

    test('enter_url lạ: bỏ lượt, không ghi gì', () async {
      final rig = _Rig()
        ..repository.launchResult = Success(
          testDirectLaunch(
            id: 'launch-1',
            entry: testEntry(enterUrl: '$testAuthOrigin/_appchat/enter'),
          ),
        );
      expect(
        (await rig.start.execute()).failureOrNull?.code,
        'IDE_WEB_UNAVAILABLE',
      );
      expect(rig.pending.value, isNull);
      expect(rig.repository.cancelled, ['launch-1']);
    });

    test('huỷ ngay sau khi ghi: xoá lượt chờ', () async {
      final rig = webview();
      rig.pending.onWrite = rig.start.abandon;
      expect(
        (await rig.start.execute()).failureOrNull?.code,
        'IDE_WEB_LAUNCH_CANCELLED',
      );
      expect(rig.pending.value, isNull);
    });

    test('callback nâng quyền: complete rồi giữ lượt cho lần sau', () async {
      final rig = webview();
      await rig.start.execute();
      final verifier = rig.pending.value!.codeVerifier;
      expect(await rig.complete.matches(callbackUri()), isTrue);
      expect(await rig.complete.execute(callbackUri()), isA<IdeWebCompleted>());
      expect(rig.repository.completes.single['code_verifier'], verifier);
      expect(rig.repository.completes.single['launch_id'], 'launch-1');
      // Mã đã dùng: callback lặp bỏ êm, không gọi lại máy chủ.
      expect(await rig.complete.matches(callbackUri()), isFalse);
      expect(
        await rig.complete.execute(callbackUri()),
        isA<IdeWebCallbackIgnored>(),
      );
      expect(rig.repository.completes, hasLength(1));
      // Lần nâng quyền sau (mã mới, cùng lượt) vẫn nhận.
      expect(
        await rig.complete.execute(callbackUri(code: 'ma-2')),
        isA<IdeWebCompleted>(),
      );
      expect(rig.repository.completes, hasLength(2));
      expect(rig.pending.value!.elevation, isTrue);
    });

    test('quá launch_expires_at: hết hạn', () async {
      final rig = webview();
      await rig.start.execute();
      rig.now = DateTime.utc(2026, 11, 25, 8, 10);
      final done = await rig.complete.execute(callbackUri());
      expect(
        (done as IdeWebCompletionFailed).failure.code,
        'IDE_WEB_LAUNCH_EXPIRED',
      );
      expect(rig.repository.completes, isEmpty);
    });

    test('complete lỗi: không giữ lượt', () async {
      final rig = webview();
      await rig.start.execute();
      rig.repository.completeResult = failResult(FailureKind.unauthorized);
      expect(
        await rig.complete.execute(callbackUri()),
        isA<IdeWebCompletionFailed>(),
      );
      expect(rig.pending.value, isNull);
    });

    test('đóng màn: chỉ xoá trên máy, không báo máy chủ huỷ', () async {
      final rig = webview();
      await rig.start.execute();
      await CancelIdeWebUseCase(
        repository: rig.repository,
        pending: rig.pending,
      ).execute();
      expect(rig.pending.value, isNull);
      expect(rig.repository.cancelled, isEmpty);
    });
  });

  test('huỷ lượt chờ', () async {
    final rig = _Rig();
    await rig.start.execute();
    final cancel = CancelIdeWebUseCase(
      repository: rig.repository,
      pending: rig.pending,
    );
    await cancel.execute();
    await cancel.execute();
    expect(rig.repository.cancelled, ['launch-1']);
    expect(rig.pending.value, isNull);
  });

  test('TC4: kết thúc phiên lỗi / treo không cản đăng xuất', () async {
    final hang = FakeIdeWebRepository()..endGate = Completer<void>();
    await EndIdeWebSessionUseCase(
      hang,
      timeout: const Duration(milliseconds: 5),
    ).execute();
    expect(hang.ended, 1);
    await EndIdeWebSessionUseCase(
      FakeIdeWebRepository()..endError = StateError('x'),
    ).execute();
  });

  test('lỗi máy chủ giữ nguyên mã', () async {
    final rig = _Rig()
      ..repository.launchResult = failResult(
        FailureKind.forbidden,
        code: 'IDE_WEB_NOT_ALLOWED',
      );
    expect(
      (await rig.start.execute()).failureOrNull?.code,
      'IDE_WEB_NOT_ALLOWED',
    );
  });
}
