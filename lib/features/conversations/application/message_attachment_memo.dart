import 'dart:collection';

import '../domain/entities/chat_message.dart';

/// Tệp đính kèm đã hỏi máy chủ của từng tin.
///
/// Danh sách tin không kèm tệp, nên mỗi lần mở lại phòng chat app phải hỏi
/// riêng từng tin có tệp (17/11/2026: cùng một tin bị hỏi 18 lần). Bộ nhớ này
/// giữ kết quả suốt lần chạy app để không hỏi lại. Tệp của một tin không đổi
/// sau khi gửi; khi máy chủ báo vừa gắn thêm tệp thì nơi gọi hỏi lại và ghi đè.
///
/// Khoá gồm cả người dùng: tài khoản khác đăng nhập trên máy không dùng lại.
final class MessageAttachmentMemo {
  MessageAttachmentMemo({this.maxEntries = 2000}) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashMap<String, List<MessageAttachment>> _entries =
      LinkedHashMap();

  /// Khoá của một tin; `null` (không nhớ) khi chưa biết người dùng.
  static String? keyFor({
    required String? userId,
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    final user = userId?.trim() ?? '';
    if (user.isEmpty || messageId.trim().isEmpty) return null;
    return '$user\u0000$workspaceId\u0000$channelId\u0000$messageId';
  }

  List<MessageAttachment>? read(String? key) {
    if (key == null) return null;
    final attachments = _entries.remove(key);
    if (attachments == null) return null;
    // Vừa dùng: đưa xuống cuối để bị bỏ sau cùng.
    _entries[key] = attachments;
    return attachments;
  }

  /// Ghi kết quả của một tin; danh sách rỗng không ghi (tin có thể còn đang
  /// được gắn tệp, lần sau hỏi lại).
  void write(String? key, List<MessageAttachment> attachments) {
    if (key == null || attachments.isEmpty) return;
    _entries.remove(key);
    _entries[key] = List.unmodifiable(attachments);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Bỏ mục nhớ của một tin (tin bị thu hồi / xoá); trả tệp đã nhớ, nếu có.
  List<MessageAttachment>? remove(String? key) {
    if (key == null) return null;
    return _entries.remove(key);
  }

  void clear() => _entries.clear();
}

/// Gắn tệp cho các tin có tệp (danh sách tin không kèm tệp): tin đã hỏi trước
/// đó lấy từ [memo], chỉ hỏi máy chủ ([fetch]) cho tin chưa biết.
final class MessageAttachmentHydrator {
  const MessageAttachmentHydrator({required this.fetch, this.memo});

  /// Hỏi máy chủ tệp của một tin; `null` khi lỗi.
  final Future<List<MessageAttachment>?> Function(ChatMessage message) fetch;
  final MessageAttachmentMemo? memo;

  /// Lần lượt trả các lô `mã tin → tệp`: lô đầu là mọi tin đã nhớ (gắn ngay),
  /// sau đó mỗi tin hỏi máy chủ thành công là một lô. Nơi gọi ngừng nghe hoặc
  /// [isActive] trả `false` (màn hình đã đóng) thì không hỏi tiếp tin còn lại.
  Stream<Map<String, List<MessageAttachment>>> hydrate(
    List<ChatMessage> targets, {
    required String? userId,
    bool Function()? isActive,
  }) async* {
    String? keyOf(ChatMessage message) => MessageAttachmentMemo.keyFor(
      userId: userId,
      workspaceId: message.workspaceId,
      channelId: message.channelId,
      messageId: message.id,
    );

    final remembered = <String, List<MessageAttachment>>{};
    final missing = <ChatMessage>[];
    for (final message in targets) {
      final attachments = memo?.read(keyOf(message));
      if (attachments != null) {
        remembered[message.id] = attachments;
      } else {
        missing.add(message);
      }
    }
    if (remembered.isNotEmpty) yield remembered;

    for (final message in missing) {
      final attachments = await fetch(message);
      if (isActive != null && !isActive()) return;
      if (attachments == null || attachments.isEmpty) continue;
      memo?.write(keyOf(message), attachments);
      yield {message.id: attachments};
    }
  }
}
