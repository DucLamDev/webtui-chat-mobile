import 'package:webtui_chat/l10n/app_strings.dart';

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
    ApprovalStatus.pending => tr('Đang chờ', 'Pending'),
    ApprovalStatus.approved => tr('Đã duyệt', 'Approved'),
    ApprovalStatus.rejected => tr('Đã từ chối', 'Rejected'),
    ApprovalStatus.expired => tr('Đã hết hạn', 'Expired'),
    ApprovalStatus.executed => tr('Đã thực hiện', 'Executed'),
    ApprovalStatus.failed => tr('Thực hiện lỗi', 'Execution failed'),
    ApprovalStatus.cancelled => tr('Đã huỷ', 'Canceled'),
    ApprovalStatus.unknown => tr('Đã cập nhật', 'Updated'),
  };
}

/// Cách máy chủ thực hiện sau khi duyệt. Máy chủ cũ không gửi trường này.
enum ApprovalExecutionMode {
  none,
  internal,
  external;

  /// Giá trị thiếu / lạ coi như `none` (chỉ ghi nhận duyệt).
  static ApprovalExecutionMode fromApi(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'internal' => ApprovalExecutionMode.internal,
      'external' => ApprovalExecutionMode.external,
      _ => ApprovalExecutionMode.none,
    };
  }
}

/// Mức nhấn của nhãn trạng thái; giao diện tự đổi sang màu design system.
enum ApprovalStatusTone { neutral, success, error }

/// Chữ + mức nhấn hiển thị cho một phiếu (một nguồn duy nhất cho mọi màn).
final class ApprovalStatusDisplay {
  const ApprovalStatusDisplay({
    required this.label,
    required this.tone,
    this.detail,
  });

  final String label;
  final ApprovalStatusTone tone;

  /// Lý do lỗi / lý do huỷ (chỉ khi máy chủ có báo).
  final String? detail;
}

/// Bộ lọc danh sách: Đang chờ / Đã xử lý.
enum ApprovalFilter {
  pending('pending', 'Đang chờ', 'Pending'),
  done('done', 'Đã xử lý', 'Done');

  const ApprovalFilter(this.apiValue, this._vi, this._en);

  final String apiValue;
  final String _vi;
  final String _en;

  String get label => tr(_vi, _en);
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
    this.userEmail = '',
    this.createdAt,
  });

  final String userId;

  /// Email người cho ý kiến (máy chủ mới); trống thì hiện [userId].
  final String userEmail;
  final ApprovalDecisionKind? decision;
  final String comment;
  final DateTime? createdAt;

  /// Tên hiện trên màn hình: ưu tiên email, không có thì mã người dùng.
  String get voterLabel => userEmail.isNotEmpty ? userEmail : userId;
}

