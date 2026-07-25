import 'dart:io';

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
      final image = await _picker.pickImage(
        source: source == MessageAttachmentPickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 86,
        maxWidth: 1920,
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
              'Không thể chọn ảnh. Kiểm tra quyền camera/thư viện rồi thử lại.',
          code: 'MESSAGE_ATTACHMENT_PICK_FAILED',
          cause: error,
        ),
      );
    }
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
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    return 'image/heic';
  }
  return 'image/jpeg';
}
