import '../../../l10n/app_strings.dart';

/// Dòng xem trước của NHÓM trong danh sách Tin nhắn, kiểu Zalo:
/// "Tên: nội dung", tin của mình "Bạn: nội dung".
///
/// Trả `null` khi không có gì để hiện (máy chủ cũ không trả tin cuối, tin rỗng):
/// nơi gọi giữ cách cũ (mô tả nhóm).
String? groupLastMessagePreview({
  required String kind,
  required String body,
  String? senderId,
  String? senderName,
  String? currentUserId,
  bool isMine = false,
  bool secret = false,
  bool hasAttachments = false,
}) {
  final name = (senderName ?? '').trim();
  final me = (currentUserId ?? '').trim();
  final sender = (senderId ?? '').trim();
  final mine = isMine || (me.isNotEmpty && sender == me);
  // Tin bí mật: không lộ nội dung, cũng không ghép tên.
  if (secret) return tr('Tin nhắn bí mật', 'Secret message');

  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final isSystemLike = kind == 'system' || kind == 'event';
  final prefix = isSystemLike
      ? ''
      : mine
      ? tr('Bạn', 'You')
      : name;

  if (text.isEmpty) {
    if (kind != 'file' && !hasAttachments) return null;
    if (prefix.isEmpty) return tr('Đã gửi một tệp', 'Sent a file');
    return '$prefix: ${tr('đã gửi một tệp', 'sent a file')}';
  }
  return prefix.isEmpty ? text : '$prefix: $text';
}
