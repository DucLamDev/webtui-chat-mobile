/// Loại mạng đang dùng, chỉ đủ để quyết định có tự tải ảnh / video không.
enum MediaNetworkType {
  /// Wi-Fi hoặc mạng dây: tải thoải mái.
  wifi,

  /// Chỉ có dữ liệu di động (4G / 5G...): tốn tiền mạng của người dùng.
  cellular,

  /// Mạng khác (VPN, Bluetooth, vệ tinh...) không kèm Wi-Fi / di động.
  other,

  /// Không có mạng.
  offline,

  /// Không đọc được (máy không hỗ trợ, lỗi): coi như không phải di động.
  unknown,
}

/// Đọc loại mạng hiện tại (bọc thư viện bên ngoài để test thay được).
abstract interface class NetworkTypeReader {
  Future<MediaNetworkType> current();
}

/// Video phát dần đã xem xong được lưu ngầm vào kho khi cỡ tối đa mức này.
const int backgroundVideoCacheMaxBytes = 30 * 1024 * 1024;

/// Ảnh trong tin chưa có trên máy có được tự tải không: chỉ chặn khi người
/// dùng tắt "Tự tải ảnh khi dùng dữ liệu di động" và đang dùng dữ liệu di động.
bool shouldAutoDownloadImage({
  required bool allowOnCellular,
  required MediaNetworkType network,
}) {
  return allowOnCellular || network != MediaNetworkType.cellular;
}

/// Video phát dần (chưa có trong kho) vừa phát được có được tải ngầm vào kho
/// để xem lại không cần mạng: không phải khung xem trước, cỡ đã biết và tối đa
/// [backgroundVideoCacheMaxBytes], đang dùng Wi-Fi hoặc người dùng cho phép
/// tự tải khi dùng dữ liệu di động.
bool shouldBackgroundCacheVideo({
  required int byteSize,
  required bool previewOnly,
  required bool allowOnCellular,
  required MediaNetworkType network,
}) {
  if (previewOnly) return false;
  if (byteSize <= 0 || byteSize > backgroundVideoCacheMaxBytes) return false;
  return allowOnCellular || network == MediaNetworkType.wifi;
}

/// Gộp công tắc của người dùng với loại mạng hiện tại. Chỉ hỏi loại mạng khi
/// công tắc tắt (bật thì luôn được tải, không cần biết mạng).
final class MediaAutoDownloadPolicy {
  const MediaAutoDownloadPolicy({
    required this.allowOnCellular,
    required NetworkTypeReader networkTypeReader,
  }) : _networkTypeReader = networkTypeReader;

  /// Công tắc "Tự tải ảnh khi dùng dữ liệu di động" trong Thiết lập.
  final bool allowOnCellular;
  final NetworkTypeReader _networkTypeReader;

  Future<MediaNetworkType> _network() async {
    try {
      return await _networkTypeReader.current();
    } on Object {
      return MediaNetworkType.unknown;
    }
  }

  Future<bool> canAutoDownloadImage() async {
    if (allowOnCellular) return true;
    return shouldAutoDownloadImage(
      allowOnCellular: allowOnCellular,
      network: await _network(),
    );
  }

  Future<bool> canBackgroundCacheVideo({
    required int byteSize,
    required bool previewOnly,
  }) async {
    final basic = shouldBackgroundCacheVideo(
      byteSize: byteSize,
      previewOnly: previewOnly,
      allowOnCellular: true,
      network: MediaNetworkType.wifi,
    );
    if (!basic) return false;
    if (allowOnCellular) return true;
    return shouldBackgroundCacheVideo(
      byteSize: byteSize,
      previewOnly: previewOnly,
      allowOnCellular: allowOnCellular,
      network: await _network(),
    );
  }
}
