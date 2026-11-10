import 'dart:async';

import '../security/instance_scope.dart';

sealed class AppDeepLinkIntent {
  const AppDeepLinkIntent();
}

final class AppNavigationDeepLink extends AppDeepLinkIntent {
  const AppNavigationDeepLink(this.location);

  final String location;
}

final class AppOidcCallbackDeepLink extends AppDeepLinkIntent {
  const AppOidcCallbackDeepLink(this.uri);

  final Uri uri;
}

/// Lời mời vào workspace `/invite/<token>` (Lõi 2.5).
final class AppInviteDeepLink extends AppDeepLinkIntent {
  const AppInviteDeepLink({required this.token, required this.host});

  final String token;

  /// Máy chủ của lời mời (dùng để điền sẵn khi app chưa kết nối máy chủ nào).
  final String host;

  String get location => '/invite/$token';
}

/// Đường dẫn universal link duy nhất app được xác minh (Android / iOS).
const _publisherHost = 'chat.vpsttt.com';

final _inviteTokenPattern = RegExp(r'^[A-Za-z0-9_-]{8,256}$');

AppDeepLinkIntent? parseAppDeepLink(
  Uri uri, {
  required InstanceScope? activeInstance,
}) {
  if (_isOidcCallback(uri)) {
    return AppOidcCallbackDeepLink(uri);
  }
  final invite = _parseInvite(uri, activeInstance);
  if (invite != null) {
    return invite;
  }
  if (activeInstance == null ||
      !_isTrustedNavigationOrigin(uri, activeInstance) ||
      uri.hasFragment) {
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.length == 1 && segments.first == 'conversations') {
    return const AppNavigationDeepLink('/');
  }
  if (segments.length == 2 && segments.first == 'conversations') {
    final channelId = _safeIdentifier(segments[1]);
    if (channelId == null) {
      return null;
    }
    final query = <String, String>{};
    _copyQuery(uri, query, 'workspaceId', const [
      'workspaceId',
      'workspace_id',
    ]);
    _copyQuery(uri, query, 'messageId', const ['messageId', 'message_id']);
    return AppNavigationDeepLink(
      Uri(
        pathSegments: ['', 'conversations', channelId],
        queryParameters: query.isEmpty ? null : query,
      ).toString(),
    );
  }
  if (segments.length == 1 && segments.first == 'notifications') {
    final query = <String, String>{};
    _copyQuery(uri, query, 'workspaceId', const [
      'workspaceId',
      'workspace_id',
    ]);
    return AppNavigationDeepLink(
      Uri(
        pathSegments: const ['', 'notifications'],
        queryParameters: query.isEmpty ? null : query,
      ).toString(),
    );
  }
  return null;
}

/// Lời mời: `https://chat.vpsttt.com/invite/<token>` (cũng nhận khi app chưa
/// kết nối máy chủ nào) hoặc `webtui://chat/invite/<token>?instance_id=...`
/// (bắt buộc đúng máy chủ đang dùng). Token chỉ gồm `[A-Za-z0-9_-]`.
AppInviteDeepLink? _parseInvite(Uri uri, InstanceScope? activeInstance) {
  final segments = uri.pathSegments;
  if (segments.length != 2 ||
      segments.first != 'invite' ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final token = segments[1].trim();
  if (!_inviteTokenPattern.hasMatch(token)) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') {
    final host = uri.host.toLowerCase();
    if (host != _publisherHost || uri.port != 443) {
      return null;
    }
    if (activeInstance != null &&
        !_isTrustedNavigationOrigin(uri, activeInstance)) {
      return null;
    }
    return AppInviteDeepLink(token: token, host: host);
  }
  if (activeInstance != null &&
      _isTrustedNavigationOrigin(uri, activeInstance)) {
    return AppInviteDeepLink(token: token, host: activeInstance.origin.host);
  }
  return null;
}

final class AppDeepLinkCoordinator {
  AppDeepLinkCoordinator({
    required Future<String?> Function() loadAccessToken,
    required InstanceScope? Function() loadActiveInstance,
    required void Function(String location) navigate,
    required Future<void> Function(Uri uri) handleOidcCallback,
    void Function(String inviteToken, String? serverHost)?
    onInviteRequiresLogin,
    bool Function()? isAuthenticationReady,
  }) : _loadAccessToken = loadAccessToken,
       _loadActiveInstance = loadActiveInstance,
       _navigate = navigate,
       _handleOidcCallback = handleOidcCallback,
       _onInviteRequiresLogin = onInviteRequiresLogin,
       _isAuthenticationReady = isAuthenticationReady ?? _alwaysReady;

  static bool _alwaysReady() => true;
  final bool Function() _isAuthenticationReady;
  final Future<String?> Function() _loadAccessToken;
  final InstanceScope? Function() _loadActiveInstance;
  final void Function(String location) _navigate;
  final Future<void> Function(Uri uri) _handleOidcCallback;
  final void Function(String inviteToken, String? serverHost)?
  _onInviteRequiresLogin;
  String? _pendingLocation;
  String? _pendingInstanceScopeId;

