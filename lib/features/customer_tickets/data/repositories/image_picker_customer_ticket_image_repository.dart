import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/customer_ticket.dart';
import '../../domain/repositories/customer_ticket_repository.dart';

/// Chọn ảnh gửi kèm trả lời ticket. Ảnh được thu nhỏ / nén ngay lúc chọn
/// (cạnh dài tối đa 1600 px, chất lượng 80) để vừa giới hạn 5 MB của máy chủ.
final class ImagePickerCustomerTicketImageRepository
    implements CustomerTicketImagePickerRepository {
  ImagePickerCustomerTicketImageRepository({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _maxDimension = 1600.0;
  static const _quality = 80;

  @override
  Future<Result<List<CustomerTicketImageUpload>>> pick({
    required CustomerTicketImageSource source,
    required int limit,
  }) async {
    if (limit <= 0) return const Success([]);
    try {
      final files = switch (source) {
        CustomerTicketImageSource.camera => [
          ?await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: _maxDimension,
            maxHeight: _maxDimension,
            imageQuality: _quality,
          ),
        ],
        CustomerTicketImageSource.gallery => await _picker.pickMultiImage(
          maxWidth: _maxDimension,
          maxHeight: _maxDimension,
          imageQuality: _quality,
          limit: limit,
        ),
      };
      final images = <CustomerTicketImageUpload>[];
      for (final file in files.take(limit)) {
        final name = file.name.trim().isEmpty
            ? _fallbackName(file.path)
            : file.name.trim();
        images.add(
          CustomerTicketImageUpload(
            name: name,
            mimeType: _mimeType(file.mimeType, name),
            bytes: await file.readAsBytes(),
          ),
        );
      }
      return Success(images);
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không chọn được ảnh. Kiểm tra quyền camera / thư viện ảnh.',
          code: 'CUSTOMER_TICKET_IMAGE_PICK_FAILED',
          cause: error,
        ),
      );
    }
  }
}

String _mimeType(String? reported, String name) {
  final mime = reported?.trim().toLowerCase();
  if (mime != null && mime.startsWith('image/')) {
    return mime == 'image/jpg' ? 'image/jpeg' : mime;
  }
  final extension = name.contains('.')
      ? name.split('.').last.trim().toLowerCase()
      : '';
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    _ => 'application/octet-stream',
  };
}

String _fallbackName(String path) {
  final name = path.replaceAll('\\', '/').split('/').last.trim();
  return name.isEmpty
      ? 'anh_${DateTime.now().millisecondsSinceEpoch}.jpg'
      : name;
}
