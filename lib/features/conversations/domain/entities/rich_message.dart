/// Một đoạn chữ của tin đang chạy dần (sự kiện WebSocket `MessageDelta`).
final class MessageStreamDelta {
  const MessageStreamDelta({
    required this.messageId,
    required this.seq,
    required this.append,
  });

  final String messageId;

  /// Bắt đầu từ 1, tăng dần, không trùng.
  final int seq;
  final String append;
}

/// Kết quả bấm nút `callback` (bấm lần 2 trả bản ghi cũ với `duplicate`).
final class MessageActionInvocation {
  const MessageActionInvocation({
    required this.interactionId,
    required this.actionId,
    required this.createdAt,
    this.duplicate = false,
  });

  final String interactionId;
  final String actionId;
  final DateTime createdAt;
  final bool duplicate;
}

final class MessageFormSubmission {
  const MessageFormSubmission({
    required this.submissionId,
    required this.formId,
    required this.submittedAt,
  });

  final String submissionId;
  final String formId;
  final DateTime submittedAt;
}

final class MessageActionRecord {
  const MessageActionRecord({required this.actionId, required this.createdAt});

  final String actionId;
  final DateTime createdAt;
}

final class MessageFormRecord {
  const MessageFormRecord({
    required this.formId,
    required this.submittedAt,
    this.count = 1,
  });

  final String formId;
  final DateTime submittedAt;
  final int count;
}

/// Người dùng hiện tại đã bấm nút / gửi biểu mẫu nào của một tin.
final class MessageInteractionSummary {
  const MessageInteractionSummary({
    this.actions = const [],
    this.forms = const [],
  });

  final List<MessageActionRecord> actions;
  final List<MessageFormRecord> forms;
}

/// Lỗi từng ô do máy chủ trả (`details.fields`) hoặc client tự kiểm; gắn vào
/// `Failure.cause` của lỗi gửi biểu mẫu.
final class MessageFormFieldErrors {
  const MessageFormFieldErrors(this.fields);

  final Map<String, String> fields;
}

enum FileTranscriptStatus {
  none('none'),
  queued('queued'),
  processing('processing'),
  ready('ready'),
  failed('failed'),
  skipped('skipped');

  const FileTranscriptStatus(this.apiValue);

  final String apiValue;

  bool get isPending => this == queued || this == processing;

  static FileTranscriptStatus fromApi(String value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return FileTranscriptStatus.none;
  }
}

final class FileTranscriptSegment {
  const FileTranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String text;
}

final class FileTranscript {
  const FileTranscript({
    required this.fileId,
    required this.status,
    this.language,
    this.text = '',
    this.segments = const [],
    this.durationMs,
    this.updatedAt,
  });

  final String fileId;
  final FileTranscriptStatus status;
  final String? language;
  final String text;
  final List<FileTranscriptSegment> segments;
  final int? durationMs;
  final DateTime? updatedAt;
}
