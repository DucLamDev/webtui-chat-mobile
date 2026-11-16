import '../../../../l10n/app_strings.dart';
import 'call_device_routing.dart';

/// Quyết định có đổ chuông cuộc gọi đến trên máy này hay không.
///
/// Máy chủ phát `CallInvited` tới room cá nhân của CẢ người gọi lẫn người
/// nhận (mọi thiết bị đang kết nối). Người gọi (trên máy vừa bấm gọi hoặc máy
/// khác cùng tài khoản) không bao giờ được đổ chuông: máy chủ chỉ cho người
/// được gọi nhận, đổ chuông chỉ dẫn tới hộp "Cuộc gọi đến" sai và lỗi 409.
///
/// Thứ tự kiểm (không cần mạng):
/// 1. [placedByThisDevice]: máy này đã tạo / đang mở màn gọi đi cho cuộc này.
/// 2. [initiatorDeviceId] trùng [localDeviceId]: máy này tạo cuộc gọi.
/// 3. Có id người dùng: mình là người gọi, hoặc người được gọi là người khác.
/// Thiếu id người dùng (và không khớp 1, 2) thì vẫn đổ chuông để người nhận
/// không bị nhỡ cuộc gọi.
bool shouldRingForIncomingCall({
  required String? currentUserId,
  required String initiatorUserId,
  required String targetUserId,
  String? initiatorDeviceId,
  String? localDeviceId,
  bool placedByThisDevice = false,
}) {
  if (placedByThisDevice) return false;
  if (callPlacedFromThisDevice(
    initiatorDeviceId: initiatorDeviceId,
    localDeviceId: localDeviceId,
  )) {
    return false;
  }
  final me = currentUserId?.trim() ?? '';
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

String get callGoneMessage => tr(
  'Cuộc gọi đã kết thúc hoặc đã được nhận ở thiết bị khác.',
  'The call ended or was answered on another device.',
);
String get callConnectTimeoutMessage => tr(
  'Không kết nối được, vui lòng thử lại.',
  'Couldn\'t connect. Please try again.',
);
