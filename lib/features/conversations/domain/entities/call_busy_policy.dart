import '../../../../l10n/app_strings.dart';

/// Lý do gửi kèm khi máy này tự từ chối cuộc gọi đến vì đang bận cuộc gọi
/// khác (máy chủ phát lại trong `CallRejected.reason`).
const String callBusyRejectReason = 'busy';

/// Mã lỗi 409 khi tạo cuộc gọi: người nhận đang trong cuộc gọi khác.
const String callTargetBusyCode = 'CALL_TARGET_BUSY';

/// Mã lỗi 409 khi tạo cuộc gọi: chính mình đang trong cuộc gọi khác.
const String callInitiatorBusyCode = 'CALL_INITIATOR_BUSY';

String get callTargetBusyMessage => tr(
  'Người nhận đang bận trong cuộc gọi khác.',
  'The person you are calling is busy on another call.',
);

String get callInitiatorBusyMessage => tr(
  'Bạn đang trong một cuộc gọi khác. Hãy kết thúc cuộc gọi đó trước.',
  'You are already on another call. End that call first.',
);

/// Bấm gọi khi màn gọi khác đang mở trên máy này.
String get callAlreadyInProgressMessage =>
    tr('Bạn đang trong một cuộc gọi khác.', 'You are already on another call.');

/// Việc cần làm khi một nguồn (realtime, thông báo đẩy, polling) báo cuộc gọi
/// 1-1 đến.
enum IncomingCallDecision {
  /// Hiện hộp "Cuộc gọi đến" như bình thường.
  show,

  /// Máy này đã nhận cuộc gọi đó (màn gọi đang mở hoặc giao diện gốc đã bấm
  /// nghe): không hiện hộp nữa.
  alreadyHandled,

  /// Đang có màn gọi của cuộc gọi khác: tự từ chối với lý do "busy", không
  /// hiện hộp, không đổ chuông.
  rejectBusy,
}

/// Quyết định cho cuộc gọi đến [callId].
///
/// [activeCallIds]: các màn gọi đang mở trên máy (ActiveCallTracker).
/// [nativeAcceptPending]: giao diện gốc (CallKit / màn hình khoá / thông báo
/// toàn màn hình) đã bấm nghe cuộc này, app đang hoặc sắp mở màn gọi.
IncomingCallDecision decideIncomingCall({
  required String callId,
  required Set<String> activeCallIds,
  bool nativeAcceptPending = false,
}) {
  final id = callId.trim();
  if (id.isEmpty) return IncomingCallDecision.alreadyHandled;
  if (activeCallIds.contains(id) || nativeAcceptPending) {
    return IncomingCallDecision.alreadyHandled;
  }
  if (activeCallIds.any((active) => active != id)) {
    return IncomingCallDecision.rejectBusy;
  }
  return IncomingCallDecision.show;
}

/// Việc cần làm khi giao diện gốc báo người dùng bấm nghe cuộc gọi 1-1.
enum NativeAcceptRoute {
  /// Mở màn gọi cho cuộc này.
  openCallScreen,

  /// Luồng trong app đang xử lý đúng cuộc này (hộp "Cuộc gọi đến" đang hiện
  /// hoặc sắp hiện): đóng hộp với kết quả "đã nghe" để luồng đó mở màn gọi
  /// đúng một lần, xác nhận hành động gốc.
  handOverToInAppFlow,

  /// Màn gọi của cuộc này đã mở: chỉ xác nhận hành động gốc.
  alreadyOpen,

  /// Đang có màn gọi của cuộc gọi khác: từ chối "busy" và tắt giao diện gốc.
  rejectBusy,
}

NativeAcceptRoute decideNativeAccept({
  required String callId,
  required Set<String> activeCallIds,
  required String? inAppFlowCallId,
}) {
  final id = callId.trim();
  if (activeCallIds.contains(id)) return NativeAcceptRoute.alreadyOpen;
  if (activeCallIds.any((active) => active != id)) {
    return NativeAcceptRoute.rejectBusy;
  }
  if (inAppFlowCallId?.trim() == id) {
    return NativeAcceptRoute.handOverToInAppFlow;
  }
  return NativeAcceptRoute.openCallScreen;
}
