import '../../../../l10n/app_strings.dart';

/// Chuyển cuộc gọi thoại sang video giữa chừng (gọi 1-1).
///
/// Quy ước với máy chủ / web:
/// - `offer` chỉ người khởi tạo gửi, `answer` chỉ người nhận gửi (giữ luật cũ).
/// - Người nhận muốn thương lượng lại (vừa bật camera) thì gửi tín hiệu
///   `renegotiate` `{"reason":"video"}`; người khởi tạo nhận `CallRenegotiate`
///   và gửi `offer` mới.
/// - Signaling chưa `stable` thì ghi nhớ, chạy lại sau khi xong lượt đang chạy.

/// Lý do gửi kèm tín hiệu `renegotiate` khi vừa bật camera.
const String callRenegotiateVideoReason = 'video';

/// Người nhận đã xin thương lượng lại mà quá thời hạn này chưa có offer mới
/// thì coi như máy bên kia chưa hỗ trợ (bản cũ): tắt camera lại.
const Duration callVideoUpgradeOfferTimeout = Duration(seconds: 8);

String get callVideoUpgradeUnsupportedMessage => tr(
  'Máy bên kia chưa hỗ trợ chuyển sang video giữa cuộc gọi (cần cập nhật ứng dụng).',
  'The other device can\'t switch to video during a call yet (it needs an app update).',
);

/// Có hiện nút "Video" (bật camera của mình) không: cuộc gọi đã kết nối,
/// máy này chưa có camera đang gửi, không đang bật dở hoặc đang rời cuộc gọi.
bool canStartLocalVideo({
  required bool connected,
  required bool hasLocalVideo,
  required bool upgrading,
  required bool leaving,
}) {
  return connected && !hasLocalVideo && !upgrading && !leaving;
}

/// Màn gọi dùng bố cục video khi cuộc gọi vốn là video, khi máy này đã bật
/// camera, hoặc khi đã nhận video từ bên kia.
bool callUsesVideoLayout({
  required bool startedAsVideo,
  required bool hasLocalVideo,
  required bool hasRemoteVideo,
}) {
  return startedAsVideo || hasLocalVideo || hasRemoteVideo;
}

/// Bước tiếp theo khi cần thương lượng lại SDP.
enum CallRenegotiationStep {
  /// Người khởi tạo: tạo offer mới và gửi `offer`.
  sendOffer,

  /// Người nhận: gửi `renegotiate` để người khởi tạo gửi offer mới.
  requestOffer,

  /// Đang có một lượt thương lượng chưa xong: ghi nhớ, làm lại sau.
  waitForStable,
}

CallRenegotiationStep callRenegotiationStep({
  required bool incoming,
  required bool signalingStable,
}) {
  if (!signalingStable) return CallRenegotiationStep.waitForStable;
  return incoming
      ? CallRenegotiationStep.requestOffer
      : CallRenegotiationStep.sendOffer;
}

/// Người nhận đã gửi `renegotiate` vì bật camera: hết thời hạn mà chưa nhận
/// offer mới nào kể từ lúc xin thì tắt camera lại và báo máy kia chưa hỗ trợ.
bool shouldRevertLocalVideoUpgrade({
  required DateTime requestedAt,
  required DateTime now,
  required DateTime? lastOfferAt,
  Duration timeout = callVideoUpgradeOfferTimeout,
}) {
  if (lastOfferAt != null && !lastOfferAt.isBefore(requestedAt)) return false;
  return now.difference(requestedAt) >= timeout;
}
