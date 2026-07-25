import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/self_hosted_server_discovery.dart';
import '../../../../core/network/self_hosted_server_discovery_client.dart';
import '../../../../core/result/result.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../application/use_cases/login_use_case.dart';
import '../../application/use_cases/register_use_case.dart';
import '../../domain/entities/auth_session.dart';

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
      return LoginController(
        initialServer: _serverInputFromUri(activeServer),
        connectToServer: ref.read(serverConnectorProvider),
        login: (command) => ref.read(loginUseCaseProvider).execute(command),
        register: (command) =>
            ref.read(registerUseCaseProvider).execute(command),
        googleLogin: () => ref.read(googleLoginUseCaseProvider).execute(),
      );
    });

final class LoginState {
  const LoginState({
    this.mode = AuthFormMode.login,
    this.displayName = '',
    this.email = '',
    this.username = '',
    this.domain = '',
    this.identifier = '',
    this.password = '',
    this.confirmPassword = '',
    this.remember = true,
    this.showPassword = false,
    this.showConfirmPassword = false,
    this.isLoading = false,
    this.isGoogleLoading = false,
    this.errorMessage,
    this.succeeded = false,
    this.serverName,
    this.registrationMode,
  });

  final AuthFormMode mode;
  final String displayName;
  final String email;
  final String username;
  final String domain;
  final String identifier;
  final String password;
  final String confirmPassword;
  final bool remember;
  final bool showPassword;
  final bool showConfirmPassword;
  final bool isLoading;
  final bool isGoogleLoading;
  final String? errorMessage;
  final bool succeeded;
  final String? serverName;
  final String? registrationMode;

  bool get isLogin => mode == AuthFormMode.login;

  bool get canSubmit {
    if (isLoading) {
      return false;
    }
    if (isLogin) {
      return domain.trim().isNotEmpty &&
          identifier.trim().isNotEmpty &&
          password.trim().isNotEmpty;
    }
    return domain.trim().isNotEmpty &&
        displayName.trim().isNotEmpty &&
        email.trim().isNotEmpty &&
        username.trim().isNotEmpty &&
        password.trim().isNotEmpty &&
        confirmPassword.trim().isNotEmpty;
  }

  LoginState copyWith({
    AuthFormMode? mode,
    String? displayName,
    String? email,
    String? username,
    String? domain,
    String? identifier,
    String? password,
    String? confirmPassword,
    bool? remember,
    bool? showPassword,
    bool? showConfirmPassword,
    bool? isLoading,
    bool? isGoogleLoading,
    String? errorMessage,
    bool clearError = false,
    bool? succeeded,
    String? serverName,
    String? registrationMode,
    bool clearServer = false,
  }) {
    return LoginState(
      mode: mode ?? this.mode,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      username: username ?? this.username,
      domain: domain ?? this.domain,
      identifier: identifier ?? this.identifier,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      remember: remember ?? this.remember,
      showPassword: showPassword ?? this.showPassword,
      showConfirmPassword: showConfirmPassword ?? this.showConfirmPassword,
      isLoading: isLoading ?? this.isLoading,
      isGoogleLoading: isGoogleLoading ?? this.isGoogleLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      succeeded: succeeded ?? this.succeeded,
      serverName: clearServer ? null : serverName ?? this.serverName,
      registrationMode: clearServer
          ? null
          : registrationMode ?? this.registrationMode,
    );
  }
}

final class LoginController extends StateNotifier<LoginState> {
  LoginController({
    required String initialServer,
    required Future<SelfHostedServerDiscovery> Function(String domain)
    connectToServer,
    required Future<Result<AuthSession>> Function(LoginCommand command) login,
    required Future<Result<AuthSession>> Function(RegisterCommand command)
    register,
    required Future<Result<AuthSession>> Function() googleLogin,
  }) : _connectToServer = connectToServer,
       _login = login,
       _register = register,
       _googleLogin = googleLogin,
       super(LoginState(domain: initialServer));

  final Future<SelfHostedServerDiscovery> Function(String domain)
  _connectToServer;
  final Future<Result<AuthSession>> Function(LoginCommand command) _login;
  final Future<Result<AuthSession>> Function(RegisterCommand command) _register;
  final Future<Result<AuthSession>> Function() _googleLogin;

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

  void updateDomain(String value) {
    state = state.copyWith(
      domain: value,
      clearError: true,
      succeeded: false,
      clearServer: true,
    );
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
    late final SelfHostedServerDiscovery server;
    try {
      server = await _connectToServer(state.domain);
    } on Object catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _serverError(error),
        succeeded: false,
      );
      return;
    }
    if (!state.isLogin && !server.canRegister) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: server.registrationMode == 'invite_only'
            ? 'Server ${server.name} chỉ nhận tài khoản qua lời mời.'
            : 'Server ${server.name} đang đóng đăng ký tài khoản.',
        serverName: server.name,
        registrationMode: server.registrationMode,
      );
      return;
    }
    state = state.copyWith(
      serverName: server.name,
      registrationMode: server.registrationMode,
    );
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
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      isLoading: true,
      isGoogleLoading: true,
      clearError: true,
      succeeded: false,
    );
    try {
      final server = await _connectToServer(state.domain);
      state = state.copyWith(
        serverName: server.name,
        registrationMode: server.registrationMode,
      );
    } on Object catch (error) {
      state = state.copyWith(
        isLoading: false,
        isGoogleLoading: false,
        errorMessage: _serverError(error),
        succeeded: false,
      );
      return;
    }
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
}

Future<SelfHostedServerDiscovery> _connectToServer(
  Ref ref,
  SelfHostedServerDiscoveryClient discoveryClient,
  String rawDomain,
) async {
  final discovery = await discoveryClient.discover(rawDomain);
  final activeServer = ref.read(activeServerUriProvider);
  if (activeServer != discovery.apiBaseUri) {
    await ref.read(sessionStateRepositoryProvider).resetForLogout();
  }
  await ref
      .read(secureKeyValueStoreProvider)
      .write(SecureStoreKey.instanceBaseUrl, discovery.apiBaseUri.toString());
  await ref
      .read(secureKeyValueStoreProvider)
      .write(SecureStoreKey.instanceWsBaseUrl, discovery.wsBaseUri.toString());
  ref.read(activeServerUriProvider.notifier).state = discovery.apiBaseUri;
  ref.read(activeServerWsUriProvider.notifier).state = discovery.wsBaseUri;
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
