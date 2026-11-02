import 'dart:typed_data';

import '../../../../core/network/bounded_image_request_pool.dart';
import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../domain/entities/customer_ticket.dart';
import '../../domain/repositories/customer_ticket_repository.dart';

/// Ảnh khách gửi trong ticket là URL tuyệt đối trên tên miền của hệ thống
/// order, không phải máy chủ chat. Tải như ảnh công khai: KHÔNG gắn token đăng
/// nhập (kể cả khi trùng tên miền), không theo chuyển hướng, chỉ HTTPS, tối đa
/// 5 MB; giải mã bằng `WebTuiOwnedDecodedImage` ở giao diện.
final class PublicCustomerTicketImageRepository
    implements CustomerTicketImageRepository {
  PublicCustomerTicketImageRepository({
    RedirectSafeFileDownloader downloader = const RedirectSafeFileDownloader(),
    BoundedImageRequestPool? pool,
  }) : _downloader = downloader,
       _pool =
           pool ??
           BoundedImageRequestPool(
             maxEntries: 24,
             maxCacheBytes: 16 * 1024 * 1024,
           );

  final RedirectSafeFileDownloader _downloader;
  final BoundedImageRequestPool _pool;

  @override
  Future<Uint8List?> loadImage(String url) async {
    final uri = customerTicketImageUri(url);
    if (uri == null) return null;
    try {
      return await _pool.load(
        key: uri.toString(),
        maxBytes: customerTicketMaxImageBytes,
        loader: () => _downloader.downloadBytes(
          uri: uri,
          maxBytes: customerTicketMaxImageBytes,
          accept: 'image/*',
          isStillCurrent: () async => true,
        ),
      );
    } on Object {
      return null;
    }
  }

  void clear() => _pool.clear();
}

/// Chỉ nhận URL tuyệt đối HTTPS (http chỉ cho máy cục bộ khi phát triển),
/// không kèm thông tin đăng nhập trong URL.
Uri? customerTicketImageUri(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !redirectSafeHttpUriAllowed(uri)) {
    return null;
  }
  return uri.removeFragment();
}
