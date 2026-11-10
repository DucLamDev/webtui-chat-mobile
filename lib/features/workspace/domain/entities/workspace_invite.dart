/// Xem trước lời mời `GET /invites/{token}` (Lõi 2.5).
final class WorkspaceInvitePreview {
  const WorkspaceInvitePreview({
    required this.workspaceId,
    required this.workspaceName,
    required this.status,
    this.workspaceSlug,
    this.domain,
    this.kind,
    this.emailHint,
    this.expiresAt,
  });

  final String workspaceId;
  final String workspaceName;
  final String? workspaceSlug;

  /// Tên miền máy chủ phát hành lời mời.
  final String? domain;

  /// `email | link`.
  final String? kind;
  final String? emailHint;

  /// `active | expired | revoked | used_up`.
  final String status;
  final DateTime? expiresAt;

  bool get isActive => status == 'active';
}

/// Kết quả `POST /invites/{token}/accept`.
final class InviteAcceptResult {
  const InviteAcceptResult({required this.workspaceId, required this.status});

  final String workspaceId;

  /// `joined | already_member`.
  final String status;

  bool get alreadyMember => status == 'already_member';
}

abstract final class InviteErrorCode {
  static const notFound = 'INVITE_NOT_FOUND';
  static const expired = 'INVITE_EXPIRED';
  static const revoked = 'INVITE_REVOKED';
  static const usedUp = 'INVITE_USED_UP';
  static const emailMismatch = 'INVITE_EMAIL_MISMATCH';
}

/// Token lời mời chỉ gồm `[A-Za-z0-9_-]` (đi vào đường dẫn API).
bool isValidInviteToken(String token) {
  return RegExp(r'^[A-Za-z0-9_-]{8,256}$').hasMatch(token.trim());
}
