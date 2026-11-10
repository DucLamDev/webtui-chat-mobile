import 'dart:async';
import 'dart:convert';

import '../../../core/error/failure.dart';
import '../domain/repositories/auth_token_repository.dart';
import '../domain/repositories/session_state_repository.dart';

/// Vì sao phiên trên máy này kết thúc ngoài ý người dùng.
enum SessionEndReason {
  /// `401 SESSION_REVOKED`, refresh bị từ chối, hoặc WS `SessionRevoked`.
  revoked,

  /// `401 RELOGIN_REQUIRED` khi refresh (quá tuổi phiên / bỏ không quá lâu).
  reloginRequired,

  /// Máy tin cậy / quản trị đã từ chối thiết bị này.
  approvalRejected,

  /// Quá thời hạn chờ duyệt thiết bị.
  approvalExpired,
}

/// Thông báo cho giao diện: đưa về màn đăng nhập kèm lời giải thích.
final class SessionEndedNotice {
  const SessionEndedNotice({required this.reason, this.code, this.detail});

  /// Từ lỗi máy chủ (`error.code` + `details.reason`).
  factory SessionEndedNotice.fromFailure(Failure failure) {
    final detail = failure.details['reason']?.toString().trim();
    return SessionEndedNotice(
      reason: failure.hasCode(SessionErrorCode.reloginRequired)
          ? SessionEndReason.reloginRequired
          : SessionEndReason.revoked,
      code: failure.code,
      detail: detail == null || detail.isEmpty ? null : detail,
    );
  }

  /// Từ sự kiện WebSocket `SessionRevoked` (`payload.reason`).
  factory SessionEndedNotice.revokedByServer(String? reason) {
    final detail = reason?.trim();
    return SessionEndedNotice(
      reason: detail == 'device_rejected'
          ? SessionEndReason.approvalRejected
          : SessionEndReason.revoked,
      code: SessionErrorCode.sessionRevoked,
      detail: detail == null || detail.isEmpty ? null : detail,
    );
  }

  final SessionEndReason reason;
  final String? code;

  /// `user_revoked | logout_all | admin_revoked | device_rejected |
  /// account_disabled | policy | idle | max_session_age`.
  final String? detail;

  /// Có nên điền sẵn tên đăng nhập (đăng nhập lại cùng tài khoản).
  bool get prefersPrefill =>
      reason == SessionEndReason.reloginRequired ||
      reason == SessionEndReason.revoked;

  String get message {
    switch (reason) {
      case SessionEndReason.reloginRequired:
        return switch (detail) {
          'idle' =>
            'Bạn đã không dùng ứng dụng quá lâu. Vui lòng đăng nhập lại.',
          'max_session_age' =>
            'Phiên đăng nhập đã tới thời hạn tối đa của tổ chức. '
                'Vui lòng đăng nhập lại.',
          _ => 'Vui lòng đăng nhập lại để tiếp tục.',
        };
      case SessionEndReason.approvalRejected:
        return 'Yêu cầu đăng nhập trên thiết bị này đã bị từ chối.';
      case SessionEndReason.approvalExpired:
        return 'Hết thời gian chờ duyệt thiết bị. Vui lòng đăng nhập lại.';
      case SessionEndReason.revoked:
        return switch (detail) {
          'user_revoked' =>
            'Phiên đăng nhập trên thiết bị này đã bị thu hồi từ thiết bị khác.',
          'logout_all' => 'Bạn đã đăng xuất khỏi tất cả thiết bị.',
          'admin_revoked' =>
            'Quản trị viên đã thu hồi phiên đăng nhập trên thiết bị này.',
          'device_rejected' =>
            'Yêu cầu đăng nhập trên thiết bị này đã bị từ chối.',
          'account_disabled' => 'Tài khoản của bạn đã bị khoá.',
          'policy' =>
            'Phiên đăng nhập đã kết thúc theo chính sách của tổ chức.',
          _ => 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.',
        };
    }
  }
}

/// Mã lỗi phiên dùng chung (Lõi 2.1, 2.8).
abstract final class SessionErrorCode {
  static const sessionRevoked = 'SESSION_REVOKED';
  static const reloginRequired = 'RELOGIN_REQUIRED';
}

