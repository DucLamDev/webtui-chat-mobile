import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../domain/entities/call_session.dart';

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

/// Lý do trong tín hiệu `renegotiate` khi bên nhận mất kết nối và xin bên gọi
/// khởi động lại ICE (bên gọi bản cũ / web bỏ qua lý do, chỉ gửi offer mới).
const String callRenegotiateIceRestartReason = 'ice_restart';
