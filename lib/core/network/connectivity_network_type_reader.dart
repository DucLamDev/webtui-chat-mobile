import 'package:connectivity_plus/connectivity_plus.dart';

import 'media_auto_download_policy.dart';

/// Đọc loại mạng bằng connectivity_plus (Android / iOS).
final class ConnectivityNetworkTypeReader implements NetworkTypeReader {
  ConnectivityNetworkTypeReader({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<MediaNetworkType> current() async {
    try {
      return mediaNetworkTypeFrom(await _connectivity.checkConnectivity());
    } on Object {
      // Máy không có plugin (bản xem thử Linux, test) / lỗi nền tảng.
      return MediaNetworkType.unknown;
    }
  }
}

/// Đổi kết quả của connectivity_plus (có thể nhiều mạng cùng lúc, vd. VPN +
/// di động) về một loại: có Wi-Fi / mạng dây thì là Wi-Fi; không có mà có di
/// động thì là di động.
MediaNetworkType mediaNetworkTypeFrom(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet)) {
    return MediaNetworkType.wifi;
  }
  if (results.contains(ConnectivityResult.mobile)) {
    return MediaNetworkType.cellular;
  }
  if (results.isEmpty) return MediaNetworkType.unknown;
  if (results.every((result) => result == ConnectivityResult.none)) {
    return MediaNetworkType.offline;
  }
  return MediaNetworkType.other;
}
