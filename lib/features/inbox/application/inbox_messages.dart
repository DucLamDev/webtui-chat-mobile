import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../core/error/failure.dart';

const inboxReplyWindowClosedCode = 'INBOX_REPLY_WINDOW_CLOSED';
const inboxSourceDisabledCode = 'INBOX_SOURCE_DISABLED';

/// Câu báo lỗi tiếng Việt khi gửi / đổi hội thoại không thành công.
String inboxActionFailureMessage(Failure failure) {
  if (failure.hasCode(inboxReplyWindowClosedCode)) {
    return tr(
      'Đã quá thời hạn trả lời của kênh này.',
      'The reply window for this channel has passed.',
    );
  }
  if (failure.hasCode(inboxSourceDisabledCode)) {
    return tr(
      'Nguồn này đang tắt, chưa trả lời được.',
      'This source is turned off, so you can\'t reply yet.',
    );
  }
  if (failure.kind == FailureKind.forbidden) {
    return tr(
      'Bạn không có quyền thực hiện thao tác này.',
      'You don\'t have permission to do this.',
    );
  }
  if (failure.kind == FailureKind.notFound) {
    return tr(
      'Hội thoại không còn tồn tại.',
      'This conversation no longer exists.',
    );
  }
  return failure.message.trim().isEmpty
      ? tr('Chưa thực hiện được, hãy thử lại.', 'Couldn\'t do that. Try again.')
      : failure.message;
}

/// Lỗi gửi chắc chắn không thành công nếu thử lại (không nên mời "Gửi lại").
bool inboxFailureIsPermanent(Failure failure) {
  return failure.hasCode(inboxReplyWindowClosedCode) ||
      failure.hasCode(inboxSourceDisabledCode) ||
      failure.kind == FailureKind.forbidden ||
      failure.kind == FailureKind.validation;
}
