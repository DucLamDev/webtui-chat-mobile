import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../domain/entities/chat_message.dart';

/// Cách đặt khoá / tên tệp trong kho đệm cho tệp đính kèm của tin nhắn.
///
/// Widget media (tải / phát / lưu) và lớp xoá tệp khi tin bị thu hồi
/// (`AttachmentCacheEvictor`) cùng dùng các hàm này: đổi cách đặt khoá ở một
/// chỗ thì cả hai đổi theo, không lệch nhau.

/// Địa chỉ tải tệp gốc của [attachment]; `null` khi đường dẫn không an toàn.
Uri? attachmentDownloadUri(MessageAttachment attachment, Uri? apiBaseUri) {
  return _resolveAttachmentUri(attachment.file.downloadPath, apiBaseUri);
}

/// Địa chỉ ảnh thu nhỏ (ảnh bìa video); null nếu máy chủ chưa có.
Uri? attachmentThumbnailUri(MessageAttachment attachment, Uri? apiBaseUri) {
  final raw = attachment.file.thumbnailUrl;
  if (raw == null) return null;
  return _resolveAttachmentUri(raw, apiBaseUri);
}

Uri? _resolveAttachmentUri(String raw, Uri? apiBaseUri) {
  final rawPath = raw.trim();
  if (rawPath.isEmpty) return null;
  final uri = Uri.tryParse(rawPath);
  if (uri == null) return null;
  final resolved = uri.hasScheme ? uri : apiBaseUri?.resolve(rawPath);
  if (resolved == null ||
      !redirectSafeHttpUriAllowed(resolved) ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty ||
      resolved.fragment.isNotEmpty) {
    return null;
  }
  return resolved;
}

/// Khoá kho của địa chỉ tải [uri]; [variant] phân biệt các bản khác nhau của
/// cùng địa chỉ (vd. cỡ tệp của ảnh).
String attachmentMediaCacheKey(Uri uri, {String variant = ''}) {
  return variant.isEmpty ? '$uri' : '$uri|$variant';
}

/// Biến thể khoá của ảnh trong tin (ảnh gốc và ảnh thu nhỏ): cỡ tệp, để ảnh
/// được thay ở cùng địa chỉ không đọc nhầm bản cũ.
String attachmentImageCacheVariant(MessageAttachment attachment) {
  return '${attachment.file.byteSize}';
}

/// Khoá tệp WAV giải mã từ tin thoại WebM / Ogg (iPhone) trong thư mục
/// `playable-audio` của kho (xem `playableAudioFile`).
String attachmentPlayableAudioCacheKey(MessageAttachment attachment) {
  return 'chat-${attachment.fileId}';
}

String _normalizedMime(MessageAttachment attachment) =>
    attachment.file.mimeType.trim().toLowerCase();

/// Thư viện ảnh nhận tệp theo đuôi tên: tên gốc thiếu đuôi thì thêm theo loại
/// tệp. Cũng là tên gốc của tệp video trong kho (giữ đuôi để trình phát nhận).
String galleryFileName(MessageAttachment attachment) {
  final name = attachment.file.name.trim();
  if (RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(name)) return name;
  final extension = switch (_normalizedMime(attachment)) {
    'image/jpeg' || 'image/jpg' => '.jpg',
    'image/png' => '.png',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    'image/heic' => '.heic',
    'image/heif' => '.heif',
    'video/quicktime' => '.mov',
    'video/webm' => '.webm',
    final mime when mime.startsWith('video/') => '.mp4',
    _ => '.jpg',
  };
  return '${name.isEmpty ? 'media' : name}$extension';
}
