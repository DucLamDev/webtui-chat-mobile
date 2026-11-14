/// Quyết định có đổ chuông cuộc gọi đến trên máy này hay không.
///
/// Máy chủ phát `CallInvited` tới mọi thiết bị của người dùng đang kết nối,
/// kể cả khi chính người dùng là NGƯỜI GỌI từ thiết bị khác (ví dụ gọi từ
/// trình duyệt khi app đăng nhập cùng tài khoản). Khi đó máy chỉ cho người
/// được gọi nhận, nên đổ chuông chỉ dẫn tới lỗi 409 và màn gọi bị kẹt.
bool shouldRingForIncomingCall({
  required String? currentUserId,
  required String initiatorUserId,
  required String targetUserId,
}) {
  final me = currentUserId?.trim() ?? '';
  // Thiếu id người dùng: giữ hành vi cũ (đổ chuông).
  if (me.isEmpty) return true;
  final initiator = initiatorUserId.trim();
  final target = targetUserId.trim();
  if (initiator.isNotEmpty && initiator == me) return false;
  if (target.isNotEmpty && target != me) return false;
  return true;
}

/// Thời hạn chờ kết nối WebRTC kể từ khi cuộc gọi được nhận.
const Duration callConnectTimeout = Duration(seconds: 40);

/// Thời gian giữ thông báo lỗi trên màn gọi trước khi tự đóng.
const Duration callErrorDisplayDuration = Duration(seconds: 2);

const String callGoneMessage =
    'Cuộc gọi đã kết thúc hoặc đã được nhận ở thiết bị khác.';
const String callConnectTimeoutMessage =
    'Không kết nối được, vui lòng thử lại.';
