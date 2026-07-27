import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/privacy/background_privacy.dart';
import '../design_system/components/webtui_avatar.dart';
import '../design_system/theme/webtui_theme.dart';
import '../features/settings/presentation/widgets/mobile_update_gate.dart';
import 'flavor/app_config.dart';
import 'providers/foundation_providers.dart';
import 'router/app_router.dart';

class WebTuiChatApp extends ConsumerWidget {
  const WebTuiChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final activeServerUri = ref.watch(activeServerUriProvider);
    final activeDiscovery = ref.watch(activeServerDiscoveryProvider);
    final accessToken = ref.watch(authAccessTokenProvider).valueOrNull?.trim();
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
        final headers = accessToken == null || accessToken.isEmpty
            ? null
            : {'Authorization': 'Bearer $accessToken'};
        return WebTuiAvatarNetworkScope(
          apiBaseUri: activeServerUri,
          headers: headers,
          child: MobileUpdateGate(
            child: PrivacyGuard(
              organizationName: activeDiscovery?.name ?? 'Ứng dụng chat',
              organizationLogoUrl: activeDiscovery?.logoUrl,
              child: scaledChild,
            ),
          ),
        );
      },
    );
  }
}
