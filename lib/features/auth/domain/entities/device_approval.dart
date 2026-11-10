import 'user_session.dart';

/// Một quyết định duyệt đã ghi (`decisions[]`).
final class DeviceApprovalDecision {
  const DeviceApprovalDecision({
    required this.approverRole,
    required this.decision,
    this.createdAt,
  });

  /// `self | admin | delegate`.
  final String approverRole;

  /// `approve | reject` (máy chủ có thể trả `approved | rejected`).
  final String decision;
  final DateTime? createdAt;

  bool get isApproval => decision.toLowerCase().startsWith('approve');
}

/// `GET /auth/device-approvals/me`: trạng thái chờ duyệt của phiên đang dùng.
final class MyDeviceApproval {
  const MyDeviceApproval({
    required this.sessionId,
    required this.approvalStatus,
    this.approvalExpiresAt,
    this.mode = 'off',
    this.requiredRoles = const [],
    this.decisions = const [],
    this.hasTrustedDevice = false,
  });

  final String sessionId;
  final String approvalStatus;
  final DateTime? approvalExpiresAt;

  /// `off | self | two_person`.
  final String mode;
  final List<String> requiredRoles;
  final List<DeviceApprovalDecision> decisions;
  final bool hasTrustedDevice;

  bool get isApproved => approvalStatus == SessionApprovalStatus.approved;

  bool get isRejected => approvalStatus == SessionApprovalStatus.rejected;

  /// Còn chờ và chưa quá hạn theo đồng hồ máy (máy chủ vẫn là nơi quyết).
  bool isPendingAt(DateTime now) {
    if (approvalStatus != SessionApprovalStatus.pending) {
      return false;
    }
    final expiresAt = approvalExpiresAt;
    return expiresAt == null || expiresAt.isAfter(now);
  }

  /// Máy chủ báo hết hạn, hoặc còn `pending` nhưng đã quá `approval_expires_at`.
  bool isExpiredAt(DateTime now) {
    if (approvalStatus == 'expired') {
      return true;
    }
    final expiresAt = approvalExpiresAt;
    return approvalStatus == SessionApprovalStatus.pending &&
        expiresAt != null &&
        !expiresAt.isAfter(now);
  }
}

/// Một phiên đang chờ mà người dùng hiện tại có quyền duyệt.
final class DeviceApprovalRequest {
  const DeviceApprovalRequest({
    required this.sessionId,
    required this.myRole,
    this.userId,
    this.userDisplayName,
    this.userEmail,
    this.userAvatarUrl,
    this.deviceName,
    this.ipAddress,
    this.userAgent,
    this.authMethod,
    this.createdAt,
    this.approvalExpiresAt,
    this.decisions = const [],
  });

  final String sessionId;

  /// `self | admin | delegate`.
  final String myRole;
  final String? userId;
  final String? userDisplayName;
  final String? userEmail;
  final String? userAvatarUrl;
  final String? deviceName;
  final String? ipAddress;
  final String? userAgent;
  final String? authMethod;
  final DateTime? createdAt;
  final DateTime? approvalExpiresAt;
  final List<DeviceApprovalDecision> decisions;

  bool get isSelf => myRole == 'self';
}

/// Kết quả duyệt / từ chối.
final class DeviceApprovalResult {
  const DeviceApprovalResult({
    required this.sessionId,
    required this.approvalStatus,
  });

  final String sessionId;

  /// `approved`, còn `pending` (chờ người thứ hai) hoặc `rejected`.
  final String approvalStatus;
}

/// Phạm vi danh sách chờ duyệt.
enum DeviceApprovalScope {
  mine('mine'),
  admin('admin');

  const DeviceApprovalScope(this.value);

  final String value;
}

/// Mã lỗi máy chủ của luồng duyệt thiết bị.
abstract final class DeviceApprovalErrorCode {
  static const pending = 'DEVICE_APPROVAL_PENDING';
  static const forbidden = 'DEVICE_APPROVAL_FORBIDDEN';
  static const alreadyDecided = 'DEVICE_APPROVAL_ALREADY_DECIDED';
  static const notFound = 'DEVICE_APPROVAL_NOT_FOUND';
  static const expired = 'DEVICE_APPROVAL_EXPIRED';
}