  /// Đích chờ khi app chưa kết nối máy chủ (lời mời): khớp theo host.
  String? _pendingHost;
  int _navigationGeneration = 0;

  String? get pendingLocation => _pendingLocation;

  Future<void> handle(Uri uri) async {
    final activeInstance = _loadActiveInstance();
    final intent = parseAppDeepLink(uri, activeInstance: activeInstance);
    switch (intent) {
      case AppOidcCallbackDeepLink(:final uri):
        await _handleOidcCallback(uri);
        return;
      case AppNavigationDeepLink(:final location):
        final hasToken = await _hasToken();
        if (hasToken == null) {
          return;
        }
        if (!hasToken) {
          _keepPending(location, activeInstance!.storageId, null);
          _navigate('/login');
          return;
        }
        if (!_isAuthenticationReady()) {
          _keepPending(location, activeInstance!.storageId, null);
          return;
        }
        _clearPending();
        _navigate(location);
      case AppInviteDeepLink():
        final hasToken = activeInstance == null ? false : await _hasToken();
        if (hasToken == null) {
          return;
        }
        if (hasToken && !_isAuthenticationReady()) {
          _keepPending(intent.location, activeInstance.storageId, null);
          return;
        }
        if (hasToken) {
          _clearPending();
          _navigate(intent.location);
          return;
        }
        // Giữ đích qua bước đăng nhập / đăng ký (kèm mã mời).
        _keepPending(
          intent.location,
          activeInstance?.storageId,
          activeInstance == null ? intent.host : null,
        );
        _onInviteRequiresLogin?.call(
          intent.token,
          activeInstance == null ? intent.host : null,
        );
        _navigate('/login');
      case null:
        return;
    }
  }

  /// null khi có link mới hơn đến trong lúc chờ (link này bỏ).
  Future<bool?> _hasToken() async {
    final generation = ++_navigationGeneration;
    String? token;
    try {
      token = await _loadAccessToken();
    } on Object {
      token = null;
    }
    if (generation != _navigationGeneration) {
      return null;
    }
    return token?.trim().isNotEmpty == true;
  }

  void _keepPending(String location, String? scopeId, String? host) {
    _pendingLocation = location;
    _pendingInstanceScopeId = scopeId;
    _pendingHost = host;
  }

  void _clearPending() {
    _pendingLocation = null;
    _pendingInstanceScopeId = null;
    _pendingHost = null;
  }

  Future<void> onAuthenticationChanged(String? accessToken) async {
    if (accessToken?.trim().isNotEmpty != true || !_isAuthenticationReady()) {
      return;
    }
    final location = _pendingLocation;
    final pendingInstanceScopeId = _pendingInstanceScopeId;
    final pendingHost = _pendingHost;
    final activeInstance = _loadActiveInstance();
    final matchesScope =
        pendingInstanceScopeId != null &&
        activeInstance?.storageId == pendingInstanceScopeId;
    final matchesHost =
        pendingInstanceScopeId == null &&
        pendingHost != null &&
        activeInstance != null &&
        activeInstance.origin.scheme == 'https' &&
        activeInstance.origin.host == pendingHost;
    _clearPending();
    if (location == null || !(matchesScope || matchesHost)) {
      return;
    }
    _navigationGeneration++;
    _navigate(location);
  }
}

bool _isOidcCallback(Uri uri) {
  return uri.scheme.toLowerCase() == 'webtui' &&
      uri.host.toLowerCase() == 'oidc' &&
      uri.userInfo.isEmpty &&
      uri.path == '/callback' &&
      !uri.hasFragment;
}

bool _isTrustedNavigationOrigin(Uri uri, InstanceScope activeInstance) {
  if (uri.userInfo.isNotEmpty) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') {
    return uri.host.toLowerCase() == _publisherHost &&
        uri.port == 443 &&
        activeInstance.origin.scheme == 'https' &&
        activeInstance.origin.host == uri.host.toLowerCase() &&
        activeInstance.origin.port == uri.port;
  }
  return scheme == 'webtui' &&
      uri.host.toLowerCase() == 'chat' &&
      !uri.hasPort &&
      uri.queryParameters['instance_id']?.trim().toLowerCase() ==
          activeInstance.instanceId;
}

String? _safeIdentifier(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean.length > 256 || clean == '.' || clean == '..') {
    return null;
  }
  if (clean.contains('/') || clean.contains(r'\')) {
    return null;
  }
  for (final codeUnit in clean.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      return null;
    }
  }
  return clean;
}

void _copyQuery(
  Uri source,
  Map<String, String> target,
  String canonicalKey,
  List<String> sourceKeys,
) {
  for (final key in sourceKeys) {
    final value = source.queryParameters[key]?.trim();
    if (value != null && value.isNotEmpty && value.length <= 512) {
      target[canonicalKey] = value;
      return;
    }
  }
}
