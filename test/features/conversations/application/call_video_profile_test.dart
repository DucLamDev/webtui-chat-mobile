import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:webtui_chat/features/conversations/application/call_video_profile.dart';

void main() {
  test('xin camera trước 960×540, tối đa 24 hình/giây', () {
    expect(CallVideoProfile.cameraConstraints(), {
      'facingMode': 'user',
      'width': {'ideal': 960},
      'height': {'ideal': 540},
      'frameRate': {'ideal': 24, 'max': 24},
    });
  });

  test(
    'đặt trần 800 kbps, 24 hình/giây cho mọi lớp, ưu tiên giữ khung hình',
    () {
      final parameters = RTCRtpParameters(
        encodings: [
          RTCRtpEncoding(maxBitrate: 2500000),
          RTCRtpEncoding(maxFramerate: 30),
        ],
      );
      expect(CallVideoProfile.applyTo(parameters), isTrue);
      for (final encoding in parameters.encodings!) {
        expect(encoding.maxBitrate, 800000);
        expect(encoding.maxFramerate, 24);
      }
      expect(
        parameters.degradationPreference,
        RTCDegradationPreference.MAINTAIN_FRAMERATE,
      );
    },
  );

  test('chưa có lớp mã hoá (chưa thoả thuận xong): báo để áp lại sau', () {
    final parameters = RTCRtpParameters(encodings: []);
    expect(CallVideoProfile.applyTo(parameters), isFalse);
    expect(parameters.degradationPreference, isNull);
    expect(CallVideoProfile.applyTo(RTCRtpParameters()), isFalse);
  });
}
