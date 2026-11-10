import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_card.dart';
import '../../domain/entities/rich_message.dart';
import '../../domain/repositories/rich_message_repository.dart';
import 'message_card_form_validator.dart';

/// Tải lại một tin (tin chạy dần bị thiếu đoạn).
final class GetMessageUseCase {
  const GetMessageUseCase(this._repository);

  final RichMessageRepository _repository;

  Future<Result<ChatMessage>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    if (messageId.trim().isEmpty) {
      return Future.value(const FailureResult(_missingMessage));
    }
    return _repository.getMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId.trim(),
    );
  }
}

/// Bấm nút `callback` của thẻ (máy chủ tự chặn bấm trùng).
final class InvokeMessageActionUseCase {
  const InvokeMessageActionUseCase(this._repository);

  final RichMessageRepository _repository;

  Future<Result<MessageActionInvocation>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String actionId,
  }) {
    if (messageId.trim().isEmpty || actionId.trim().isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Nút này không còn dùng được.',
            code: 'ACTION_NOT_FOUND',
          ),
        ),
      );
    }
    return _repository.invokeAction(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      actionId: actionId,
    );
  }
}

/// Gửi biểu mẫu của thẻ: kiểm ở client trước (lỗi từng ô nằm ở
/// `Failure.cause` dạng [MessageFormFieldErrors]), rồi gửi giá trị đã chuẩn hoá.
final class SubmitMessageFormUseCase {
  const SubmitMessageFormUseCase(this._repository);

  final RichMessageRepository _repository;

  Future<Result<MessageFormSubmission>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required MessageCardForm form,
    required Map<String, Object?> values,
  }) {
    final errors = validateMessageCardForm(form, values);
    if (errors.isNotEmpty) {
      return Future.value(
        FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Biểu mẫu còn ô chưa hợp lệ.',
            code: 'INVALID_FORM_SUBMISSION',
            cause: MessageFormFieldErrors(errors),
          ),
        ),
      );
    }
    return _repository.submitForm(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      formId: form.formId,
      values: normalizeMessageCardFormValues(form, values),
    );
  }
}

final class LoadMyMessageInteractionsUseCase {
  const LoadMyMessageInteractionsUseCase(this._repository);

  final RichMessageRepository _repository;

  Future<Result<MessageInteractionSummary>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    return _repository.loadMyInteractions(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
  }
}

/// Câu báo khi máy chủ chưa có API phê duyệt (route trả 404).
const approvalUnavailableMessage =
    'Chức năng phê duyệt chưa sẵn sàng trên máy chủ';

/// Đồng ý / từ chối một yêu cầu phê duyệt từ nút trên thẻ.
final class DecideApprovalUseCase {
  const DecideApprovalUseCase(this._repository);

  final RichMessageRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String approvalId,
    required MessageCardApprovalDecision decision,
  }) async {
    if (approvalId.trim().isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Yêu cầu phê duyệt không hợp lệ.',
          code: 'VALIDATION_ERROR',
        ),
      );
    }
    final result = await _repository.decideApproval(
      workspaceId: workspaceId,
      approvalId: approvalId.trim(),
      decision: decision,
    );
    if (result case FailureResult(:final failure)
        when failure.kind == FailureKind.notFound &&
            _isMissingRoute(failure.code)) {
      return FailureResult(
        failure.copyWith(
          message: approvalUnavailableMessage,
          code: 'APPROVAL_UNAVAILABLE',
        ),
      );
    }
    return result;
  }

  /// 404 không kèm mã nghiệp vụ = máy chủ chưa có route (bản cũ). Mã cụ thể
  /// (vd. yêu cầu không còn) thì giữ câu của máy chủ.
  static bool _isMissingRoute(String? code) {
    final normalized = code?.trim().toUpperCase() ?? '';
    return normalized.isEmpty ||
        normalized == 'NOT_FOUND' ||
        normalized == 'ROUTE_NOT_FOUND';
  }
}

final class LoadFileTranscriptUseCase {
  const LoadFileTranscriptUseCase(this._repository);

  final RichMessageRepository _repository;

  Future<Result<FileTranscript>> execute({
    required String workspaceId,
    required String fileId,
  }) {
    if (fileId.trim().isEmpty) {
      return Future.value(const FailureResult(_missingMessage));
    }
    return _repository.getFileTranscript(
      workspaceId: workspaceId,
      fileId: fileId.trim(),
    );
  }
}

const _missingMessage = Failure(
  kind: FailureKind.validation,
  message: 'Không tìm thấy tin nhắn.',
  code: 'MESSAGE_NOT_FOUND',
);
