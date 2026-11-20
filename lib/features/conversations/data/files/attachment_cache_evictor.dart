import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../../core/audio/playable_audio.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/entities/chat_message.dart';
import 'attachment_media_cache_keys.dart';
import 'scoped_attachment_file_store.dart';

/// Xoá khỏi kho đệm trên máy mọi tệp đã lưu của các tệp đính kèm một tin
/// (tin bị thu hồi / xoá / hết hạn), như Zalo: không chờ kho tự dọn sau 7 ngày.
///
/// Tính đúng tệp kho mà widget media đã ghi (cùng hàm đặt khoá trong
/// `attachment_media_cache_keys.dart`): ảnh gốc, ảnh thu nhỏ, ảnh bìa video,
/// video, tin thoại + WAV giải mã, tệp (mở bằng app khác / lưu vào thư viện).
/// Không đụng tệp của tin khác.
final class AttachmentCacheEvictor {
  const AttachmentCacheEvictor({
    ScopedAttachmentFileStore store = const ScopedAttachmentFileStore(),
  }) : _store = store;

  final ScopedAttachmentFileStore _store;

  /// Mọi tệp kho có thể có của [attachments] (tệp chưa từng tải thì không có
  /// trên máy, xoá bỏ qua).
  Future<List<File>> cacheFilesFor({
    required InstanceScope instanceScope,
    required String accountKey,
    required Uri? apiBaseUri,
    required List<MessageAttachment> attachments,
  }) async {
    Future<File> cacheFile(
      String purpose,
      Uri uri, {
      String variant = '',
      String originalName = '',
    }) {
      return _store.cacheFileFor(
        instanceScope: instanceScope,
        accountKey: accountKey,
        purpose: purpose,
        key: attachmentMediaCacheKey(uri, variant: variant),
        originalName: originalName,
      );
    }

    final files = <String, File>{};
    void add(File file) => files[file.path] = file;

    for (final attachment in attachments) {
      final download = attachmentDownloadUri(attachment, apiBaseUri);
      final thumbnail = attachmentThumbnailUri(attachment, apiBaseUri);
      final imageVariant = attachmentImageCacheVariant(attachment);
      final name = attachment.file.name;
      final galleryName = galleryFileName(attachment);
      // Không phân theo loại tệp: tin có thể được hiện theo nhiều cách (ảnh
      // mở bằng app khác, video lưu vào thư viện...); tệp không có thì bỏ qua.
      if (download != null) {
        add(await cacheFile('image', download, variant: imageVariant));
        add(await cacheFile('video', download, originalName: galleryName));
        add(await cacheFile('voice', download, originalName: name));
        add(await cacheFile('file', download, originalName: name));
        add(await cacheFile('file', download, originalName: galleryName));
      }
      if (thumbnail != null) {
        // Ảnh thu nhỏ của ảnh (kèm cỡ tệp) và ảnh bìa video (không kèm).
        add(await cacheFile('image', thumbnail, variant: imageVariant));
        add(await cacheFile('image', thumbnail));
      }
      if (attachment.fileId.trim().isNotEmpty) {
        final playable = await _store.cacheDirectoryFor(
          instanceScope: instanceScope,
          accountKey: accountKey,
          purpose: 'playable-audio',
        );
        add(
          File(
            path.join(
              playable.path,
              playableAudioCacheFileName(
                attachmentPlayableAudioCacheKey(attachment),
              ),
            ),
          ),
        );
      }
    }
    return files.values.toList(growable: false);
  }

  /// Xoá các tệp kho của [attachments]; trả số tệp đã xoá. Lỗi từng tệp (đang
  /// mở, đã bị dọn) chỉ bỏ qua.
  Future<int> evict({
    required InstanceScope instanceScope,
    required String accountKey,
    required Uri? apiBaseUri,
    required List<MessageAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return 0;
    final files = await cacheFilesFor(
      instanceScope: instanceScope,
      accountKey: accountKey,
      apiBaseUri: apiBaseUri,
      attachments: attachments,
    );
    var deleted = 0;
    for (final file in files) {
      try {
        await file.delete();
        deleted += 1;
      } on FileSystemException {
        // Chưa từng tải / đã bị dọn: không có gì để xoá.
      }
    }
    return deleted;
  }
}
