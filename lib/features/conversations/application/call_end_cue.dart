import '../../../core/notifications/call_tone_player.dart';
import '../domain/entities/call_session.dart';

/// Âm báo khi màn gọi 1-1 đóng:
/// - mình bấm gác máy, hoặc cuộc gọi kết thúc / bị từ chối / bị huỷ: tiếng
///   kết thúc cuộc gọi;
/// - gọi đi mà hết giờ đổ chuông không ai bắt máy (`missed`): lời báo không
///   liên lạc được người nhận;
/// - lỗi kỹ thuật (mất mạng, không kết nối được media) hoặc không rõ trạng
///   thái: im, màn gọi đã báo lỗi bằng chữ.
CallCue? callEndCue({
  required bool incoming,
  required CallStatus? status,
  bool localHangup = false,
}) {
  if (localHangup) return CallCue.ended;
  switch (status) {
    case CallStatus.missed:
      return incoming ? null : CallCue.unreachable;
    case CallStatus.ended:
    case CallStatus.rejected:
    case CallStatus.cancelled:
      return CallCue.ended;
    case CallStatus.ringing:
    case CallStatus.accepted:
    case null:
      return null;
  }
}
