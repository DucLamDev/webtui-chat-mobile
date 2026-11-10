import 'package:dio/dio.dart';

import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_card.dart';
import '../../domain/entities/rich_message.dart';
import '../../domain/repositories/rich_message_repository.dart';
import '../datasources/rich_message_remote_data_source.dart';

final class RichMessageRepositoryImpl implements RichMessageRepository {
  const RichMessageRepositoryImpl(this._remote);

  final RichMessageRemoteDataSource _remote;

  @override
  Future<Result<ChatMessage>> getMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    return guardResult(
      () => _remote.getMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
      ),
    );
  }

  @override
  Future<Result<MessageActionInvocation>> invokeAction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String actionId,
  }) {
    return guardResult(
      () => _remote.invokeAction(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
        actionId: actionId,
      ),
    );
  }

  @override
  Future<Result<MessageFormSubmission>> submitForm({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String formId,
    required Map<String, Object?> values,
  }) async {
    final result = await guardResult(
      () => _remote.submitForm(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
        formId: formId,
        values: values,
      ),
    );
    if (result case FailureResult(:final failure)) {
      final cause = failure.cause;
      final fields = cause is DioException
          ? formFieldErrorsFromErrorBody(cause.response?.data)
          : const <String, String>{};
      if (fields.isNotEmpty) {
        return FailureResult(
          failure.copyWith(cause: MessageFormFieldErrors(fields)),
        );
      }
    }
    return result;
  }

  @override
  Future<Result<MessageInteractionSummary>> loadMyInteractions({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    return guardResult(
      () => _remote.loadMyInteractions(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
      ),
    );
  }

  @override
  Future<Result<void>> decideApproval({
    required String workspaceId,
    required String approvalId,
    required MessageCardApprovalDecision decision,
    String comment = '',
  }) {
    return guardResult(
      () => _remote.decideApproval(
        workspaceId: workspaceId,
        approvalId: approvalId,
        decision: decision,
        comment: comment,
      ),
    );
  }

  @override
  Future<Result<FileTranscript>> getFileTranscript({
    required String workspaceId,
    required String fileId,
  }) {
    return guardResult(
      () => _remote.getFileTranscript(workspaceId: workspaceId, fileId: fileId),
    );
  }
}
