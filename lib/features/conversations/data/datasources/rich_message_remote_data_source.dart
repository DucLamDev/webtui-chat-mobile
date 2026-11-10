import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_card.dart';
import '../../domain/entities/rich_message.dart';
import 'conversation_remote_data_source.dart';

/// REST cho tin nhắn nâng cao (thẻ, chạy dần, chép lời).
final class RichMessageRemoteDataSource {
  const RichMessageRemoteDataSource(this._api);

  final ApiTransport _api;

  String _messagePath(String workspaceId, String channelId, String messageId) =>
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}';

  Future<ChatMessage> getMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final response = await _api.get<Object>(
      _messagePath(workspaceId, channelId, messageId),
    );
    return chatMessageFromJson(
      envelopeItem(response.data, 'message'),
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }

  Future<MessageActionInvocation> invokeAction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String actionId,
  }) async {
    // Không gửi `value`: máy chủ lấy từ thẻ đã lưu.
    final response = await _api.post<Object>(
      '${_messagePath(workspaceId, channelId, messageId)}/actions',
      data: {'action_id': actionId},
    );
    final map = envelopeItem(response.data, 'interaction');
    return MessageActionInvocation(
      interactionId: stringField(map, const ['interaction_id', 'id']),
      actionId: stringField(map, const ['action_id'], fallback: actionId),
      createdAt: dateTimeField(map, const ['created_at']),
      duplicate: boolField(map, const ['duplicate']),
    );
  }

  Future<MessageFormSubmission> submitForm({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String formId,
    required Map<String, Object?> values,
  }) async {
    final response = await _api.post<Object>(
      '${_messagePath(workspaceId, channelId, messageId)}/forms/${_e(formId)}/submissions',
      data: {'values': values},
    );
    final map = envelopeItem(response.data, 'submission');
    return MessageFormSubmission(
      submissionId: stringField(map, const ['submission_id', 'id']),
      formId: stringField(map, const ['form_id'], fallback: formId),
      submittedAt: dateTimeField(map, const ['submitted_at', 'created_at']),
    );
  }

  Future<MessageInteractionSummary> loadMyInteractions({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final response = await _api.get<Object>(
      '${_messagePath(workspaceId, channelId, messageId)}/interactions/me',
    );
    final map = jsonMap(envelopeData(response.data));
    return MessageInteractionSummary(
      actions: [
        for (final item in jsonMapList(map['actions']))
          if (nullableStringField(item, const ['action_id']) case final id?)
            MessageActionRecord(
              actionId: id,
              createdAt: dateTimeField(item, const ['created_at']),
            ),
      ],
      forms: [
        for (final item in jsonMapList(map['forms']))
          if (nullableStringField(item, const ['form_id']) case final id?)
            MessageFormRecord(
              formId: id,
              submittedAt: dateTimeField(item, const [
                'submitted_at',
                'created_at',
              ]),
              count: intField(item, const ['count'], fallback: 1),
            ),
      ],
    );
  }

  Future<void> decideApproval({
    required String workspaceId,
    required String approvalId,
    required MessageCardApprovalDecision decision,
    String comment = '',
  }) async {
    await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/approvals/${_e(approvalId)}/decisions',
      data: {'decision': decision.name, 'comment': comment},
    );
  }

  Future<FileTranscript> getFileTranscript({
    required String workspaceId,
    required String fileId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/files/${_e(fileId)}/transcript',
    );
    final map = envelopeItem(response.data, 'transcript');
    final durationMs = field(map, const ['duration_ms']);
    return FileTranscript(
      fileId: stringField(map, const ['file_id'], fallback: fileId),
      status: FileTranscriptStatus.fromApi(
        stringField(map, const ['status'], fallback: 'none'),
      ),
      language: nullableStringField(map, const ['language']),
      text: stringField(map, const ['text']).trim(),
      segments: [
        for (final item in jsonMapList(map['segments']))
          FileTranscriptSegment(
            startMs: intField(item, const ['start_ms']),
            endMs: intField(item, const ['end_ms']),
            text: stringField(item, const ['text']).trim(),
          ),
      ],
      durationMs: durationMs is num ? durationMs.toInt() : null,
      updatedAt: nullableDateTimeField(map, const ['updated_at']),
    );
  }
}

/// Lỗi từng ô trong `error.details.fields` của `INVALID_FORM_SUBMISSION`.
Map<String, String> formFieldErrorsFromErrorBody(Object? body) {
  final error = jsonMap(jsonMap(body)['error']);
  final fields = jsonMap(jsonMap(error['details'])['fields']);
  return {
    for (final entry in fields.entries)
      if (entry.value != null && entry.value.toString().trim().isNotEmpty)
        entry.key: entry.value.toString().trim(),
  };
}

String _e(String value) => Uri.encodeComponent(value);
