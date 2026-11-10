/// Trạng thái yêu cầu phê duyệt (khớp hợp đồng máy chủ).
enum ApprovalStatus {
  pending,
  approved,
  rejected,
  expired,
  executed,
  failed,
  cancelled,
  unknown;

  static ApprovalStatus fromApi(String value) {
    return switch (value.trim().toLowerCase()) {
      'pending' => ApprovalStatus.pending,
      'approved' => ApprovalStatus.approved,
      'rejected' => ApprovalStatus.rejected,
      'expired' => ApprovalStatus.expired,
      'executed' => ApprovalStatus.executed,
      'failed' => ApprovalStatus.failed,
      'cancelled' => ApprovalStatus.cancelled,
      _ => ApprovalStatus.unknown,
    };
  }

  String get label => switch (this) {
    ApprovalStatus.pending => 'Đang chờ',
    ApprovalStatus.approved => 'Đã duyệt',
    ApprovalStatus.rejected => 'Đã từ chối',
    ApprovalStatus.expired => 'Hết hạn',
    ApprovalStatus.executed => 'Đã thực hiện',
    ApprovalStatus.failed => 'Thực hiện lỗi',
    ApprovalStatus.cancelled => 'Đã huỷ',
    ApprovalStatus.unknown => 'Không rõ',
  };
}

/// Bộ lọc danh sách: Đang chờ / Đã xử lý.
enum ApprovalFilter {
  pending('pending', 'Đang chờ'),
  done('done', 'Đã xử lý');

  const ApprovalFilter(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

enum ApprovalDecisionKind {
  approve('approve'),
  reject('reject');

  const ApprovalDecisionKind(this.apiValue);

  final String apiValue;

  static ApprovalDecisionKind? fromApi(String? value) {
    for (final kind in values) {
      if (kind.apiValue == value?.trim().toLowerCase()) return kind;
    }
    return null;
  }
}

final class ApprovalVote {
  const ApprovalVote({
    required this.userId,
    required this.decision,
    required this.comment,
    this.createdAt,
  });

  final String userId;
  final ApprovalDecisionKind? decision;
  final String comment;
  final DateTime? createdAt;
}

final class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.workspaceId,
    required this.status,
    required this.title,
    required this.action,
    required this.source,
    required this.requiredApprovals,
    required this.approvalsCount,
    required this.canDecide,
    this.resourceType = '',
    this.resourceId = '',
    this.payload = const {},
    this.channelId,
    this.requestedBy,
    this.expiresAt,
    this.decidedAt,
    this.createdAt,
    this.decisions = const [],
  });

  final String id;
  final String workspaceId;
  final ApprovalStatus status;
  final String title;
  final String action;
  final String resourceType;
  final String resourceId;
  final Map<String, Object?> payload;
  final String? channelId;

  /// `user` | `bot` | `webhook` | `order`.
  final String source;
  final String? requestedBy;
  final int requiredApprovals;
  final int approvalsCount;
  final DateTime? expiresAt;
  final DateTime? decidedAt;
  final DateTime? createdAt;
  final List<ApprovalVote> decisions;

  /// Máy chủ báo người đang xem được duyệt yêu cầu này lúc này. Chỉ để ẩn /
  /// hiện nút; máy chủ vẫn kiểm quyền khi nhận quyết định.
  final bool canDecide;

  bool get isPending => status == ApprovalStatus.pending;

  String get sourceLabel => switch (source) {
    'bot' => 'Bot',
    'webhook' => 'Webhook',
    'order' => 'Đơn hàng',
    _ => 'Người dùng',
  };
}

final class ApprovalPage {
  const ApprovalPage({required this.items, this.nextCursor});

  final List<ApprovalRequest> items;
  final String? nextCursor;

  bool get hasMore => nextCursor?.isNotEmpty == true;
}
