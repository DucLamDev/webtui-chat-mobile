/// Nơi lưu video đã nén chờ tải lên (thư mục tạm của app).
final class CompressedVideoFileStore {
  const CompressedVideoFileStore();

  /// Đường dẫn tệp nén của [clientAttachmentId] (tên tệp đã lọc ký tự, không
  /// thoát ra ngoài thư mục riêng).
  Future<String> pathFor(String clientAttachmentId) {
    // TODO(khung): agent phần tải lên cài đặt.
    throw UnimplementedError();
  }
}