/// Một nơi duy nhất kết thúc phiên bị máy chủ thu hồi: xoá token, Drift, tệp
/// tải về, cuộc gọi CallKit, thông báo (qua [SessionStateRepository]) rồi báo
/// giao diện về màn đăng nhập.
///
/// - Nhiều request / nhiều kết nối WS cùng báo một lúc chỉ chạy một lần.
/// - Sự kiện lặp sau khi đã xoá (không còn token) bị bỏ qua.
/// - Sự kiện WS mang `session_id` khác `sid` của token hiện tại (phiên cũ)
///   không xoá phiên mới.
final class SessionTerminationCoordinator {
  SessionTerminationCoordinator({
    required SessionStateRepository sessionStateRepository,
    required AuthTokenRepository tokenRepository,
  }) : _sessionStateRepository = sessionStateRepository,
       _tokenRepository = tokenRepository;

  final SessionStateRepository _sessionStateRepository;
  final AuthTokenRepository _tokenRepository;
  final _ended = StreamController<SessionEndedNotice>.broadcast();
  final _approvalPending = StreamController<void>.broadcast();
  Future<bool>? _inFlight;
  AuthTokenMutationGuard? _inFlightGuard;

  Stream<SessionEndedNotice> get endedSessions => _ended.stream;

  /// Máy chủ trả `403 DEVICE_APPROVAL_PENDING`: phiên này còn chờ duyệt.
  Stream<void> get approvalPendingSignals => _approvalPending.stream;

  void reportApprovalPending() {
    if (!_approvalPending.isClosed) {
      _approvalPending.add(null);
    }
  }

  /// Trả true khi đã xoá phiên đang dùng và đã báo giao diện.
  Future<bool> endSession(
    SessionEndedNotice notice, {
    AuthTokenMutationGuard? guard,
    String? revokedSessionId,
  }) async {
    final AuthTokenMutationGuard? target;
    try {
      target =
          guard ?? await _sessionStateRepository.captureActiveSessionGuard();
    } on Object {
      return false;
    }
    if (target == null) {
      return false;
    }
    final running = _inFlight;
    if (running != null && _inFlightGuard == target) {
      return running;
    }
    final run = _terminate(target, notice, revokedSessionId?.trim());
    _inFlight = run;
    _inFlightGuard = target;
    try {
      return await run;
    } finally {
      if (identical(_inFlight, run)) {
        _inFlight = null;
        _inFlightGuard = null;
      }
    }
  }

  Future<bool> _terminate(
    AuthTokenMutationGuard guard,
    SessionEndedNotice notice,
    String? revokedSessionId,
  ) async {
    String? accessToken;
    String? refreshToken;
    try {
      accessToken = (await _tokenRepository.readAccessTokenIfCurrent(
        guard,
      ))?.trim();
      refreshToken = (await _tokenRepository.readRefreshTokenIfCurrent(
        guard,
      ))?.trim();
    } on Object {
      accessToken = null;
      refreshToken = null;
    }
    final hadSession =
        (accessToken?.isNotEmpty ?? false) ||
        (refreshToken?.isNotEmpty ?? false);
    if (!hadSession) {
      return false;
    }
    if (revokedSessionId != null && revokedSessionId.isNotEmpty) {
      final currentSessionId = accessTokenSessionId(accessToken);
      if (currentSessionId != null && currentSessionId != revokedSessionId) {
        return false;
      }
    }

    var wasCurrent = true;
    try {
      await _tokenRepository.clearTokensIfCurrent(guard);
    } on Object {
      // Vẫn xoá dữ liệu cục bộ bên dưới.
    }
    try {
      wasCurrent = await _sessionStateRepository.resetForLogoutIfCurrent(guard);
    } on Object {
      // Máy chủ đã thu hồi phiên: dù xoá cục bộ lỗi vẫn phải về đăng nhập.
      wasCurrent = true;
    }
    if (wasCurrent && !_ended.isClosed) {
      _ended.add(notice);
    }
    return wasCurrent;
  }

  Future<void> dispose() async {
    await _ended.close();
    await _approvalPending.close();
  }
}

/// Đọc claim `sid` (id phiên) trong access token JWT. Chỉ dùng để so khớp
/// cục bộ, không thay cho kiểm chữ ký ở máy chủ. Token cũ không có `sid`
/// hoặc không phải JWT → null.
String? accessTokenSessionId(String? token) {
  final parts = token?.trim().split('.');
  if (parts == null || parts.length != 3 || parts[1].isEmpty) {
    return null;
  }
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map) {
      final sid = payload['sid'];
      if (sid is String && sid.trim().isNotEmpty) {
        return sid.trim();
      }
    }
  } on Object {
    return null;
  }
  return null;
}
