import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/self_hosted_server_discovery.dart';
import '../../../../core/network/self_hosted_server_discovery_client.dart';
import '../../../../core/result/result.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../../../core/security/server_account_registry.dart';
import '../../application/use_cases/login_use_case.dart';
import '../../application/use_cases/register_use_case.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/oidc_provider.dart';

enum AuthFormMode { login, register }

typedef ServerConnector =
    Future<SelfHostedServerDiscovery> Function(String domain);

final serverConnectorProvider = Provider<ServerConnector>((ref) {
  final discoveryClient = ref.read(selfHostedServerDiscoveryClientProvider);
  return (domain) => _connectToServer(ref, discoveryClient, domain);
});

final loginControllerProvider =
    StateNotifierProvider.autoDispose<LoginController, LoginState>((ref) {
      final activeServer = ref.read(activeServerUriProvider);
      final activeDiscovery = ref.read(activeServerDiscoveryProvider);
      final oidc = ref.read(oidcLoginUseCaseProvider);
      final controller = LoginController(
        initialServer: activeDiscovery == null
            ? ''
            : _serverInputFromUri(activeServer),
        initialDiscovery: activeDiscovery,
        connectToServer: ref.read(serverConnectorProvider),
        login: (command) => ref.read(loginUseCaseProvider).execute(command),
        register: (command) =>
            ref.read(registerUseCaseProvider).execute(command),
        googleLogin: () => ref.read(googleLoginUseCaseProvider).execute(),
        oidcProviders: oidc.providers,
        oidcStart: ({required domain, required providerId}) =>
            oidc.start(domain: domain, providerId: providerId),
        oidcComplete: ({required code, required domain}) =>
            oidc.complete(code: code, domain: domain),
        openExternalUrl: (uri) =>
            ref.read(externalUrlLauncherProvider).open(uri.toString()),
        recentServers: () => ref.read(serverAccountRegistryProvider).list(),
        hasStoredSession: () async {
          final token = await ref
              .read(authTokenRepositoryProvider)
              .readAccessToken();
          return token?.trim().isNotEmpty == true;
        },
      );
      Future<void>.microtask(controller.loadRecentServers);
      if (activeDiscovery?.capabilities.sso == true) {
        Future<void>.microtask(controller.loadOidcProviders);
      }
      return controller;
    });

final class LoginState {
  const LoginState({
    this.mode = AuthFormMode.login,
    this.displayName = '',
    this.email = '',
    this.username = '',
    this.inviteToken = '',
    this.domain = '',
    this.identifier = '',
    this.password = '',
    this.confirmPassword = '',
    this.remember = true,
    this.showPassword = false,
    this.showConfirmPassword = false,
    this.isLoading = false,
    this.isGoogleLoading = false,
    this.oidcProviders = const [],
    this.loadingOidcProviderId,
    this.recentServers = const [],
    this.errorMessage,
    this.succeeded = false,
    this.serverConnected = false,
    this.serverName,
    this.logoUrl,
    this.registrationMode,
  });

  final AuthFormMode mode;
  final String displayName;
  final String email;
  final String username;
  final String inviteToken;
  final String domain;
  final String identifier;
  final String password;
  final String confirmPassword;
  final bool remember;
  final bool showPassword;
  final bool showConfirmPassword;
  final bool isLoading;
  final bool isGoogleLoading;
  final List<OidcProvider> oidcProviders;
  final String? loadingOidcProviderId;
  final List<ServerAccountSummary> recentServers;
  final String? errorMessage;
  final bool succeeded;
  final bool serverConnected;
  final String? serverName;
  final String? logoUrl;
  final String? registrationMode;

  bool get isLogin => mode == AuthFormMode.login;

  bool get canSubmit {
    if (isLoading || !serverConnected) {
      return false;
    }
    if (isLogin) {
      return identifier.trim().isNotEmpty && password.trim().isNotEmpty;
    }
    return displayName.trim().isNotEmpty &&
        email.trim().isNotEmpty &&
        username.trim().isNotEmpty &&
        password.trim().isNotEmpty &&
        confirmPassword.trim().isNotEmpty;
  }

  bool get canConnectServer => !isLoading && domain.trim().isNotEmpty;

