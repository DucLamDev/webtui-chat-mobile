import '../../../core/error/failure.dart';

const inboxReplyWindowClosedCode = 'INBOX_REPLY_WINDOW_CLOSED';
const inboxSourceDisabledCode = 'INBOX_SOURCE_DISABLED';

/// Câu báo lỗi tiếng Việt khi gửi / đổi hội thoại không thành công.
String inboxActionFailureMessage(Failure failure) {
  if (failure.hasCode(inboxReplyWindowClosedCode)) {
    return 'Đã quá thời hạn trả lời của kênh này.';
  }
  if (failure.hasCode(inboxSourceDisabledCode)) {
    return 'Nguồn này đang tắt, chưa trả lời được.';
  }
  if (failure.kind == FailureKind.forbidden) {
    return 'Bạn không có quyền thực hiện thao tác này.';
  }
  if (failure.kind == FailureKind.notFound) {
    return 'Hội thoại không còn tồn tại.';
  }
  return failure.message.trim().isEmpty
      ? 'Chưa thực hiện được, hãy thử lại.'
      : failure.message;
}

/// Lỗi gửi chắc chắn không thành công nếu thử lại (không nên mời "Gửi lại").
bool inboxFailureIsPermanent(Failure failure) {
  return failure.hasCode(inboxReplyWindowClosedCode) ||
      failure.hasCode(inboxSourceDisabledCode) ||
      failure.kind == FailureKind.forbidden ||
      failure.kind == FailureKind.validation;
}
