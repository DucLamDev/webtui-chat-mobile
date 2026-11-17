import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Cấu hình video của cuộc gọi 1-1 (WebRTC ngang hàng).
///
/// Trước đây xin camera 1280×720, không giới hạn khung hình / băng thông: máy
/// tầm trung vừa nén vừa giải nén 720p nóng và giật, nhiều cuộc gọi trên cùng
/// Wi-Fi văn phòng chiếm hết băng thông nên hình đứng. 960×540, 24 hình/giây,
/// tối đa 800 kbps vẫn rõ trên màn điện thoại mà nhẹ máy và nhẹ mạng; mạng yếu
/// thì giảm độ nét trước, giữ chuyển động mượt.
abstract final class CallVideoProfile {
  static const int width = 960;
  static const int height = 540;
  static const int frameRate = 24;

  /// bit/giây cho mỗi luồng video gửi đi.
  static const int maxBitrate = 800000;

  /// Ràng buộc `getUserMedia` cho camera trước.
  static Map<String, Object> cameraConstraints() => {
    'facingMode': 'user',
    'width': {'ideal': width},
    'height': {'ideal': height},
    'frameRate': {'ideal': frameRate, 'max': frameRate},
  };

  /// Đặt trần băng thông / khung hình cho mọi lớp mã hoá và ưu tiên giữ khung
  /// hình (mạng yếu thì giảm độ nét). Không có lớp nào (chưa thoả thuận xong)
  /// thì trả `false` để gọi lại sau khi đã kết nối.
  static bool applyTo(RTCRtpParameters parameters) {
    final encodings = parameters.encodings;
    if (encodings == null || encodings.isEmpty) return false;
    for (final encoding in encodings) {
      encoding.maxBitrate = maxBitrate;
      encoding.maxFramerate = frameRate;
    }
    parameters.degradationPreference =
        RTCDegradationPreference.MAINTAIN_FRAMERATE;
    return true;
  }
}
