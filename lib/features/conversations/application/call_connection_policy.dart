import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../domain/entities/call_device_routing.dart';
import '../domain/entities/call_session.dart';
import '../domain/entities/conversation_realtime_event.dart';

/// Chạy các bước SDP / ICE (nhận offer, nhận answer, thêm candidate, khởi
/// động lại ICE, thương lượng lại khi bật video) lần lượt từng bước một.
///
/// RTCPeerConnection không chịu được hai lượt `setRemoteDescription` /
/// `setLocalDescription` chen nhau (vd. candidate tới giữa lúc đang đặt
/// offer, hay ICE restart chạy song song với thương lượng bật camera). Bước
/// lỗi chỉ trả lỗi cho người gọi bước đó, không làm kẹt các bước sau.
final class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  bool get isClosed => _closed;

  /// Xếp [task] chạy sau mọi bước đã xếp trước. Hàng đã đóng thì bỏ qua và trả
  /// `null` (màn gọi đã rời).
  Future<T?> run<T>(Future<T> Function() task) {
    if (_closed) return Future<T?>.value();
    final completer = Completer<T?>();
    _tail = _tail.then((_) async {
      if (_closed) {
        completer.complete(null);
        return;
      }
      try {
        completer.complete(await task());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Không nhận thêm bước mới; bước đang chờ trong hàng bị bỏ.
  void close() => _closed = true;
}

/// Đếm số lần còn được gửi lại một tín hiệu (ready, offer, ICE restart, xin
/// thương lượng lại). Máy chủ chỉ chuyển tiếp tín hiệu một lần: mất gói (đổi
/// mạng, realtime vừa nối lại) thì phải gửi lại, nhưng có trần để không spam.
final class SignalResendBudget {
  SignalResendBudget({required this.maxResends}) : assert(maxResends >= 0);

  final int maxResends;
  int _used = 0;

  int get used => _used;
  bool get exhausted => _used >= maxResends;

  /// `true` và trừ một lượt nếu còn lượt gửi lại.
  bool tryConsume() {
    if (exhausted) return false;
    _used++;
    return true;
  }

  void reset() => _used = 0;
}

/// Nhịp gửi lại / hẹn giờ của cuộc gọi 1-1. Giá trị chung cho mọi màn gọi.
abstract final class CallSignalTiming {
  /// Bên nhận gửi lại `ready` tới khi có offer.
  static const Duration readyResendInterval = Duration(seconds: 3);
  static const int readyMaxResends = 5;

  /// Bên gọi gửi lại offer đầu tiên nếu chưa có answer.
  static const Duration offerAnswerTimeout = Duration(seconds: 5);
  static const int offerMaxResends = 3;

  /// Bên gọi gửi lại offer khởi động lại ICE nếu chưa có answer.
  static const Duration iceRestartAnswerTimeout = Duration(seconds: 4);
  static const int iceRestartMaxResends = 3;

  /// POST ICE candidate lỗi: thử lại một lần sau khoảng chờ ngắn.
  static const Duration candidateRetryDelay = Duration(milliseconds: 800);
  static const int candidateMaxAttempts = 2;
}

/// Khôi phục kết nối khi WebRTC báo `disconnected` / `failed` (đổi Wi-Fi ↔
/// 4G, sóng yếu).
///
/// - Sau [actionDelay] vẫn mất kết nối: bên gọi khởi động lại ICE, bên nhận
///   gửi `renegotiate` xin bên gọi khởi động lại (chỉ bên gọi được gửi offer).
/// - Hẹn kết thúc ([giveUpAfter]) đặt MỘT lần từ lúc bắt đầu mất kết nối và chỉ
///   huỷ khi nối lại được: các lần báo lỗi tiếp theo không xoá hẹn này, nên màn
///   gọi không bao giờ kẹt "Đang khôi phục kết nối…".
abstract final class CallRecoveryPolicy {
  static const Duration actionDelay = Duration(seconds: 3);

  /// Số lần tối đa bên gọi khởi động lại ICE / bên nhận xin khởi động lại
  /// trong một lần mất kết nối.
  static const int maxRecoveryActions = 3;

  /// Khoảng chờ giữa hai lần thử khôi phục khi lần trước chưa nối lại được.
  static const Duration retryInterval = Duration(seconds: 6);

  /// Bên nhận chờ lâu hơn bên gọi để bên gọi kịp khởi động lại ICE.
  static Duration giveUpAfter({required bool incoming}) =>
      incoming ? const Duration(seconds: 30) : const Duration(seconds: 25);

  /// Tải lại ICE servers khi khôi phục: quá hạn này thì dùng cấu hình cũ (lúc
  /// đổi mạng, lệnh HTTP có thể treo 15–30 giây, quá cả hạn kết thúc).
  static const Duration iceServersFetchTimeout = Duration(seconds: 3);
}

/// Bên gọi có phải nhường lượt khôi phục mới cho offer đang chờ answer không.
///
/// - Đang có lượt khởi động lại ICE xếp hàng / chạy: nhường (không chồng).
/// - Đang chờ answer cho offer đã gửi được: nhường, hẹn gửi lại tự lo.
/// - Lần gửi offer gần nhất LỖI (vừa đổi Wi-Fi ↔ 4G): không nhường, tạo
///   offer khởi động lại mới (thay offer cũ), kẻo cuộc gọi bị cắt vì hết hạn.
bool callerRecoveryShouldWait({
  required bool iceRestartRunning,
  required bool awaitingAnswer,
  required bool lastOfferSendFailed,
}) {
  if (iceRestartRunning) return true;
  return awaitingAnswer && !lastOfferSendFailed;
}

/// Bên gọi xử lý tín hiệu `renegotiate` của bên nhận.
enum CallRenegotiateAction {
  /// Khởi động lại ICE (offer `iceRestart`), dù máy này chưa thấy mất kết nối.
  iceRestart,

  /// Thương lượng lại thường (bên nhận bật camera). Đang khôi phục thì gộp
  /// vào offer khởi động lại ICE hoặc chạy ngay sau khi lượt đó xong.
  renegotiate,

  /// Không rõ lý do (bản cũ) lúc đang khôi phục: vừa ghi nhớ thương lượng lại
  /// vừa thúc khôi phục; offer khởi động lại ICE mang luôn m-line video.
  renegotiateAndIceRestart,
}

CallRenegotiateAction callerRenegotiateAction({
  required String? reason,
  required bool reconnecting,
}) {
  final normalized = reason?.trim() ?? '';
  if (normalized == callRenegotiateIceRestartReason) {
    return CallRenegotiateAction.iceRestart;
  }
  if (normalized.isEmpty && reconnecting) {
    return CallRenegotiateAction.renegotiateAndIceRestart;
  }
  return CallRenegotiateAction.renegotiate;
}

/// Hỏng giữa chừng (thiếu quyền micro, mở media lỗi, tín hiệu lỗi): có báo
/// kết thúc lên máy chủ không. Cuộc gọi đến CHƯA nhận trên máy này thì không
/// gửi từ chối thay người được gọi: máy khác (web) vẫn đổ chuông, không ai
/// nghe thì máy chủ tự ghi cuộc gọi nhỡ.
bool callAbortTerminatesServerCall({
  required bool incoming,
  required bool acceptedHere,
}) {
  return !incoming || acceptedHere;
}

/// Hộp "Cuộc gọi đến" hỏi máy chủ vẫn lỗi tạm thời sau mấy lần thử.
enum IncomingLookupFailureAction {
  /// Chưa ai bấm nghe: giữ chuông gốc, thông báo / hỏi định kỳ mở lại sau.
  keepRinging,

  /// Đã bấm nghe trên CallKit và đủ thông tin cuộc gọi: mở màn gọi luôn (màn
  /// gọi tự nhận máy, chịu được lỗi tạm thời).
  openCallScreen,

  /// Đã bấm nghe nhưng thiếu thông tin (chưa biết cuộc trò chuyện): thử lại.
  retryLater,

  /// Đã bấm nghe, thử lại quá số lần: tắt giao diện gốc, không treo im lặng.
  giveUp,
}

/// Số lượt thử lại tối đa khi đã bấm nghe native mà chưa đọc được cuộc gọi.
const int incomingNativeAcceptMaxRetries = 3;

IncomingLookupFailureAction incomingLookupFailureAction({
  required bool nativeAccepted,
  required bool hasCallContext,
  required int retriesUsed,
}) {
  if (!nativeAccepted) return IncomingLookupFailureAction.keepRinging;
  if (hasCallContext) return IncomingLookupFailureAction.openCallScreen;
  return retriesUsed < incomingNativeAcceptMaxRetries
      ? IncomingLookupFailureAction.retryLater
      : IncomingLookupFailureAction.giveUp;
}

/// Dòng trạng thái dưới tên người gọi trên màn gọi.
enum CallHeaderPhase {
  /// Chưa nối WebRTC lần nào (kể cả khi máy chủ đã báo "accepted").
  connecting,

  /// Đã từng nối, đang mất kết nối và thử khôi phục.
  reconnecting,

  /// Đã nối: hiện đồng hồ thời lượng.
  active,
}

/// Đồng hồ thời lượng chỉ chạy khi máy chủ đã báo nhận máy VÀ WebRTC đã thật
/// sự thông ít nhất một lần; trước đó là "Đang kết nối…" (không để người dùng
/// thấy 00:05 mà chưa nghe gì).
CallHeaderPhase callHeaderPhase({
  required bool serverAccepted,
  required bool mediaConnectedOnce,
  required bool reconnecting,
}) {
  if (!mediaConnectedOnce) return CallHeaderPhase.connecting;
  if (reconnecting) return CallHeaderPhase.reconnecting;
  return serverAccepted ? CallHeaderPhase.active : CallHeaderPhase.connecting;
}

/// Kết quả hỏi máy chủ `GET /calls/{id}`.
enum CallLookupOutcome {
  /// Còn đổ chuông.
  ringing,

  /// Đã được nhận (ở máy này hoặc máy khác).
  accepted,

  /// Đã kết thúc / không còn (404, 403, trạng thái kết thúc).
  gone,

  /// Lỗi mạng / máy chủ tạm thời: chưa biết, giữ nguyên và thử lại.
  transientError,
}

/// Lỗi tạm thời (mạng chập chờn, hết giờ, máy chủ 5xx / quá tải): không được
/// coi là "cuộc gọi đã kết thúc".
bool isTransientCallFailure(Failure? failure) {
  if (failure == null) return false;
  return switch (failure.kind) {
    FailureKind.network ||
    FailureKind.timeout ||
    FailureKind.server ||
    FailureKind.rateLimited ||
    FailureKind.cancelled ||
    FailureKind.unknown => true,
    FailureKind.unauthorized ||
    FailureKind.forbidden ||
    FailureKind.notFound ||
    FailureKind.validation ||
    FailureKind.conflict ||
    FailureKind.decoding ||
    FailureKind.storage => false,
  };
}

/// Tách "không tìm thấy / đã kết thúc" khỏi "lỗi mạng" khi đọc một cuộc gọi.
CallLookupOutcome classifyCallLookup(Result<CallSession> result) {
  final call = result.valueOrNull;
  if (call == null) {
    return isTransientCallFailure(result.failureOrNull)
        ? CallLookupOutcome.transientError
        : CallLookupOutcome.gone;
  }
  if (call.isTerminal) return CallLookupOutcome.gone;
  return call.status == CallStatus.ringing
      ? CallLookupOutcome.ringing
      : CallLookupOutcome.accepted;
}

/// Nhịp hỏi máy chủ / nhịp đồng hồ của màn gọi 1-1 và hộp "Cuộc gọi đến".
///
/// Kết thúc, nhận máy, đã nghe ở máy khác đều đến qua realtime; lượt hỏi
/// `GET /calls/{id}` chỉ còn để bắt sự kiện bị lỡ và làm nhịp "còn trong cuộc
/// gọi" cho máy chủ (máy chủ ghi `last_active_at` tối đa 10 giây một lần, coi
/// người dùng còn bận trong 90 giây), nên không cần hỏi mỗi giây.
abstract final class CallStatePolling {
  /// Màn gọi hỏi trạng thái cuộc gọi.
  static const Duration callScreenSyncInterval = Duration(seconds: 5);

  /// Đồng hồ thời lượng chạy trên máy (chỉ vẽ lại, không gọi mạng).
  static const Duration durationTickInterval = Duration(seconds: 1);

  /// Hộp "Cuộc gọi đến": đếm ngược / rung mỗi giây, hỏi máy chủ mỗi bấy
  /// nhiêu nhịp.
  static const int incomingDialogCheckEveryTicks = 2;

  /// Nhịp thứ [tick] (đếm từ 1) của hộp "Cuộc gọi đến" có hỏi máy chủ không:
  /// nhịp 1, 3, 5… (lượt hỏi đầu vẫn sau 1 giây như trước).
  static bool incomingDialogShouldCheck(int tick) =>
      tick > 0 && (tick - 1) % incomingDialogCheckEveryTicks == 0;
}

/// Thời lượng cuộc gọi tính từ [startedAt]; chưa bắt đầu hoặc giờ máy lệch
/// (bắt đầu "trong tương lai") thì là 0.
Duration callElapsed({required DateTime? startedAt, required DateTime now}) {
  if (startedAt == null) return Duration.zero;
  final elapsed = now.toUtc().difference(startedAt.toUtc());
  return elapsed.isNegative ? Duration.zero : elapsed;
}

/// Trạng thái màn gọi sau một lượt hỏi máy chủ. Máy chủ không bao giờ đưa
/// cuộc gọi đã nhận về "đang đổ chuông": lượt hỏi gửi đi trước khi realtime
/// báo nhận máy mà về sau thì không được kéo màn gọi lùi lại.
CallStatus reconcileCallStatus({
  required CallStatus local,
  required CallStatus server,
}) {
  if (local == CallStatus.accepted && server == CallStatus.ringing) {
    return CallStatus.accepted;
  }
  return server;
}

/// Việc màn gọi phải làm ngay với một sự kiện realtime (ngoài tín hiệu
/// WebRTC và các sự kiện kết thúc).
enum CallRealtimeLifecycleAction {
  /// Không làm gì thêm.
  none,

  /// Kết nối realtime vừa nối lại: hỏi máy chủ ngay để bắt sự kiện bị lỡ.
  resync,

  /// Bên kia đã nhận máy (chiều gọi đi): chuyển sang "đã nhận" ngay.
  accepted,

  /// Cuộc gọi đến đã được nghe ở máy khác của chính người dùng: đóng màn.
  answeredElsewhere,
}

/// Phân loại sự kiện realtime cho màn gọi [callId].
///
/// - `reconnected` không mang mã cuộc gọi: luôn [CallRealtimeLifecycleAction.resync].
/// - `CallAnsweredElsewhere` / `CallAccepted` mang mã máy đã nhận khác máy
///   này, trên màn cuộc gọi đến: [CallRealtimeLifecycleAction.answeredElsewhere]
///   (sự kiện này do chính người dùng tạo nên KHÔNG được bỏ vì "của mình").
/// - `CallAccepted` của người kia trên màn gọi đi:
///   [CallRealtimeLifecycleAction.accepted].
CallRealtimeLifecycleAction callRealtimeLifecycleAction({
  required ConversationRealtimeEventType type,
  required String? eventCallId,
  required String callId,
  required bool incoming,
  required bool fromCurrentUser,
  required String? answeredDeviceId,
  required String? localDeviceId,
}) {
  if (type == ConversationRealtimeEventType.reconnected) {
    return CallRealtimeLifecycleAction.resync;
  }
  if (eventCallId != callId) return CallRealtimeLifecycleAction.none;
  final answeredElsewhere =
      incoming &&
      callAnsweredOnAnotherDevice(
        answeredDeviceId: answeredDeviceId,
        localDeviceId: localDeviceId,
      );
  return switch (type) {
    ConversationRealtimeEventType.callAnsweredElsewhere ||
    ConversationRealtimeEventType.callAccepted when answeredElsewhere =>
      CallRealtimeLifecycleAction.answeredElsewhere,
    ConversationRealtimeEventType.callAccepted
        when !incoming && !fromCurrentUser =>
      CallRealtimeLifecycleAction.accepted,
    _ => CallRealtimeLifecycleAction.none,
  };
}

/// Lý do trong tín hiệu `renegotiate` khi bên nhận mất kết nối và xin bên gọi
/// khởi động lại ICE (bên gọi bản cũ / web bỏ qua lý do, chỉ gửi offer mới).
const String callRenegotiateIceRestartReason = 'ice_restart';
