import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bounded_image_request_pool.dart';
import '../core/network/redirect_safe_file_downloader.dart';
import '../core/platform/app_deep_link_coordinator.dart';
import '../core/privacy/background_privacy.dart';
import '../core/security/instance_scope.dart';
import '../design_system/components/webtui_avatar.dart';
import '../design_system/theme/webtui_theme.dart';
import '../features/auth/application/session_termination.dart';
import '../features/auth/presentation/controllers/auth_flow_providers.dart';
import '../features/auth/presentation/controllers/legal_acceptance_controller.dart';
import '../features/auth/presentation/controllers/login_controller.dart';
import '../features/auth/presentation/screens/device_approval_pending_screen.dart';
import '../features/auth/presentation/widgets/app_lock_gate.dart';
import '../features/auth/presentation/widgets/legal_acceptance_gate.dart';
import '../features/settings/presentation/widgets/mobile_update_gate.dart';
import 'flavor/app_config.dart';
import 'providers/foundation_providers.dart';
import 'router/app_router.dart';

class WebTuiChatApp extends ConsumerStatefulWidget {
  const WebTuiChatApp({super.key});

  @override
  ConsumerState<WebTuiChatApp> createState() => _WebTuiChatAppState();
}

class _WebTuiChatAppState extends ConsumerState<WebTuiChatApp> {
  static const _avatarDownloader = RedirectSafeFileDownloader();
  final BoundedImageRequestPool _imageRequestPool = BoundedImageRequestPool();
  String? _imageCacheNamespace;
  int _imageCacheEpoch = 0;
  StreamSubscription<Uri>? _deepLinkSubscription;
  late final AppDeepLinkCoordinator _deepLinkCoordinator;
  late final Listenable _routerChanges;

  @override
  void initState() {
    super.initState();
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
        path != '/workspaces' &&
        path != deviceApprovalPendingPath;
  }

  void _resumePendingLink() {
    if (!_isAuthenticationReady() ||
        _deepLinkCoordinator.pendingLocation == null) {
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

  /// Phiên bị thu hồi / phải đăng nhập lại: dữ liệu cục bộ đã xoá, về màn
  /// đăng nhập kèm lời giải thích.
  void _onSessionEnded(SessionEndedNotice notice) {
    if (!mounted) return;
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
    _deepLinkSubscription?.cancel();
    _routerChanges.removeListener(_resumePendingLink);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(authAccessTokenProvider, (previous, next) {
      next.whenData((_) => _resumePendingLink());
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

    return MaterialApp.router(
      title: activeDiscovery?.name ?? config.appTitle,
      debugShowCheckedModeBanner: false,
      theme: WebTuiTheme.light(),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.maybeOf(context);
        final scaledChild = mediaQuery == null
            ? child ?? const SizedBox.shrink()
            : MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: mediaQuery.textScaler.clamp(
                    minScaleFactor: 0.85,
                    maxScaleFactor: 1.35,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
        final instanceScope = activeDiscovery?.instanceScope;
        return WebTuiAvatarNetworkScope(
          apiBaseUri: activeServerUri,
          cacheKey: imageCacheNamespace,
          loadBytes: (uri, {required maxBytes, required allowPublicRequest}) =>
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
              organizationName: activeDiscovery?.name ?? 'Ứng dụng chat',
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
    String? bearerToken;
    final isSameOrigin = serverOriginsMatch(uri, apiBaseUri);
    if (!isSameOrigin && !allowPublicRequest) {
      return null;
    }
    if (isSameOrigin && !allowPublicRequest) {
      bearerToken = (await tokenRepository.readAccessTokenIfCurrent(
        guard,
      ))?.trim();
      if (bearerToken == null || bearerToken.isEmpty) {
        return null;
      }
    }
    try {
      final cacheKey =
          '$cacheNamespace|$uri|$maxBytes|$allowPublicRequest|'
          '${_credentialCacheKey(bearerToken)}';
      return await _imageRequestPool.load(
        key: cacheKey,
        maxBytes: maxBytes,
        loader: () => _avatarDownloader.downloadBytes(
          uri: uri,
          maxBytes: maxBytes,
          accept: 'image/*',
          bearerToken: bearerToken,
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
