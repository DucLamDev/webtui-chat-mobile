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

AppDeepLinkIntent? parseAppDeepLink(
  Uri uri, {
  required InstanceScope? activeInstance,
}) {
  if (_isOidcCallback(uri)) {
    return AppOidcCallbackDeepLink(uri);
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

final class AppDeepLinkCoordinator {
  AppDeepLinkCoordinator({
    required Future<String?> Function() loadAccessToken,
    required InstanceScope? Function() loadActiveInstance,
    required void Function(String location) navigate,
    required Future<void> Function(Uri uri) handleOidcCallback,
  }) : _loadAccessToken = loadAccessToken,
       _loadActiveInstance = loadActiveInstance,
       _navigate = navigate,
       _handleOidcCallback = handleOidcCallback;

  final Future<String?> Function() _loadAccessToken;
  final InstanceScope? Function() _loadActiveInstance;
  final void Function(String location) _navigate;
  final Future<void> Function(Uri uri) _handleOidcCallback;
  String? _pendingLocation;
  String? _pendingInstanceScopeId;
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
        final generation = ++_navigationGeneration;
        String? token;
        try {
          token = await _loadAccessToken();
        } on Object {
          token = null;
        }
        if (generation != _navigationGeneration) {
          return;
        }
        if (token?.trim().isNotEmpty == true) {
          _pendingLocation = null;
          _pendingInstanceScopeId = null;
          _navigate(location);
          return;
        }
        _pendingLocation = location;
        _pendingInstanceScopeId = activeInstance!.storageId;
        _navigate('/login');
      case null:
        return;
    }
  }

  Future<void> onAuthenticationChanged(String? accessToken) async {
    if (accessToken?.trim().isNotEmpty != true) {
      return;
    }
    final location = _pendingLocation;
    final pendingInstanceScopeId = _pendingInstanceScopeId;
    final activeInstance = _loadActiveInstance();
    if (location == null ||
        pendingInstanceScopeId == null ||
        activeInstance?.storageId != pendingInstanceScopeId) {
      _pendingLocation = null;
      _pendingInstanceScopeId = null;
      return;
    }
    _pendingLocation = null;
    _pendingInstanceScopeId = null;
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
    return uri.host.toLowerCase() == 'chat.vpsttt.com' &&
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
