import 'dart:async';
import 'dart:io';

import '../../../../core/error/failure.dart';
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
    UploadVideoThumbnailUseCase? uploadThumbnail,
  }) : _uploadAttachment = uploadAttachment,
       _compressor = compressor,
       _compressedPathFor = compressedPathFor,
       _uploadThumbnail = uploadThumbnail;

  /// Video nhỏ hơn mức này gửi luôn bản gốc.
  static const int minCompressBytes = 4 * 1024 * 1024;

  /// Bản nén phải nhỏ hơn bản gốc ít nhất 15 %, nếu không gửi bản gốc.
  static const double minSavingRatio = 0.15;

  final UploadMessageAttachmentUseCase _uploadAttachment;
  final VideoCompressor _compressor;
  final Future<String> Function(String clientAttachmentId) _compressedPathFor;

  /// Gửi ảnh bìa sau khi tải video; null thì không gửi ảnh bìa.
  final UploadVideoThumbnailUseCase? _uploadThumbnail;

  final Map<String, _Job> _running = {};
  final Map<String, UploadedMessageFile> _done = {};
  final Map<String, MessageMediaUploadProgress> _progress = {};
  final StreamController<MessageMediaUploadProgress> _updates =
      StreamController<MessageMediaUploadProgress>.broadcast();

  @override
  Future<Result<UploadedMessageFile>> upload({
    required String workspaceId,
    required String clientAttachmentId,
    required PickedMessageAttachment attachment,
    void Function(MessageMediaUploadProgress progress)? onProgress,
  }) {
    final key = '$workspaceId|$clientAttachmentId';
    final cached = _done[key];
    if (cached != null) {
      onProgress?.call(
        MessageMediaUploadProgress(
          clientAttachmentId: clientAttachmentId,
          stage: MessageMediaUploadStage.done,
          progress: 1,
        ),
      );
      return Future.value(Success(cached));
    }
    final running = _running[key];
    if (running != null) {
      if (onProgress != null) {
        running.listeners.add(onProgress);
        final current = _progress[clientAttachmentId];
        if (current != null) onProgress(current);
      }
      return running.future;
    }
    final job = _Job();
    if (onProgress != null) job.listeners.add(onProgress);
    _running[key] = job;
    job.future = _run(
      key: key,
      job: job,
      workspaceId: workspaceId,
      clientAttachmentId: clientAttachmentId,
      attachment: attachment,
    );
    return job.future;
  }

  void _emit(
    _Job job,
    String id,
    MessageMediaUploadStage stage,
    double progress,
  ) {
    final value = MessageMediaUploadProgress(
      clientAttachmentId: id,
      stage: stage,
      progress: progress.clamp(0.0, 1.0).toDouble(),
    );
    _progress[id] = value;
    if (!_updates.isClosed) _updates.add(value);
    for (final listener in List.of(job.listeners)) {
      listener(value);
    }
  }

  Future<Result<UploadedMessageFile>> _run({
    required String key,
    required _Job job,
    required String workspaceId,
    required String clientAttachmentId,
    required PickedMessageAttachment attachment,
  }) async {
    final id = clientAttachmentId;
    String? compressedPath;
    try {
      if (!await File(attachment.path).exists()) {
        const failure = Failure(
          kind: FailureKind.validation,
          code: 'ATTACHMENT_FILE_MISSING',
          message: 'Không còn tệp trên máy, hãy chọn lại.',
        );
        _emit(job, id, MessageMediaUploadStage.failed, 0);
        return const FailureResult(failure);
      }

      var toUpload = attachment;
      final shouldCompress =
          attachment.compressVideo &&
          attachment.kind == MessageAttachmentKind.video &&
          attachment.byteSize >= minCompressBytes;
      if (shouldCompress) {
        _emit(job, id, MessageMediaUploadStage.compressing, 0);
        final compressed = await _compress(job, id, attachment);
        if (compressed != null) {
          compressedPath = compressed.path;
          toUpload = PickedMessageAttachment(
            path: compressed.path,
            fileName: _mp4Name(attachment.fileName),
            mimeType: 'video/mp4',
            byteSize: compressed.byteSize,
            kind: attachment.kind,
            voice: attachment.voice,
            compressVideo: false,
          );
        }
      }

      final base = shouldCompress ? _compressShare : 0.0;
      _emit(job, id, MessageMediaUploadStage.uploading, base);
      final result = await _uploadAttachment.execute(
        workspaceId: workspaceId,
        attachment: toUpload,
        onProgress: (value) => _emit(
          job,
          id,
          MessageMediaUploadStage.uploading,
          base + value.clamp(0.0, 1.0) * (1 - base),
        ),
      );
      switch (result) {
        case Success<UploadedMessageFile>(:final value):
          var finalFile = value;
          if (attachment.kind == MessageAttachmentKind.video) {
            // Ảnh bìa lấy từ tệp gốc trên máy; lỗi thì bỏ qua.
            finalFile = await _attachPoster(workspaceId, id, attachment, value);
          }
          _done[key] = finalFile;
          if (compressedPath != null) await _deleteQuietly(compressedPath);
          _emit(job, id, MessageMediaUploadStage.done, 1);
          return Success(finalFile);
        case FailureResult<UploadedMessageFile>():
          _emit(
            job,
            id,
            MessageMediaUploadStage.failed,
            _progress[id]?.progress ?? 0,
          );
      }
      return result;
    } catch (error) {
      _emit(
        job,
        id,
        MessageMediaUploadStage.failed,
        _progress[id]?.progress ?? 0,
      );
      return FailureResult(
        Failure(
          kind: FailureKind.unknown,
          message: 'Không tải được tệp lên, hãy thử lại.',
          cause: error,
        ),
      );
    } finally {
      _running.remove(key);
    }
  }

  static const double _compressShare = 0.3;

  /// Lấy ảnh bìa từ video gốc và gửi lên; mọi lỗi đều bỏ qua và trả [file].
  Future<UploadedMessageFile> _attachPoster(
    String workspaceId,
    String id,
    PickedMessageAttachment original,
    UploadedMessageFile file,
  ) async {
    final upload = _uploadThumbnail;
    if (upload == null || file.thumbnailUrl != null) return file;
    String? posterPath;
    String? resultPath;
    try {
      final base = await _compressedPathFor(id);
      posterPath = '$base.poster.jpg';
      final poster = await _compressor.poster(
        inputPath: original.path,
        outputPath: posterPath,
      );
      if (poster == null) return file;
      resultPath = poster.path;
      final result = await upload.execute(
        workspaceId: workspaceId,
        fileId: file.id,
        thumbnailPath: poster.path,
        durationMs: poster.durationMs > 0 ? poster.durationMs : null,
        width: poster.width > 0 ? poster.width : null,
        height: poster.height > 0 ? poster.height : null,
      );
      if (result is Success<UploadedMessageFile>) {
        final updated = result.value;
        return updated.copyWith(
          width: updated.width ?? (poster.width > 0 ? poster.width : null),
          height: updated.height ?? (poster.height > 0 ? poster.height : null),
          durationMs:
              updated.durationMs ??
              (poster.durationMs > 0 ? poster.durationMs : null),
        );
      }
      return file;
    } catch (_) {
      return file;
    } finally {
      if (posterPath != null) await _deleteQuietly(posterPath);
      if (resultPath != null && resultPath != posterPath) {
        await _deleteQuietly(resultPath);
      }
    }
  }

  Future<CompressedVideo?> _compress(
    _Job job,
    String id,
    PickedMessageAttachment attachment,
  ) async {
    String? outputPath;
    try {
      outputPath = await _compressedPathFor(id);
      final existing = File(outputPath);
      if (await existing.exists()) {
        final size = await existing.length();
        if (size > 0) return CompressedVideo(path: outputPath, byteSize: size);
      }
      final result = await _compressor.compress(
        inputPath: attachment.path,
        outputPath: outputPath,
        onProgress: (value) => _emit(
          job,
          id,
          MessageMediaUploadStage.compressing,
          value.clamp(0.0, 1.0) * _compressShare,
        ),
      );
      if (result != null &&
          result.byteSize > 0 &&
          result.byteSize <= attachment.byteSize * (1 - minSavingRatio)) {
        return result;
      }
      await _deleteQuietly(result?.path ?? outputPath);
      if (result != null && result.path != outputPath) {
        await _deleteQuietly(outputPath);
      }
      return null;
    } catch (_) {
      if (outputPath != null) await _deleteQuietly(outputPath);
      return null;
    }
  }

  static String _mp4Name(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return '${stem.isEmpty ? 'video' : stem}.mp4';
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Không xoá được thì bỏ qua.
    }
  }

  @override
  MessageMediaUploadProgress? progressOf(String clientAttachmentId) =>
      _progress[clientAttachmentId];

  @override
  Stream<MessageMediaUploadProgress> get progressUpdates => _updates.stream;

  @override
  void dispose() {
    unawaited(_updates.close());
  }
}

final class _Job {
  final List<void Function(MessageMediaUploadProgress)> listeners = [];
  late Future<Result<UploadedMessageFile>> future;
}