/// Kiểm một địa chỉ có phải `https://` hợp lệ để mở / tải không (không nhận
/// `http`, `javascript:`, địa chỉ có tài khoản / mật khẩu kèm theo).
Uri? approvalHttpsUri(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

/// Một ô nhãn / giá trị trong khối nội dung để người duyệt đọc.
final class ApprovalContentField {
  const ApprovalContentField({required this.label, required this.value});

  final String label;
  final String value;
}

/// Liên kết kèm khối nội dung. Chỉ [uri] khác `null` (https) mới được mở.
final class ApprovalContentLink {
  const ApprovalContentLink({required this.label, required this.url});

  final String label;
  final String url;

  Uri? get uri => approvalHttpsUri(url);
}

/// Khối `display` máy chủ gửi kèm yêu cầu để người duyệt đọc được nội dung
/// (chữ thường, ảnh, các ô nhãn / giá trị, một liên kết). Máy chủ cũ không
/// gửi thì yêu cầu không có khối này.
final class ApprovalContent {
  const ApprovalContent({
    this.text = '',
    this.imageUrl,
    this.fields = const [],
    this.link,
  });

  final String text;

  /// Chỉ giữ địa chỉ `https://`; địa chỉ khác bị bỏ khi đọc JSON.
  final String? imageUrl;
  final List<ApprovalContentField> fields;
  final ApprovalContentLink? link;

  bool get isEmpty =>
      text.trim().isEmpty && imageUrl == null && fields.isEmpty && link == null;

  /// Dòng đầu có chữ của [text] (cho dòng tóm tắt ở danh sách).
  String get firstLine {
    for (final line in text.split('\n')) {
      final value = line.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
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
    this.executionMode,
    this.executionStartedAt,
    this.reportedAt,
    this.resultExecutor,
    this.resultError,
    this.decisions = const [],
    this.content,
    this.externalKey,
    this.cancelReason,
    this.resultLabel,
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

  /// Khối `display` để người duyệt đọc; `null` khi máy chủ không gửi.
  final ApprovalContent? content;

  /// Khoá chống trùng của bot tạo yêu cầu (nếu có).
  final String? externalKey;

  /// Lý do huỷ (chỉ khi `cancelled` và máy chủ có gửi).
  final String? cancelReason;

  /// Nhãn kết quả bot gửi kèm khi báo xong (vd. "Đã đăng"); thay chữ
  /// "Đã thực hiện" / "Thực hiện lỗi" khi có.
  final String? resultLabel;

  /// Tuỳ chọn: máy chủ cũ không gửi `execution_mode` / mốc thời gian.
  final ApprovalExecutionMode? executionMode;
  final DateTime? executionStartedAt;
  final DateTime? reportedAt;

  /// `result.executor` / `result.error` của phiếu (nếu có).
  final String? resultExecutor;
  final String? resultError;

  /// Máy chủ báo người đang xem được duyệt yêu cầu này lúc này. Chỉ để ẩn /
  /// hiện nút; máy chủ vẫn kiểm quyền khi nhận quyết định.
  final bool canDecide;

  bool get isPending => status == ApprovalStatus.pending;

  /// Chữ + mức nhấn trạng thái dùng chung cho danh sách, chi tiết, thông báo.
  ApprovalStatusDisplay get display {
    const ok = ApprovalStatusTone.success;
    const plain = ApprovalStatusTone.neutral;
    switch (status) {
      case ApprovalStatus.approved:
        return switch (executionMode ?? ApprovalExecutionMode.none) {
          ApprovalExecutionMode.internal => ApprovalStatusDisplay(
            label: tr('Đã duyệt – đang thực hiện', 'Approved – in progress'),
            tone: plain,
          ),
          ApprovalExecutionMode.external => ApprovalStatusDisplay(
            label: tr(
              'Đã duyệt – chờ bot thực hiện',
              'Approved – waiting for the bot',
            ),
            tone: plain,
          ),
          ApprovalExecutionMode.none => ApprovalStatusDisplay(
            label: tr('Đã duyệt', 'Approved'),
            tone: ok,
          ),
        };
      case ApprovalStatus.executed:
        final executedLabel = _resultLabel;
        if (executedLabel != null) {
          return ApprovalStatusDisplay(label: executedLabel, tone: ok);
        }
        if (resultExecutor?.trim().toLowerCase() == 'none') {
          return ApprovalStatusDisplay(
            label: tr('Đã duyệt', 'Approved'),
            tone: ok,
          );
        }
        return ApprovalStatusDisplay(
          label: tr('Đã thực hiện', 'Executed'),
          tone: ok,
        );
      case ApprovalStatus.failed:
        final error = resultError?.trim();
        return ApprovalStatusDisplay(
          label: _resultLabel ?? tr('Thực hiện lỗi', 'Execution failed'),
          tone: ApprovalStatusTone.error,
          detail: error == null || error.isEmpty ? null : error,
        );
      case ApprovalStatus.cancelled:
        final reason = cancelReason?.trim();
        return ApprovalStatusDisplay(
          label: status.label,
          tone: plain,
          detail: reason == null || reason.isEmpty ? null : reason,
        );
      case ApprovalStatus.pending:
      case ApprovalStatus.rejected:
      case ApprovalStatus.expired:
      case ApprovalStatus.unknown:
        return ApprovalStatusDisplay(label: status.label, tone: plain);
    }
  }

  String? get _resultLabel {
    final label = resultLabel?.trim();
    return label == null || label.isEmpty ? null : label;
  }

  String get sourceLabel => switch (source) {
    'bot' => 'Bot',
    'webhook' => 'Webhook',
    'order' => tr('Đơn hàng', 'Order'),
    _ => tr('Người dùng', 'User'),
  };
}

final class ApprovalPage {
  const ApprovalPage({required this.items, this.nextCursor});

  final List<ApprovalRequest> items;
  final String? nextCursor;

  bool get hasMore => nextCursor?.isNotEmpty == true;
}