  LoginState copyWith({
    AuthFormMode? mode,
    String? displayName,
    String? email,
    String? username,
    String? inviteToken,
    String? domain,
    String? identifier,
    String? password,
    String? confirmPassword,
    bool? remember,
    bool? showPassword,
    bool? showConfirmPassword,
    bool? isLoading,
    bool? isGoogleLoading,
    List<OidcProvider>? oidcProviders,
    String? loadingOidcProviderId,
    bool clearOidcLoading = false,
    List<ServerAccountSummary>? recentServers,
    String? errorMessage,
    bool clearError = false,
    bool? succeeded,
    bool? serverConnected,
    String? serverName,
    String? logoUrl,
    String? registrationMode,
    bool clearServer = false,
  }) {
    return LoginState(
      mode: mode ?? this.mode,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      username: username ?? this.username,
      inviteToken: inviteToken ?? this.inviteToken,
      domain: domain ?? this.domain,
      identifier: identifier ?? this.identifier,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      remember: remember ?? this.remember,
      showPassword: showPassword ?? this.showPassword,
      showConfirmPassword: showConfirmPassword ?? this.showConfirmPassword,
      isLoading: isLoading ?? this.isLoading,
      isGoogleLoading: isGoogleLoading ?? this.isGoogleLoading,
      oidcProviders: oidcProviders ?? this.oidcProviders,
      loadingOidcProviderId: clearOidcLoading
          ? null
          : loadingOidcProviderId ?? this.loadingOidcProviderId,
      recentServers: recentServers ?? this.recentServers,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      succeeded: succeeded ?? this.succeeded,
      serverConnected: serverConnected ?? this.serverConnected,
      serverName: clearServer ? null : serverName ?? this.serverName,
      logoUrl: clearServer ? null : logoUrl ?? this.logoUrl,
      registrationMode: clearServer
          ? null
          : registrationMode ?? this.registrationMode,
    );
  }
}

final class LoginController extends StateNotifier<LoginState> {
  LoginController({
    required String initialServer,
    SelfHostedServerDiscovery? initialDiscovery,
    required Future<SelfHostedServerDiscovery> Function(String domain)
    connectToServer,
    required Future<Result<AuthSession>> Function(LoginCommand command) login,
    required Future<Result<AuthSession>> Function(RegisterCommand command)
    register,
    required Future<Result<AuthSession>> Function() googleLogin,
    required Future<Result<List<OidcProvider>>> Function(String domain)
    oidcProviders,
    required Future<Result<Uri>> Function({
      required String domain,
      required String providerId,
    })
    oidcStart,
    required Future<Result<AuthSession>> Function({
      required String code,
      required String domain,
    })
    oidcComplete,
    required Future<bool> Function(Uri uri) openExternalUrl,
    required Future<List<ServerAccountSummary>> Function() recentServers,
    required Future<bool> Function() hasStoredSession,
  }) : _connectToServer = connectToServer,
       _login = login,
       _register = register,
       _googleLogin = googleLogin,
       _oidcProviders = oidcProviders,
       _oidcStart = oidcStart,
       _oidcComplete = oidcComplete,
       _openExternalUrl = openExternalUrl,
       _recentServers = recentServers,
       _hasStoredSession = hasStoredSession,
       super(
         LoginState(
           domain: initialServer,
           serverConnected: initialDiscovery != null,
           serverName: initialDiscovery?.name,
           logoUrl: initialDiscovery?.logoUrl,
           registrationMode: initialDiscovery?.registrationMode,
         ),
       );

  final Future<SelfHostedServerDiscovery> Function(String domain)
  _connectToServer;
  final Future<Result<AuthSession>> Function(LoginCommand command) _login;
  final Future<Result<AuthSession>> Function(RegisterCommand command) _register;
  final Future<Result<AuthSession>> Function() _googleLogin;
  final Future<Result<List<OidcProvider>>> Function(String domain)
  _oidcProviders;
  final Future<Result<Uri>> Function({
    required String domain,
    required String providerId,
  })
  _oidcStart;
  final Future<Result<AuthSession>> Function({
    required String code,
    required String domain,
  })
  _oidcComplete;
  final Future<bool> Function(Uri uri) _openExternalUrl;
  final Future<List<ServerAccountSummary>> Function() _recentServers;
  final Future<bool> Function() _hasStoredSession;

  void showLogin() => _setMode(AuthFormMode.login);
  void showRegister() => _setMode(AuthFormMode.register);

  void _setMode(AuthFormMode mode) {
    if (state.mode == mode || state.isLoading) {
      return;
    }
    state = state.copyWith(mode: mode, clearError: true, succeeded: false);
  }

  void updateDisplayName(String value) {
    state = state.copyWith(
      displayName: value,
      clearError: true,
      succeeded: false,
    );
  }

  void updateEmail(String value) {
    state = state.copyWith(email: value, clearError: true, succeeded: false);
  }

  void updateUsername(String value) {
    state = state.copyWith(username: value, clearError: true, succeeded: false);
  }

  void updateInviteToken(String value) {
    state = state.copyWith(
      inviteToken: value,
      clearError: true,
      succeeded: false,
    );
  }

