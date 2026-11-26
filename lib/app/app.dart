import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bounded_image_request_pool.dart';
import '../core/network/recent_download_failures.dart';
import '../core/network/redirect_safe_file_downloader.dart';
import '../core/notifications/call_tone_player.dart';
import '../core/platform/app_deep_link_coordinator.dart';
import '../core/privacy/background_privacy.dart';
import '../core/security/instance_scope.dart';
import '../core/storage/cached_image_bytes.dart';
import '../design_system/components/webtui_avatar.dart';
import '../design_system/theme/webtui_theme.dart';
import '../design_system/tokens/webtui_colors.dart';
import '../design_system/tokens/webtui_text_scale.dart';
import '../features/auth/application/session_termination.dart';
import '../features/auth/domain/repositories/auth_token_repository.dart';
import '../features/auth/presentation/controllers/auth_flow_providers.dart';
import '../features/auth/presentation/controllers/legal_acceptance_controller.dart';
import '../features/auth/presentation/controllers/login_controller.dart';
import '../features/auth/presentation/screens/device_approval_pending_screen.dart';
import '../features/auth/presentation/screens/login_mfa_screen.dart';
import '../features/auth/presentation/widgets/app_lock_gate.dart';
import '../features/auth/presentation/widgets/legal_acceptance_gate.dart';
import '../features/conversations/data/files/scoped_attachment_file_store.dart';
import '../features/ide_web/application/ide_web_access.dart';
import '../features/ide_web/application/ide_web_providers.dart';
import '../features/settings/domain/entities/app_settings.dart';
import '../features/settings/presentation/controllers/app_settings_controller.dart';
import '../features/settings/presentation/widgets/mobile_update_gate.dart';
import '../l10n/app_strings.dart';
import 'flavor/app_config.dart';
import 'providers/foundation_providers.dart';
import 'router/app_router.dart';

class WebTuiChatApp extends ConsumerStatefulWidget {
  const WebTuiChatApp({super.key});

  @override
  ConsumerState<WebTuiChatApp> createState() => _WebTuiChatAppState();
}

