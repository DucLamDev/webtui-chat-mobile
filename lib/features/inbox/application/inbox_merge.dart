import '../domain/entities/inbox.dart';

/// Gộp [incoming] vào danh sách tin (cũ → mới) mà không trùng: cùng `id`, hoặc
/// cùng `client_message_id` (tin gửi cục bộ được máy chủ xác nhận thì thay
/// chỗ tin cục bộ).
List<InboxMessage> mergeInboxMessages(
  List<InboxMessage> existing,
  Iterable<InboxMessage> incoming,
) {
  final result = [...existing];
  for (final message in incoming) {
    final index = result.indexWhere((item) => _sameMessage(item, message));
    if (index >= 0) {
      result[index] = message;
    } else {
      result.add(message);
    }
  }
  // sort ổn định: cùng giờ giữ thứ tự nhận.
  final indexed = [for (var i = 0; i < result.length; i++) (i, result[i])];
  indexed.sort((a, b) {
    final byTime = a.$2.createdAt.compareTo(b.$2.createdAt);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

bool _sameMessage(InboxMessage a, InboxMessage b) {
  if (a.id.isNotEmpty && a.id == b.id) return true;
  return a.clientMessageId.isNotEmpty && a.clientMessageId == b.clientMessageId;
}

/// Đưa [updated] vào danh sách hội thoại (mới nhất trước). [matches] quyết
/// định hội thoại còn thuộc bộ lọc hiện tại không; không thì bị bỏ khỏi danh
/// sách.
List<InboxConversation> upsertInboxConversation(
  List<InboxConversation> items,
  InboxConversation updated, {
  required bool Function(InboxConversation) matches,
}) {
  final rest = items.where((item) => item.id != updated.id).toList();
  if (!matches(updated)) return rest;
  final existed = rest.length != items.length;
  final at = updated.lastMessageAt?.millisecondsSinceEpoch ?? 0;
  var index = rest.indexWhere(
    (item) => (item.lastMessageAt?.millisecondsSinceEpoch ?? 0) <= at,
  );
  if (index < 0) {
    // Cũ hơn mọi mục đang có: chỉ thêm cuối nếu đã có sẵn (đã tải tới đó),
    // còn hội thoại mới thì để trang sau tải.
    if (!existed && rest.isNotEmpty) return items;
    index = rest.length;
  }
  return [...rest.sublist(0, index), updated, ...rest.sublist(index)];
}