  void updateDomain(String value) {
    state = state.copyWith(
      domain: value,
      serverConnected: false,
      oidcProviders: const [],
      clearOidcLoading: true,
      clearError: true,
      succeeded: false,
      clearServer: true,
    );
  }

  Future<void> connectServer() async {
    if (!state.canConnectServer) {
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true, succeeded: false);
    try {
      final server = await _connectToServer(state.domain);
      state = state.copyWith(
        domain: server.apiBaseUri.host,
        isLoading: false,
        serverConnected: true,
        serverName: server.name,
        logoUrl: server.logoUrl,
        registrationMode: server.registrationMode,
      );
      await loadOidcProviders();
      await loadRecentServers();
      if (await _hasStoredSession()) {
        state = state.copyWith(succeeded: true);
      }
    } on Object catch (error) {
      state = state.copyWith(
        isLoading: false,
        serverConnected: false,
        errorMessage: _serverError(error),
        succeeded: false,
        clearServer: true,
        oidcProviders: const [],
        clearOidcLoading: true,
      );
    }
  }

  void changeServer() {
    if (state.isLoading) {
      return;
    }
    state = state.copyWith(
      mode: AuthFormMode.login,
      serverConnected: false,
      oidcProviders: const [],
      clearOidcLoading: true,
      clearError: true,
      succeeded: false,
    );
  }

  Future<void> loadRecentServers() async {
    final servers = await _recentServers();
    state = state.copyWith(recentServers: servers);
  }

  Future<void> selectRecentServer(ServerAccountSummary server) async {
    if (state.isLoading) {
      return;
    }
    updateDomain(server.baseUrl.toString());
    await connectServer();
  }

  void updateIdentifier(String value) {
    state = state.copyWith(
      identifier: value,
      clearError: true,
      succeeded: false,
    );
  }

  void updatePassword(String value) {
    state = state.copyWith(password: value, clearError: true, succeeded: false);
  }

  void updateConfirmPassword(String value) {
    state = state.copyWith(
      confirmPassword: value,
      clearError: true,
      succeeded: false,
    );
  }

  void updateRemember(bool value) {
    state = state.copyWith(remember: value, clearError: true);
  }

  void togglePasswordVisibility() {
    state = state.copyWith(showPassword: !state.showPassword);
  }

  void toggleConfirmPasswordVisibility() {
    state = state.copyWith(showConfirmPassword: !state.showConfirmPassword);
  }

