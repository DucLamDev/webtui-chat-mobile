import '../../domain/entities/chat_message.dart';
import '../../domain/entities/rich_message.dart';

/// Kết quả ghép các đoạn `MessageDelta` vào một tin đang chạy dần.
final class MessageStreamMergeResult {
  const MessageStreamMergeResult({
    required this.message,
    this.changed = false,
    this.hasGap = false,
    this.pending = const [],
  });

  /// Tin sau khi ghép (giữ nguyên nếu không có đoạn nào ghép được).
  final ChatMessage message;
  final bool changed;

  /// Thiếu `seq` ở giữa: phải tải lại tin rồi chỉ ghép đoạn có `seq` lớn hơn
  /// `metadata.stream_seq` của bản vừa tải.
  final bool hasGap;

  /// Các đoạn đến trước, chưa ghép được vì còn thiếu đoạn trước nó (theo `seq`).
  final List<MessageStreamDelta> pending;
}

/// Chữ giữ chỗ máy chủ đặt lúc tạo tin chạy dần (client cũ thấy "…").
const messageStreamPlaceholder = '…';

/// Ghép [deltas] vào [message] theo đúng thứ tự `seq` (hàm thuần, không gọi mạng):
/// - tin đã xong (`streaming != true`) thì bỏ qua mọi đoạn: bản cuối thắng;
/// - `seq` ≤ seq đã ghép là đoạn trùng, bỏ;
/// - đoạn đầu tiên thay chỗ "…" giữ chỗ thay vì nối thêm;
/// - gặp `seq` nhảy cóc thì dừng, trả [MessageStreamMergeResult.hasGap] và các
///   đoạn còn lại để ghép sau khi tải lại tin.
MessageStreamMergeResult mergeMessageStreamDeltas(
  ChatMessage message,
  Iterable<MessageStreamDelta> deltas,
) {
  if (!message.isStreaming || message.isDeleted) {
    return MessageStreamMergeResult(message: message);
  }
  final bySeq = <int, MessageStreamDelta>{};
  for (final delta in deltas) {
    if (delta.messageId != message.id || delta.seq < 1) continue;
    bySeq.putIfAbsent(delta.seq, () => delta);
  }
  final ordered = bySeq.keys.toList()..sort();
  var lastSeq = message.streamSeq ?? 0;
  if (lastSeq < 0) lastSeq = 0;
  var body = message.body;
  var changed = false;
  final pending = <MessageStreamDelta>[];
  for (final seq in ordered) {
    if (seq <= lastSeq) continue;
    if (seq != lastSeq + 1 || pending.isNotEmpty) {
      pending.add(bySeq[seq]!);
      continue;
    }
    final append = bySeq[seq]!.append;
    body = lastSeq == 0 && _isPlaceholder(body) ? append : '$body$append';
    lastSeq = seq;
    changed = true;
  }
  return MessageStreamMergeResult(
    message: changed
        ? message.copyWith(
            body: body,
            metadata: {...message.metadata, 'stream_seq': lastSeq},
          )
        : message,
    changed: changed,
    hasGap: pending.isNotEmpty,
    pending: List.unmodifiable(pending),
  );
}

bool _isPlaceholder(String body) {
  final trimmed = body.trim();
  return trimmed.isEmpty ||
      trimmed == messageStreamPlaceholder ||
      trimmed == '...';
}

const _aiCardFence = '```webtui-card';

/// Chữ hiện trong lúc AI chạy dần. AI trả biểu đồ / sơ đồ / kế hoạch bằng khối
/// ```webtui-card ở cuối câu trả lời; máy chủ tách khối này thành thẻ khi trả
/// xong, nên trong lúc chạy dần không cho người dùng thấy JSON thô:
/// - từ dòng mở khối đầu tiên trở đi bị giấu, [drawing] = true;
/// - dòng cuối đang gõ dở mà là đầu của dòng mở khối (vd. "```web") cũng giấu
///   tạm; "```" đứng riêng (có thể là dòng đóng khối mã thường) vẫn hiện.
({String text, bool drawing}) visibleStreamingText(String body) {
  final lines = body.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    final isLast = index == lines.length - 1;
    if (line == _aiCardFence ||
        (isLast && line.length > 3 && _aiCardFence.startsWith(line))) {
      return (
        text: lines.sublist(0, index).join('\n').trimRight(),
        drawing: true,
      );
    }
  }
  return (text: body, drawing: false);
}
