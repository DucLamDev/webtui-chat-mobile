import '../../../../core/result/result.dart';
import '../entities/chat_message.dart';
import '../entities/message_card.dart';
import '../entities/rich_message.dart';

/// Tin nhắn nâng cao: tải lại một tin (tin chạy dần bị thiếu đoạn), bấm nút /
/// gửi biểu mẫu của thẻ, quyết định phê duyệt, chép lời tin thoại.
///
/// Mọi kiểm quyền thật nằm ở máy chủ; client chỉ ẩn / khoá nút cho dễ dùng.
abstract interface class RichMessageRepository {
  Future<Result<ChatMessage>> getMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  });

  Future<Result<MessageActionInvocation>> invokeAction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String actionId,
  });

  /// Lỗi `INVALID_FORM_SUBMISSION` có `Failure.cause` là
  /// [MessageFormFieldErrors] (lỗi từng ô).
  Future<Result<MessageFormSubmission>> submitForm({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String formId,
    required Map<String, Object?> values,
  });

  Future<Result<MessageInteractionSummary>> loadMyInteractions({
    required String workspaceId,
    required String channelId,
    required String messageId,
  });

  Future<Result<void>> decideApproval({
    required String workspaceId,
    required String approvalId,
    required MessageCardApprovalDecision decision,
    String comment = '',
  });

  Future<Result<FileTranscript>> getFileTranscript({
    required String workspaceId,
    required String fileId,
  });
}