  Future<void> submit() async {
    if (state.isLoading || !state.canSubmit) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true, succeeded: false);
    if (!state.isLogin &&
        state.registrationMode != 'open' &&
        !(state.registrationMode == 'invite_only' &&
            state.inviteToken.trim().isNotEmpty)) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.registrationMode == 'invite_only'
            ? 'Server ${state.serverName} chỉ nhận tài khoản qua lời mời.'
            : 'Server ${state.serverName} đang đóng đăng ký tài khoản.',
      );
      return;
    }
    final result = state.isLogin
        ? await _login(
            LoginCommand(
              identifier: state.identifier,
              password: state.password,
            ),
          )
        : await _register(
            RegisterCommand(
              displayName: state.displayName,
              email: state.email,
              username: state.username,
              password: state.password,
              confirmPassword: state.confirmPassword,
              inviteToken: state.inviteToken,
            ),
          );

    switch (result) {
      case Success<AuthSession>():
        state = state.copyWith(isLoading: false, succeeded: true);
      case FailureResult<AuthSession>(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
          succeeded: false,
        );
    }
  }

  Future<void> loginWithGoogle() async {
    if (state.isLoading || !state.serverConnected) {
      return;
    }

    state = state.copyWith(
      isLoading: true,
      isGoogleLoading: true,
      clearError: true,
      succeeded: false,
    );
    final result = await _googleLogin();
    switch (result) {
      case Success<AuthSession>():
        state = state.copyWith(
          isLoading: false,
          isGoogleLoading: false,
          succeeded: true,
        );
      case FailureResult<AuthSession>(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          isGoogleLoading: false,
          errorMessage: failure.message,
          succeeded: false,
        );
    }
  }

  Future<void> loadOidcProviders() async {
    if (!state.serverConnected || state.domain.trim().isEmpty) {
      return;
    }
    final result = await _oidcProviders(state.domain);
    switch (result) {
      case Success<List<OidcProvider>>(:final value):
        state = state.copyWith(oidcProviders: value);
      case FailureResult<List<OidcProvider>>():
        state = state.copyWith(oidcProviders: const []);
    }
  }

  Future<void> loginWithOidc(OidcProvider provider) async {
    if (state.isLoading || !state.serverConnected) {
      return;
    }
    state = state.copyWith(
      isLoading: true,
      loadingOidcProviderId: provider.id,
      clearError: true,
      succeeded: false,
    );
    final result = await _oidcStart(
      domain: state.domain,
      providerId: provider.id,
    );
    switch (result) {
      case Success<Uri>(:final value):
        final opened = await _openExternalUrl(value);
        state = state.copyWith(
          isLoading: false,
          clearOidcLoading: true,
          errorMessage: opened
              ? null
              : 'Không thể mở trình duyệt để đăng nhập SSO.',
          clearError: opened,
        );
      case FailureResult<Uri>(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          clearOidcLoading: true,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> handleDeepLink(Uri uri) async {
    if (uri.scheme.toLowerCase() != 'webtui' ||
        uri.host.toLowerCase() != 'oidc' ||
        uri.path != '/callback') {
      return;
    }
    final callbackDomain = uri.queryParameters['server']?.toLowerCase() ?? '';
    final activeDomain = _domainHost(state.domain);
    if (!state.serverConnected ||
        callbackDomain.isEmpty ||
        callbackDomain != activeDomain) {
      state = state.copyWith(
        errorMessage: 'Callback SSO không thuộc máy chủ đang kết nối.',
        isLoading: false,
        clearOidcLoading: true,
      );
      return;
    }
    final providerError = uri.queryParameters['error']?.trim();
    if (providerError != null && providerError.isNotEmpty) {
      state = state.copyWith(
        errorMessage: 'Nhà cung cấp SSO đã từ chối đăng nhập.',
        isLoading: false,
        clearOidcLoading: true,
      );
      return;
    }
    final code = uri.queryParameters['oidc_code']?.trim() ?? '';
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearOidcLoading: true,
    );
    final result = await _oidcComplete(code: code, domain: callbackDomain);
    switch (result) {
      case Success<AuthSession>():
        state = state.copyWith(isLoading: false, succeeded: true);
      case FailureResult<AuthSession>(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
          succeeded: false,
        );
    }
  }
}

Future<SelfHostedServerDiscovery> _connectToServer(
  Ref ref,
  SelfHostedServerDiscoveryClient discoveryClient,
  String rawDomain,
) async {
  final discovery = await discoveryClient.discover(rawDomain);
  final activeServer = ref.read(activeServerUriProvider);
  final registry = ref.read(serverAccountRegistryProvider);
  if (activeServer != discovery.apiBaseUri) {
    await registry.stashActiveSession();
    await ref.read(sessionStateRepositoryProvider).resetForLogout();
    await registry.activate(discovery.apiBaseUri);
  }
  await ref
      .read(secureKeyValueStoreProvider)
      .write(SecureStoreKey.instanceBaseUrl, discovery.apiBaseUri.toString());
  await ref
      .read(secureKeyValueStoreProvider)
      .write(SecureStoreKey.instanceWsBaseUrl, discovery.wsBaseUri.toString());
  await ref
      .read(secureKeyValueStoreProvider)
      .write(SecureStoreKey.instanceOrganizationName, discovery.name);
  if (discovery.logoUrl case final logoUrl?) {
    await ref
        .read(secureKeyValueStoreProvider)
        .write(SecureStoreKey.instanceOrganizationLogoUrl, logoUrl);
  } else {
    await ref
        .read(secureKeyValueStoreProvider)
        .delete(SecureStoreKey.instanceOrganizationLogoUrl);
  }
  await ref
      .read(secureKeyValueStoreProvider)
      .write(
        SecureStoreKey.instanceRegistrationMode,
        discovery.registrationMode,
      );
  await ref
      .read(secureKeyValueStoreProvider)
      .write(SecureStoreKey.instanceAppVersion, discovery.appVersion);
  await registry.rememberServer(
    baseUrl: discovery.apiBaseUri,
    wsBaseUrl: discovery.wsBaseUri,
    name: discovery.name,
    logoUrl: discovery.logoUrl,
  );
  ref.read(activeServerUriProvider.notifier).state = discovery.apiBaseUri;
  ref.read(activeServerWsUriProvider.notifier).state = discovery.wsBaseUri;
  ref.read(activeServerDiscoveryProvider.notifier).state = discovery;
  return discovery;
}

String _serverError(Object error) {
  if (error is SelfHostedServerConnectionException) {
    return 'Không thể kết nối tới server. Hãy kiểm tra domain, DNS và TLS.';
  }
  return error
      .toString()
      .replaceFirst(RegExp(r'^(StateError|FormatException):\s*'), '')
      .trim();
}

String _serverInputFromUri(Uri uri) {
  final isLocal =
      uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host.endsWith('.localhost');
  if (isLocal || uri.scheme != 'https' || uri.hasPort) {
    return uri.toString().replaceFirst(RegExp(r'/$'), '');
  }
  return uri.host;
}

String _domainHost(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  return uri?.host.toLowerCase() ?? '';
}
