/// Quy tắc cuộc gọi khi một người dùng đăng nhập trên nhiều thiết bị.
///
/// Mã thiết bị là mã đã gửi lúc đăng ký push. Hàng VoIP của iOS được đăng ký
/// với hậu tố `:voip` nhưng vẫn là cùng một máy.
library;

String? normalizedCallDeviceId(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

bool _sameCallDevice(String left, String right) {
  return left == right || left == '$right:voip' || right == '$left:voip';
}

/// Cuộc gọi đã được nhận trên chính máy này.
bool callAnsweredOnThisDevice({
  required String? answeredDeviceId,
  required String? localDeviceId,
}) {
  final answered = normalizedCallDeviceId(answeredDeviceId);
  final local = normalizedCallDeviceId(localDeviceId);
  return answered != null && local != null && _sameCallDevice(answered, local);
}

/// Cuộc gọi đã được nhận trên một máy khác của cùng người dùng. Thiếu mã
/// (máy chủ cũ hoặc chưa đọc được mã máy) thì không kết luận được: trả `false`
/// để giữ hành vi cũ.
bool callAnsweredOnAnotherDevice({
  required String? answeredDeviceId,
  required String? localDeviceId,
}) {
  final answered = normalizedCallDeviceId(answeredDeviceId);
  final local = normalizedCallDeviceId(localDeviceId);
  return answered != null && local != null && !_sameCallDevice(answered, local);
}

/// Tín hiệu WebRTC (offer / answer / ICE / ready) do máy chủ gắn
/// `target_device_id`: khác mã máy này thì phải bỏ qua. Không có mã đích thì xử
/// lý như cũ. Có mã đích nhưng chưa biết mã máy mình thì cũng bỏ qua: máy đã
/// nhận cuộc gọi luôn biết mã của chính nó.
bool callSignalTargetsAnotherDevice({
  required String? targetDeviceId,
  required String? localDeviceId,
}) {
  final target = normalizedCallDeviceId(targetDeviceId);
  if (target == null) return false;
  final local = normalizedCallDeviceId(localDeviceId);
  return local == null || !_sameCallDevice(target, local);
}
