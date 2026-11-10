import 'auth_tokens.dart';
import 'auth_user.dart';
import 'user_session.dart';

final class AuthSession {
  const AuthSession({
    required this.tokens,
    required this.sessionId,
    this.user,
    this.refreshUntil,
    this.approvalStatus,
    this.approvalExpiresAt,
  });

  final AuthTokens tokens;
  final String sessionId;
  final AuthUser? user;
  final DateTime? refreshUntil;

  /// `approved | pending | rejected` (Lõi 2.3); máy chủ cũ không trả → null.
  final String? approvalStatus;
  final DateTime? approvalExpiresAt;

  /// Phiên mới phải chờ máy tin cậy / quản trị duyệt trước khi dùng app.
  bool get isPendingApproval =>
      approvalStatus?.trim().toLowerCase() == SessionApprovalStatus.pending;
}
