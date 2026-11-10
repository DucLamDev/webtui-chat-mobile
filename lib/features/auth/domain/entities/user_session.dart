/// Trạng thái duyệt thiết bị của một phiên (Lõi 2.3).
abstract final class SessionApprovalStatus {
  static const approved = 'approved';
  static const pending = 'pending';
  static const rejected = 'rejected';
}

final class UserSession {
  const UserSession({
    required this.id,
    required this.expiresAt,
    required this.createdAt,
    this.deviceName,
    this.ipAddress,
    this.userAgent,
    this.revokedAt,
    this.isCurrent = false,
    this.lastSeenAt,
    this.approvalStatus = SessionApprovalStatus.approved,
    this.authMethod,
    this.revokedReason,
  });

  final String id;
  final String? deviceName;
  final String? ipAddress;
  final String? userAgent;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? revokedAt;

  /// Chỉ máy chủ biết phiên nào là máy đang dùng (`is_current`). Không suy từ
  /// [revokedAt] hay [isActive]: mọi phiên còn hạn đều "đang hoạt động".
  final bool isCurrent;

  /// Lần cuối phiên gọi API (`last_seen_at`); máy chủ cũ không trả.
  final DateTime? lastSeenAt;

  /// `approved | pending | rejected`; máy chủ cũ không trả → `approved`.
  final String approvalStatus;

  /// `password | register | oidc | qr | email_code | invite`.
  final String? authMethod;
  final String? revokedReason;

  bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now());

  bool get isPendingApproval => approvalStatus == SessionApprovalStatus.pending;

  /// Mốc "Hoạt động lần cuối": `last_seen_at`, thiếu thì lúc tạo phiên.
  DateTime get lastActivityAt => lastSeenAt ?? createdAt;
}
