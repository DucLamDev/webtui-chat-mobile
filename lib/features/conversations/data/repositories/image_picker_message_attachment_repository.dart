import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_attachment_repository.dart';

final class ImagePickerMessageAttachmentRepository
    implements MessageAttachmentPickerRepository {
  ImagePickerMessageAttachmentRepository({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Result<PickedMessageAttachment?>> pick(
    MessageAttachmentPickSource source,
  ) async {
    try {
      if (source == MessageAttachmentPickSource.file) {
        return _pickFile();
      }
      if (source == MessageAttachmentPickSource.video) {
        return _pickVideo();
      }
      final image = await _picker.pickImage(
        source: source == MessageAttachmentPickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 82,
        maxHeight: 1600,
        maxWidth: 1600,
      );
      if (image == null) {
        return const Success(null);
      }
      final file = File(image.path);
      final stat = await file.stat();
      return Success(
        PickedMessageAttachment(
          path: image.path,
          fileName: image.name.isEmpty ? _fallbackName(image.path) : image.name,
          mimeType: image.mimeType ?? _mimeFromPath(image.path),
          byteSize: stat.size,
          kind: MessageAttachmentKind.image,
        ),
      );
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message:
              'Không thể chọn tệp. Kiểm tra quyền camera/thư viện rồi thử lại.',
          code: 'MESSAGE_ATTACHMENT_PICK_FAILED',
          cause: error,
        ),
      );
    }
  }

  Future<Result<PickedMessageAttachment?>> _pickVideo() async {
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 10),
    );
    if (video == null) {
      return const Success(null);
    }
    final stat = await File(video.path).stat();
    return Success(
      PickedMessageAttachment(
        path: video.path,
        fileName: video.name.isEmpty ? _fallbackName(video.path) : video.name,
        mimeType: video.mimeType ?? _mimeFromPath(video.path),
        byteSize: stat.size,
        kind: MessageAttachmentKind.video,
      ),
    );
  }

  Future<Result<PickedMessageAttachment?>> _pickFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const [
        'aac',
        'doc',
        'docx',
        'json',
        'm4a',
        'm4v',
        'mkv',
        'mov',
        'mp3',
        'mp4',
        'ogg',
        'pdf',
        'ppt',
        'pptx',
        'txt',
        'wav',
        'webm',
        'xls',
        'xlsx',
        'zip',
      ],
    );
    final picked = result?.files.single;
    final path = picked?.path?.trim();
    if (picked == null || path == null || path.isEmpty) {
      return const Success(null);
    }
    final mimeType = _mimeFromPath(picked.name);
    return Success(
      PickedMessageAttachment(
        path: path,
        fileName: picked.name,
        mimeType: mimeType,
        byteSize: picked.size,
        kind: _kindForMime(mimeType),
      ),
    );
  }
}

String _fallbackName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  return name.isEmpty
      ? 'image_${DateTime.now().millisecondsSinceEpoch}.jpg'
      : name;
}

String _mimeFromPath(String path) {
  final extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'aac' => 'audio/aac',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'gif' => 'image/gif',
    'heic' || 'heif' => 'image/heic',
    'jpg' || 'jpeg' => 'image/jpeg',
    'json' => 'application/json',
    'm4a' => 'audio/mp4',
    'm4v' => 'video/x-m4v',
    'mkv' => 'video/x-matroska',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'mp4' => 'video/mp4',
    'ogg' => 'audio/ogg',
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    'wav' => 'audio/wav',
    'webm' => 'video/webm',
    'webp' => 'image/webp',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

MessageAttachmentKind _kindForMime(String mimeType) {
  if (mimeType.startsWith('image/')) return MessageAttachmentKind.image;
  if (mimeType.startsWith('video/')) return MessageAttachmentKind.video;
  if (mimeType.startsWith('audio/')) return MessageAttachmentKind.audio;
  return MessageAttachmentKind.file;
}