class _WebTuiChatAppState extends ConsumerState<WebTuiChatApp>
    with WidgetsBindingObserver {
  static const _avatarDownloader = RedirectSafeFileDownloader();
  final BoundedImageRequestPool _imageRequestPool = BoundedImageRequestPool();

  /// Tài khoản của kho đệm ảnh đại diện, nhớ theo phiên (đổi người đăng nhập
  /// thì thế hệ phiên đổi nên tính lại).
  AuthTokenMutationGuard? _mediaCacheAccountGuard;
  String? _mediaCacheAccountKey;
  String? _imageCacheNamespace;
  int _imageCacheEpoch = 0;
  StreamSubscription<Uri>? _deepLinkSubscription;
  late final AppDeepLinkCoordinator _deepLinkCoordinator;
  late final Listenable _routerChanges;
  Brightness _platformBrightness =
      ui.PlatformDispatcher.instance.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platformBrightness = ui.PlatformDispatcher.instance.platformBrightness;
    _deepLinkCoordinator = AppDeepLinkCoordinator(
      loadAccessToken: () => ref.read(authAccessTokenProvider.future),
      loadActiveInstance: () =>
          ref.read(activeServerDiscoveryProvider)?.instanceScope,
      navigate: (location) {
        if (mounted) {
          ref.read(appRouterProvider).go(location);
        }
      },
      isAuthenticationReady: _isAuthenticationReady,
      handleOidcCallback: (uri) =>
          ref.read(loginControllerProvider.notifier).handleDeepLink(uri),
      handleIdeWebCallback: _handleIdeWebCallback,
      onInviteRequiresLogin: (token, serverHost) {
        if (mounted) {
          ref.read(loginPrefillProvider.notifier).state = LoginPrefill(
            inviteToken: token,
            domain: serverHost,
          );
        }
      },
    );
    _routerChanges = ref.read(appRouterProvider).routerDelegate;
    _routerChanges.addListener(_resumePendingLink);
    Future<void>.microtask(_startDeepLinkHandling);
    // Dọn kho tệp đã tải (quá 7 ngày không dùng / vượt 1 GB) sau khi app lên.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => attachmentMediaCache.scheduleTrim(),
    );
  }

  @override
  void didChangePlatformBrightness() {
    final next = ui.PlatformDispatcher.instance.platformBrightness;
    if (!mounted || next == _platformBrightness) return;
    setState(() => _platformBrightness = next);
  }

  /// Màu của app đọc từ [WebTuiColors] nên khi đổi Sáng / Tối phải buộc mọi
  /// widget dựng lại (kể cả widget `const`) mà không làm mất trạng thái
  /// điều hướng.
  void _rebuildAllElements() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
  }

  bool _isAuthenticationReady() {
    if (!mounted) return false;
    final path = ref
        .read(appRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    return path != '/login' &&
        path != '/verify-email' &&
        path != loginMfaPath &&
        path != '/workspaces' &&
        path != deviceApprovalPendingPath;
  }

  void _resumePendingLink() {
    if (!_isAuthenticationReady() || !_deepLinkCoordinator.hasPendingWork) {
      return;
    }
    // Đợi chuyển màn đăng nhập / chọn workspace hoàn tất để không ghi đè
    // đích của lời mời trong cùng một frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isAuthenticationReady()) return;
      final token = ref.read(authAccessTokenProvider).valueOrNull;
      unawaited(_deepLinkCoordinator.onAuthenticationChanged(token));
    });
  }

  /// Người khác (hoặc máy chủ khác) vừa đăng nhập: xoá khoá thiết bị và dữ
  /// liệu WebView VPSTTT IDE của người trước, không đợi tới lúc mở mục IDE.
  Future<void> _dropOtherAccountIdeBinding() async {
    try {
      await ref.read(dropOtherIdeWebOwnerUseCaseProvider).execute();
    } on Object {
      // Lần mở màn IDE sau sẽ dọn.
    }
  }

  /// Kết quả đăng nhập VPSTTT IDE: trao cho màn IDE qua bộ nhớ, không đưa vào
  /// `location`. Callback lạ / lặp bị bỏ êm, không mở màn.
  Future<void> _handleIdeWebCallback(Uri uri) async {
    if (!mounted || !ref.read(ideWebEnabledProvider)) return;
    if (!await ref.read(completeIdeWebUseCaseProvider).matches(uri)) return;
    if (!mounted) return;
    if (ref.read(ideWebCallbackInboxProvider).deliver(uri)) {
      unawaited(ref.read(appRouterProvider).push<void>(ideWebRoutePath));
    }
  }

  /// Phiên bị thu hồi / phải đăng nhập lại: dữ liệu cục bộ đã xoá, về màn
  /// đăng nhập kèm lời giải thích.
  void _onSessionEnded(SessionEndedNotice notice) {
    if (!mounted) return;
    ref.read(ideWebCallbackInboxProvider).clear();
    ref.read(loginNoticeProvider.notifier).state = notice;
    ref.invalidate(authAccessTokenProvider);
    ref.read(appRouterProvider).go('/login');
  }

  /// Máy chủ báo phiên còn chờ duyệt thiết bị: chuyển sang màn chờ duyệt.
  void _onDeviceApprovalPending() {
    if (!mounted) return;
    final router = ref.read(appRouterProvider);
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (path == deviceApprovalPendingPath || path == '/login') return;
    router.go(deviceApprovalPendingPath);
  }

  Future<void> _startDeepLinkHandling() async {
    if (!mounted) {
      return;
    }
    final service = ref.read(nativeDeepLinkServiceProvider);
    _deepLinkSubscription = service.urls.listen(
      (uri) => unawaited(_deepLinkCoordinator.handle(uri)),
    );
    final initialUri = await service.getInitialUri();
    if (initialUri != null && mounted) {
      await _deepLinkCoordinator.handle(initialUri);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSubscription?.cancel();
    _routerChanges.removeListener(_resumePendingLink);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(authAccessTokenProvider, (previous, next) {
      next.whenData((_) => _resumePendingLink());
      final token = next.valueOrNull?.trim() ?? '';
      if (token.isNotEmpty && token != previous?.valueOrNull?.trim()) {
        unawaited(_dropOtherAccountIdeBinding());
      }
    });
    ref.listen<AsyncValue<SessionEndedNotice>>(sessionEndedNoticesProvider, (
      _,
      next,
    ) {
      if (next.valueOrNull case final notice?) _onSessionEnded(notice);
    });
    ref.listen<AsyncValue<int>>(deviceApprovalPendingSignalsProvider, (
      _,
      next,
    ) {
      if (next.hasValue) _onDeviceApprovalPending();
    });
    final config = ref.watch(appConfigProvider);
    final activeServerUri = ref.watch(activeServerUriProvider);
    final activeDiscovery = ref.watch(activeServerDiscoveryProvider);
    final accessToken = ref.watch(authAccessTokenProvider).valueOrNull?.trim();
    final imageIdentity =
        '${activeDiscovery?.instanceScope.storageId ?? ''}:'
        '${identityHashCode(activeDiscovery)}:'
        '${_credentialCacheKey(accessToken)}';
    if (_imageCacheNamespace != imageIdentity) {
      _imageRequestPool.clear();
      _imageCacheNamespace = imageIdentity;
      _imageCacheEpoch++;
    }
    final imageCacheNamespace = '$imageIdentity:epoch$_imageCacheEpoch';
    final legalWorkspaceId = ref.watch(legalAcceptanceWorkspaceScopeProvider);
    final router = ref.watch(appRouterProvider);
    // Đổi ngôn ngữ trong Thiết lập ứng dụng có tác dụng ngay, không cần mở lại.
    // Chưa chọn máy chủ thì chưa có kho cài đặt: dùng tiếng Việt.
    final languageCode = activeDiscovery == null
        ? 'vi'
        : ref.watch(
            appSettingsControllerProvider.select(
              (value) => value.settings.languageCode,
            ),
          );

    // Chữ viết bằng `tr()` đọc ngôn ngữ từ AppStrings.current: đổi ngôn ngữ thì
    // đặt lại rồi dựng lại mọi widget (như đổi Sáng / Tối), không mất màn đang mở.
    final strings = AppStrings.forLanguageCode(languageCode);
    if (AppStrings.current.isEnglish != strings.isEnglish) {
      AppStrings.current = strings;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildAllElements();
      });
    }

    // Chưa chọn máy chủ thì chưa có kho cài đặt: theo Hệ thống.
    final themePreference = activeDiscovery == null
        ? WebTuiThemePreference.system
        : ref.watch(
            appSettingsControllerProvider.select(
              (value) => value.settings.theme,
            ),
          );
    // Cài đặt > Cỡ chữ / Âm lượng có tác dụng ngay trên toàn app (chưa chọn máy
    // chủ thì dùng mặc định).
    final textScale = activeDiscovery == null
        ? appTextScaleDefault
        : ref.watch(
            appSettingsControllerProvider.select(
              (value) => value.settings.textScale,
            ),
          );
    CallTonePlayer.volume = activeDiscovery == null
        ? appSoundVolumeDefault
        : ref.watch(
            appSettingsControllerProvider.select(
              (value) => value.settings.soundVolume,
            ),
          );
    final brightness = switch (themePreference) {
      WebTuiThemePreference.light => Brightness.light,
      WebTuiThemePreference.dark => Brightness.dark,
      WebTuiThemePreference.system => _platformBrightness,
    };
    if (WebTuiColors.brightness != brightness) {
      WebTuiColors.apply(brightness);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildAllElements();
      });
    }
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: brightness,
    );

    return MaterialApp.router(
      title: activeDiscovery?.name ?? config.appTitle,
      debugShowCheckedModeBanner: false,
      theme: WebTuiTheme.light(),
      darkTheme: WebTuiTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      locale: Locale(languageCode),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      routerConfig: router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.maybeOf(context);
        final scaledChild = mediaQuery == null
            ? child ?? const SizedBox.shrink()
            : MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: webTuiAppTextScaler(
                    mediaQuery.textScaler,
                    textScale,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
        final instanceScope = activeDiscovery?.instanceScope;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: WebTuiAvatarNetworkScope(
            apiBaseUri: activeServerUri,
            cacheKey: imageCacheNamespace,
            loadBytes:
                (uri, {required maxBytes, required allowPublicRequest}) =>
                    _loadNetworkImageBytes(
                      uri: uri,
                      maxBytes: maxBytes,
                      allowPublicRequest: allowPublicRequest,
                      cacheNamespace: imageCacheNamespace,
                      apiBaseUri: activeServerUri,
                      expectedInstanceScope: instanceScope,
                    ),
            child: MobileUpdateGate(
              child: PrivacyGuard(
                organizationName:
                    activeDiscovery?.name ?? tr('Ứng dụng chat', 'Chat app'),
                organizationLogoUrl: activeDiscovery?.logoUrl,
                child: AppLockGate(
                  protectSession: accessToken?.isNotEmpty == true,
                  child: LegalAcceptanceGate(
                    accessToken: accessToken,
                    serverUri: activeServerUri,
                    workspaceId: legalWorkspaceId,
                    child: scaledChild,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadNetworkImageBytes({
    required Uri uri,
    required int maxBytes,
    required bool allowPublicRequest,
    required String cacheNamespace,
    required Uri apiBaseUri,
    required InstanceScope? expectedInstanceScope,
  }) async {
    if (expectedInstanceScope == null ||
        !serverOriginsMatch(apiBaseUri, expectedInstanceScope.origin)) {
      return null;
    }
    final tokenRepository = ref.read(authTokenRepositoryProvider);
    final guard = await tokenRepository.captureMutationGuard();
    if (guard == null ||
        guard.instanceScopeId != expectedInstanceScope.storageId) {
      return null;
    }
    final isSameOrigin = serverOriginsMatch(uri, apiBaseUri);
    if (!isSameOrigin && !allowPublicRequest) {
      return null;
    }
    String? bearerToken;
    if (isSameOrigin && !allowPublicRequest) {
      bearerToken = (await tokenRepository.readAccessTokenIfCurrent(
        guard,
      ))?.trim();
      if (bearerToken == null || bearerToken.isEmpty) {
        return null;
      }
    }
    // Thư mục kho đệm theo máy chủ + tài khoản (đăng xuất xoá cùng tệp chat).
    // Mỗi phiên chỉ đọc token một lần để biết tài khoản, không đọc mỗi ảnh.
    final String accountKey;
    final rememberedAccountKey = _mediaCacheAccountGuard == guard
        ? _mediaCacheAccountKey
        : null;
    if (rememberedAccountKey != null) {
      accountKey = rememberedAccountKey;
    } else {
      accountKey = mediaCacheAccountKey(
        accessToken:
            bearerToken ??
            (await tokenRepository.readAccessTokenIfCurrent(guard))?.trim(),
        sessionGeneration: guard.generation,
      );
      _mediaCacheAccountGuard = guard;
      _mediaCacheAccountKey = accountKey;
    }
    try {
      final cacheKey =
          '$cacheNamespace|$uri|$maxBytes|$allowPublicRequest|'
          '${_credentialCacheKey(bearerToken)}';
      return await _imageRequestPool.load(
        key: cacheKey,
        maxBytes: maxBytes,
        // Bộ nhớ trong chỉ giữ ít ảnh và bị xoá mỗi lần đổi token: lớp dưới là
        // kho đệm trên máy (7 ngày) nên không tải lại từ máy chủ. Ảnh vừa bị
        // từ chối (vd. ảnh đại diện kiểu cũ người khác không có quyền tải) thì
        // không hỏi lại máy chủ mỗi lần vẽ lại.
        loader: () async => loadCachedImageBytes(
          cache: attachmentMediaCache,
          failures: mediaDownloadFailures,
          failureKey: '${expectedInstanceScope.storageId}|$accountKey|$uri',
          file: await const ScopedAttachmentFileStore().cacheFileFor(
            instanceScope: expectedInstanceScope,
            accountKey: accountKey,
            purpose: 'avatar',
            key: '$uri|$allowPublicRequest',
          ),
          maxBytes: maxBytes,
          download: () => _avatarDownloader.downloadBytes(
            uri: uri,
            maxBytes: maxBytes,
            accept: 'image/*',
            bearerToken: bearerToken,
            isStillCurrent: () => tokenRepository.isMutationGuardCurrent(guard),
          ),
          // Đã đăng xuất / đổi phiên trong lúc tải thì không ghi vào kho.
          isStillCurrent: () => tokenRepository.isMutationGuardCurrent(guard),
        ),
      );
    } on Object {
      return null;
    }
  }

  String _credentialCacheKey(String? credential) {
    final value = credential?.trim();
    if (value == null || value.isEmpty) return 'public';
    return sha256.convert(utf8.encode(value)).toString();
  }
}
