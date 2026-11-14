import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_card.dart';
import 'package:webtui_chat/features/conversations/domain/entities/rich_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/rich_message_repository.dart';

/// Máy chủ giả cho thẻ: bấm nút `callback` thì trả lỗi [invokeError] (nếu có).
final class FakeRichMessageRepository implements RichMessageRepository {
  FakeRichMessageRepository({this.invokeError});

  final String? invokeError;
  final invoked = <String>[];

  @override
  Future<Result<MessageActionInvocation>> invokeAction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String actionId,
  }) async {
    invoked.add(actionId);
    final error = invokeError;
    if (error != null) {
      return FailureResult(
        Failure(
          kind: FailureKind.conflict,
          message: error,
          code: 'NOTICE_ACTION_DONE',
        ),
      );
    }
    return Success(
      MessageActionInvocation(
        interactionId: 'i',
        actionId: actionId,
        createdAt: DateTime.utc(2026, 11),
      ),
    );
  }

  @override
  Future<Result<MessageInteractionSummary>> loadMyInteractions({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async => const Success(MessageInteractionSummary());

  @override
  Future<Result<ChatMessage>> getMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) => throw UnimplementedError();

  @override
  Future<Result<MessageFormSubmission>> submitForm({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String formId,
    required Map<String, Object?> values,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> decideApproval({
    required String workspaceId,
    required String approvalId,
    required MessageCardApprovalDecision decision,
    String comment = '',
  }) => throw UnimplementedError();

  @override
  Future<Result<FileTranscript>> getFileTranscript({
    required String workspaceId,
    required String fileId,
  }) => throw UnimplementedError();
}
