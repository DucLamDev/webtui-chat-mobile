import '../../../core/error/failure.dart';

/// Vì sao không mở được VPSTTT IDE (mỗi loại ứng với một màn trạng thái).
enum IdeWebFailureKind {
  disabled,
  notAllowed,
  unavailable,
  rateLimited,
  expired,
  webViewTooOld,

  /// Lượt bị bỏ (người dùng huỷ, có lượt mới hơn): không hiện gì.
  cancelled,
}

/// Đổi lỗi API sang loại lỗi của màn IDE. Mã máy chủ được ưu tiên hơn HTTP.
IdeWebFailureKind ideWebFailureKindOf(Failure failure) {
  switch (failure.code?.trim().toUpperCase()) {
    case 'IDE_WEB_DISABLED':
      return IdeWebFailureKind.disabled;
    case 'IDE_WEB_NOT_ALLOWED':
      return IdeWebFailureKind.notAllowed;
    case 'IDE_WEB_UNAVAILABLE':
      return IdeWebFailureKind.unavailable;
    case 'IDE_WEB_LAUNCH_NOT_FOUND':
    case 'IDE_WEB_LAUNCH_EXPIRED':
    case 'IDE_WEB_STATE_MISMATCH':
    case 'IDE_WEB_CODE_REJECTED':
    case 'IDE_WEB_CODE_USED':
      return IdeWebFailureKind.expired;
    case 'IDE_WEB_RATE_LIMITED':
      return IdeWebFailureKind.rateLimited;
    case ideWebLaunchCancelledCode:
      return IdeWebFailureKind.cancelled;
  }
  return switch (failure.kind) {
    FailureKind.forbidden => IdeWebFailureKind.notAllowed,
    FailureKind.rateLimited => IdeWebFailureKind.rateLimited,
    // 401 của API chat đi đường hết phiên sẵn có; màn chỉ báo hết hạn.
    FailureKind.unauthorized => IdeWebFailureKind.expired,
    _ => IdeWebFailureKind.unavailable,
  };
}

/// Trả lời của cổng `ide.<chat>` cho khung chính; `null` = không phải lỗi.
IdeWebFailureKind? ideWebFailureKindOfGate(int status, String? gateHeader) {
  switch (gateHeader?.trim().toLowerCase()) {
    case 'disabled':
      return IdeWebFailureKind.disabled;
    case 'forbidden':
      return IdeWebFailureKind.notAllowed;
    case 'expired':
      return IdeWebFailureKind.expired;
  }
  return switch (status) {
    401 || 403 || 410 => IdeWebFailureKind.expired,
    429 => IdeWebFailureKind.rateLimited,
    >= 500 => IdeWebFailureKind.unavailable,
    _ => null,
  };
}

/// Mã nội bộ: lượt mở đã bị bỏ.
const ideWebLaunchCancelledCode = 'IDE_WEB_LAUNCH_CANCELLED';
