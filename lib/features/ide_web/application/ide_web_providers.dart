import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/flavor/app_config.dart';
import '../../../app/providers/foundation_providers.dart';
import '../data/ide_web_api.dart';
import '../data/ide_web_stores.dart';
import '../data/method_channel_ide_web_browser.dart';
import '../data/method_channel_ide_web_host.dart';
import '../data/method_channel_ide_web_keys.dart';
import '../data/platform_ide_web_file_saver.dart';
import '../data/record_ide_web_mic_permission.dart';
import '../data/webview_flutter_ide_view.dart';
import '../domain/ide_web_host_policy.dart';
import '../domain/ide_web_ports.dart';
import 'ide_web_access.dart';
import 'ide_web_account_use_cases.dart';
import 'ide_web_bridge_dispatcher.dart';
import 'ide_web_callback_inbox.dart';
import 'ide_web_device_keys.dart';
import 'ide_web_rate_limiter.dart';
import 'ide_web_session_cleaner.dart';
import 'ide_web_use_cases.dart';
import 'ide_web_view.dart';

final ideWebRepositoryProvider = Provider<IdeWebRepository>(
  (ref) => IdeWebApi(ref.watch(apiTransportProvider)),
);

final ideWebPendingStoreProvider = Provider<IdeWebPendingStore>(
  (ref) => SecureIdeWebPendingStore(ref.watch(secureKeyValueStoreProvider)),
);

final ideWebDataCleanerProvider = Provider<IdeWebDataCleaner>(
  (_) => const MethodChannelIdeWebHost(),
);

final ideWebSessionCleanerProvider = Provider<IdeWebSessionCleaner>(
  (ref) => IdeWebSessionCleaner(
    data: ref.watch(ideWebDataCleanerProvider),
    markers: SecureIdeWebDataMarkerStore(
      ref.watch(secureKeyValueStoreProvider),
    ),
  ),
);

final ideWebKeyChipProvider = Provider<IdeWebKeyChip>(
  (ref) => MethodChannelIdeWebKeyChip(
    biometric: ref.watch(biometricAuthServiceProvider),
  ),
);

/// Một bộ cho cả app: mọi thao tác khoá chạy lần lượt.
final ideWebDeviceKeysProvider = Provider<IdeWebDeviceKeys>(
  (ref) => IdeWebDeviceKeys(
    chip: ref.watch(ideWebKeyChipProvider),
    store: SecureIdeWebKeyMetadataStore(ref.watch(secureKeyValueStoreProvider)),
  ),
);

final ideWebSessionReaderProvider = Provider<IdeWebSessionReader>(
  (ref) => IdeWebSessionReader(
    tokens: ref.watch(authTokenRepositoryProvider),
    currentUserId: () =>
        ref.read(resolveCurrentUserIdUseCaseProvider).execute(),
  ),
);

final ideWebAppInfoProvider = Provider<IdeWebAppInfo>(
  (ref) => IdeWebAppInfo(
    appVersion: ref.watch(appConfigProvider).appVersion,
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    osVersion: Platform.operatingSystemVersion,
  ),
);

/// Chính sách địa chỉ hiện thời; `null` khi tính năng tắt.
final ideWebHostPolicyProvider = Provider<IdeWebHostPolicy?>((ref) {
  final base = ref.watch(ideWebBaseUriProvider);
  return base == null ? null : IdeWebHostPolicy(base);
});

final startIdeWebUseCaseProvider = Provider<StartIdeWebUseCase>((ref) {
  final app = ref.watch(ideWebAppInfoProvider);
  return StartIdeWebUseCase(
    repository: ref.watch(ideWebRepositoryProvider),
    pending: ref.watch(ideWebPendingStoreProvider),
    sessions: ref.watch(ideWebSessionReaderProvider),
    keys: ref.watch(ideWebDeviceKeysProvider),
    policy: () => ref.read(ideWebHostPolicyProvider),
    platform: app.platform,
    appVersion: app.appVersion,
  );
});

final completeIdeWebUseCaseProvider = Provider<CompleteIdeWebUseCase>(
  (ref) => CompleteIdeWebUseCase(
    repository: ref.watch(ideWebRepositoryProvider),
    pending: ref.watch(ideWebPendingStoreProvider),
    sessions: ref.watch(ideWebSessionReaderProvider),
    policy: () => ref.read(ideWebHostPolicyProvider),
  ),
);

final cancelIdeWebUseCaseProvider = Provider<CancelIdeWebUseCase>(
  (ref) => CancelIdeWebUseCase(
    repository: ref.watch(ideWebRepositoryProvider),
    pending: ref.watch(ideWebPendingStoreProvider),
  ),
);

final endIdeWebSessionUseCaseProvider = Provider<EndIdeWebSessionUseCase>(
  (ref) => EndIdeWebSessionUseCase(ref.watch(ideWebRepositoryProvider)),
);

final dropOtherIdeWebOwnerUseCaseProvider =
    Provider<DropOtherIdeWebOwnerUseCase>(
      (ref) => DropOtherIdeWebOwnerUseCase(
        sessions: ref.watch(ideWebSessionReaderProvider),
        keys: ref.watch(ideWebDeviceKeysProvider),
        cleaner: ref.watch(ideWebSessionCleanerProvider),
      ),
    );

final ideWebCallbackInboxProvider = Provider<IdeWebCallbackInbox>(
  (_) => IdeWebCallbackInbox(),
);

final ideWebBrowserProvider = Provider<IdeWebBrowser>(
  (_) => const MethodChannelIdeWebBrowser(),
);

/// Sống suốt đời app: đóng mở màn không xoá được hạn mức.
final ideWebRateLimiterProvider = Provider<IdeWebRateLimiter>(
  (_) => IdeWebRateLimiter(),
);

final ideWebFileSaverFactoryProvider = Provider<IdeWebFileSaver Function()>(
  (_) => PlatformIdeWebFileSaver.new,
);

final ideWebMicPermissionProvider = Provider<IdeWebMicPermission>(
  (_) => const RecordIdeWebMicPermission(),
);

final ideWebViewFactoryProvider = Provider<IdeWebViewFactory>(
  (_) => WebViewFlutterIdeView.new,
);
