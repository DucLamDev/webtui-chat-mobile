import 'dart:async';

import 'package:dio/dio.dart';

/// Fail-closed process state shared by the app-level legal gate and the
/// authenticated HTTP interceptor. It never persists or fabricates consent.
final class LegalAcceptanceAccessPolicy {
  final StreamController<void> _requiredEvents =
      StreamController<void>.broadcast(sync: true);
  bool _complete = false;

  bool get canCreateUserContent => _complete;
  Stream<void> get requiredEvents => _requiredEvents.stream;

  void markComplete() {
    _complete = true;
  }

  void reset() {
    _complete = false;
  }

  void requireAcceptance() {
    _complete = false;
    if (!_requiredEvents.isClosed) {
      _requiredEvents.add(null);
    }
  }

  bool shouldBlock(RequestOptions request) {
    if (_complete || !_isMutation(request.method)) {
      return false;
    }
    return !_isAllowedWithoutAcceptance(request);
  }

  void dispose() {
    _requiredEvents.close();
  }
}

bool _isMutation(String method) {
  return switch (method.toUpperCase()) {
    'POST' || 'PUT' || 'PATCH' => true,
    _ => false,
  };
}

bool _isAllowedWithoutAcceptance(RequestOptions request) {
  final method = request.method.toUpperCase();
  final path = request.uri.path;
  if (path == '/api/v1/auth/legal-acceptance' ||
      path == '/api/v1/auth/logout') {
    return true;
  }
  if (path.startsWith('/api/v1/mobile/devices')) {
    return true;
  }
  if (path.startsWith('/api/v1/notifications')) {
    return true;
  }
  if (path.endsWith('/read-state') || path.endsWith('/presence/heartbeat')) {
    return true;
  }
  if (path.endsWith('/sync/ack')) {
    return true;
  }
  if (path.endsWith('/moderation/reports') || path.endsWith('/blocks')) {
    return true;
  }
  if (method == 'POST' &&
      RegExp(r'/calls/[^/]+/(reject|cancel|hangup|miss)$').hasMatch(path)) {
    return true;
  }
  if (_isRestrictiveCollaborationMutation(method, path, request.data)) {
    return true;
  }
  return false;
}

/// Mirrors the backend's mixed collaboration routes: an unaccepted account
/// may still make a running session safer or terminate capture, but may never
/// expand participation, media, roles, or shared content. Unknown/malformed
/// bodies fail closed.
bool _isRestrictiveCollaborationMutation(
  String method,
  String path,
  Object? data,
) {
  final collaborationRoot = RegExp(
    r'^/api/v1/workspaces/[^/]+/channels/[^/]+/collaboration$',
  );
  final collaborationChild = RegExp(
    r'^/api/v1/workspaces/[^/]+/channels/[^/]+/collaboration/',
  );
  if (!collaborationRoot.hasMatch(path) && !collaborationChild.hasMatch(path)) {
    return false;
  }

  if (method == 'POST' &&
      (path.endsWith('/voice-room/stop') ||
          RegExp(r'/recordings/[^/]+/stop$').hasMatch(path))) {
    return true;
  }

  final payload = _jsonObject(data);
  if (payload == null) return false;

  if (method == 'PUT' && collaborationRoot.hasMatch(path)) {
    return _normalizedString(payload['room_mode']) == 'internal' &&
        payload['lobby_enabled'] == true &&
        payload['chat_locked'] == true &&
        payload['guest_microphone_enabled'] == false &&
        payload['guest_camera_enabled'] == false &&
        _normalizedString(payload['default_participant_role']) == 'listener';
  }
  if (method == 'PATCH' && RegExp(r'/roles/[^/]+$').hasMatch(path)) {
    return _normalizedString(payload['role']) == 'listener';
  }
  if (method == 'PUT' && path.endsWith('/assignments')) {
    final assignedUserIds = payload['assigned_user_ids'];
    return assignedUserIds is List && assignedUserIds.isEmpty;
  }
  if (method == 'PUT' && path.endsWith('/recording-policy')) {
    return payload['enabled'] == false;
  }
  if (method == 'PUT' && RegExp(r'/recordings/[^/]+/consent$').hasMatch(path)) {
    return payload['consented'] == false;
  }
  return false;
}

Map<String, Object?>? _jsonObject(Object? data) {
  if (data is! Map) return null;
  final payload = <String, Object?>{};
  for (final entry in data.entries) {
    if (entry.key is! String) return null;
    payload[entry.key as String] = entry.value;
  }
  return payload;
}

String? _normalizedString(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ? null : normalized;
}
