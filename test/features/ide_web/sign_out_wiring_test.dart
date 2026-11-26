import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_access.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_providers.dart';

import '../auth/support/core2_fakes.dart';
import 'support/fakes.dart';

/// Dây đăng xuất của app (provider thật): IDE nhúng hỏng không cản xoá phiên.
void main() {
  late FakeIdeWebRepository repository;
  late RecordingSessionStateRepository sessions;

  ProviderContainer container({required bool enabled}) {
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(ScriptedAuthRepository()),
        authTokenRepositoryProvider.overrideWithValue(FakeTokenRepository()),
        sessionStateRepositoryProvider.overrideWithValue(sessions),
        ideWebEnabledProvider.overrideWithValue(enabled),
        ideWebRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    repository = FakeIdeWebRepository();
    sessions = RecordingSessionStateRepository();
  });

  test('đăng xuất: báo kết thúc phiên IDE, quên callback, xoá phiên', () async {
    final c = container(enabled: true);
    c.read(ideWebCallbackInboxProvider).deliver(callbackUri());
    expect(await c.read(logoutUseCaseProvider).execute(), isA<Success<void>>());
    expect(repository.ended, 1);
    expect(c.read(ideWebCallbackInboxProvider).take(), isNull);
    expect(sessions.resetGuards, [testGuard]);
  });

  test('máy chủ IDE lỗi: vẫn đăng xuất', () async {
    repository.endError = StateError('mất VPN');
    final c = container(enabled: true);
    expect(await c.read(logoutUseCaseProvider).execute(), isA<Success<void>>());
    expect(repository.ended, 1);
    expect(sessions.resetGuards, [testGuard]);
  });

  test('IDE nhúng đang tắt: không gọi máy chủ, vẫn quên callback', () async {
    final c = container(enabled: false);
    c.read(ideWebCallbackInboxProvider).deliver(callbackUri());
    expect(await c.read(logoutUseCaseProvider).execute(), isA<Success<void>>());
    expect(repository.ended, 0);
    expect(c.read(ideWebCallbackInboxProvider).take(), isNull);
    expect(sessions.resetGuards, [testGuard]);
  });
}
