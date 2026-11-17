import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_video_upgrade_policy.dart';

void main() {
  group('canStartLocalVideo', () {
    test('hiện nút Video khi đã kết nối và camera của mình đang tắt', () {
      expect(
        canStartLocalVideo(
          connected: true,
          hasLocalVideo: false,
          upgrading: false,
          leaving: false,
        ),
        isTrue,
      );
    });

    test(
      'ẩn nút khi chưa kết nối, đã có camera, đang bật dở hoặc đang rời',
      () {
        expect(
          canStartLocalVideo(
            connected: false,
            hasLocalVideo: false,
            upgrading: false,
            leaving: false,
          ),
          isFalse,
        );
        expect(
          canStartLocalVideo(
            connected: true,
            hasLocalVideo: true,
            upgrading: false,
            leaving: false,
          ),
          isFalse,
        );
        expect(
          canStartLocalVideo(
            connected: true,
            hasLocalVideo: false,
            upgrading: true,
            leaving: false,
          ),
          isFalse,
        );
        expect(
          canStartLocalVideo(
            connected: true,
            hasLocalVideo: false,
            upgrading: false,
            leaving: true,
          ),
          isFalse,
        );
      },
    );
  });

  test('bố cục video khi gọi video, mình bật camera hoặc bên kia có video', () {
    expect(
      callUsesVideoLayout(
        startedAsVideo: false,
        hasLocalVideo: false,
        hasRemoteVideo: false,
      ),
      isFalse,
    );
    expect(
      callUsesVideoLayout(
        startedAsVideo: true,
        hasLocalVideo: false,
        hasRemoteVideo: false,
      ),
      isTrue,
    );
    expect(
      callUsesVideoLayout(
        startedAsVideo: false,
        hasLocalVideo: true,
        hasRemoteVideo: false,
      ),
      isTrue,
    );
    expect(
      callUsesVideoLayout(
        startedAsVideo: false,
        hasLocalVideo: false,
        hasRemoteVideo: true,
      ),
      isTrue,
    );
  });

  group('callRenegotiationStep', () {
    test('người khởi tạo gửi offer, người nhận xin offer', () {
      expect(
        callRenegotiationStep(incoming: false, signalingStable: true),
        CallRenegotiationStep.sendOffer,
      );
      expect(
        callRenegotiationStep(incoming: true, signalingStable: true),
        CallRenegotiationStep.requestOffer,
      );
    });

    test('signaling chưa stable thì chờ, cả hai vai', () {
      expect(
        callRenegotiationStep(incoming: false, signalingStable: false),
        CallRenegotiationStep.waitForStable,
      );
      expect(
        callRenegotiationStep(incoming: true, signalingStable: false),
        CallRenegotiationStep.waitForStable,
      );
    });
  });

  group('shouldRevertLocalVideoUpgrade', () {
    final requestedAt = DateTime.utc(2026, 11, 17, 9);

    test('chưa đủ 8 giây thì chưa tắt camera', () {
      expect(
        shouldRevertLocalVideoUpgrade(
          requestedAt: requestedAt,
          now: requestedAt.add(const Duration(seconds: 7)),
          lastOfferAt: null,
        ),
        isFalse,
      );
    });

    test('đủ 8 giây không có offer mới thì tắt camera', () {
      expect(callVideoUpgradeOfferTimeout, const Duration(seconds: 8));
      expect(
        shouldRevertLocalVideoUpgrade(
          requestedAt: requestedAt,
          now: requestedAt.add(const Duration(seconds: 8)),
          lastOfferAt: null,
        ),
        isTrue,
      );
    });

    test('offer cũ (trước lúc xin) không tính', () {
      expect(
        shouldRevertLocalVideoUpgrade(
          requestedAt: requestedAt,
          now: requestedAt.add(const Duration(seconds: 9)),
          lastOfferAt: requestedAt.subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('đã có offer mới sau lúc xin thì giữ camera', () {
      expect(
        shouldRevertLocalVideoUpgrade(
          requestedAt: requestedAt,
          now: requestedAt.add(const Duration(seconds: 9)),
          lastOfferAt: requestedAt.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );
    });
  });
}
