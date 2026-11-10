import 'dart:async';

import '../../../../core/platform/video_compressor.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import 'message_attachment_use_cases.dart';

enum MessageMediaUploadStage {
  /// Đang nén video trên máy.
  compressing,

  /// Đang tải lên máy chủ.
  uploading,

  /// Đã tải xong.
  done,

  /// Lỗi (có thể gọi lại `upload` cùng id để thử lại).
  failed,
}

/// Tiến độ của một tệp đính kèm, theo `clientAttachmentId`.
final class MessageMediaUploadProgress {
  const MessageMediaUploadProgress({
    required this.clientAttachmentId,
    required this.stage,
    required this.progress,
  });

  final String clientAttachmentId;
  final MessageMediaUploadStage stage;

  /// Tiến độ chung 0..1 (có nén: nén chiếm 0..0,3, tải lên 0,3..1).
  final double progress;
}

/// Bộ "nén + tải lên" dùng chung toàn app (sống suốt phiên, không gắn với
/// phòng chat), để thoát phòng vẫn tải tiếp và không tải trùng một tệp.
abstract interface class MessageMediaUploader {
  /// Nén (nếu là video cần nén) rồi tải [attachment] lên.
  ///
  /// - Cùng [clientAttachmentId] đang chạy: dùng chung việc đang chạy (không
  ///   tải lại), [onProgress] vẫn nhận tiến độ.
  /// - Đã tải xong trước đó trong phiên app: trả ngay kết quả cũ.
  /// - Lỗi: lần gọi sau với cùng id chạy lại (tải tiếp phần còn thiếu).
  Future<Result<UploadedMessageFile>> upload({
    required String workspaceId,
    required String clientAttachmentId,
    required PickedMessageAttachment attachment,
    void Function(MessageMediaUploadProgress progress)? onProgress,
  });

  /// Tiến độ mới nhất của [clientAttachmentId] (null nếu chưa từng chạy).
  MessageMediaUploadProgress? progressOf(String clientAttachmentId);

  /// Mọi thay đổi tiến độ (cho giao diện nghe chung).
  Stream<MessageMediaUploadProgress> get progressUpdates;

  void dispose();
}

/// Cài đặt mặc định.
final class DefaultMessageMediaUploader implements MessageMediaUploader {
  DefaultMessageMediaUploader({
    required UploadMessageAttachmentUseCase uploadAttachment,
    required VideoCompressor compressor,
    required Future<String> Function(String clientAttachmentId)
    compressedPathFor,
  }) : _uploadAttachment = uploadAttachment,
       _compressor = compressor,
       _compressedPathFor = compressedPathFor;

  /// Video nhỏ hơn mức này gửi luôn bản gốc.
  static const int minCompressBytes = 4 * 1024 * 1024;

  /// Bản nén phải nhỏ hơn bản gốc ít nhất 15 %, nếu không gửi bản gốc.
  static const double minSavingRatio = 0.15;

  // ignore: unused_field
  final UploadMessageAttachmentUseCase _uploadAttachment;
  // ignore: unused_field
  final VideoCompressor _compressor;
  // ignore: unused_field
  final Future<String> Function(String clientAttachmentId) _compressedPathFor;

  @override
  Future<Result<UploadedMessageFile>> upload({
    required String workspaceId,
    required String clientAttachmentId,
    required PickedMessageAttachment attachment,
    void Function(MessageMediaUploadProgress progress)? onProgress,
  }) {
    // TODO(khung): agent phần tải lên cài đặt.
    throw UnimplementedError();
  }

  @override
  MessageMediaUploadProgress? progressOf(String clientAttachmentId) {
    // TODO(khung): agent phần tải lên cài đặt.
    throw UnimplementedError();
  }

  @override
  Stream<MessageMediaUploadProgress> get progressUpdates {
    // TODO(khung): agent phần tải lên cài đặt.
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
