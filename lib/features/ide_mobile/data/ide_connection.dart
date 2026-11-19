import 'dart:async';

import '../domain/ide_errors.dart';
import '../domain/ide_ready.dart';
import 'ide_channel.dart';

enum IdeStreamKind { rpc, ai, term, talk }

/// Trạng thái đường nối IDE (stream rpc luôn giữ).
enum IdeLinkPhase {
  /// Chưa nối (hoặc đã dừng vì rời mục / ra nền).
  idle,
  connecting,
  ready,

  /// IDE chưa nối vào máy chủ chat (máy tính tắt / mất mạng).
  offline,

  /// Mạng hoặc IDE rớt, đang chờ nối lại.
  reconnecting,

  /// Máy này đã bị gỡ gắn.
  revoked,
}

final class IdeLinkStatus {
  const IdeLinkStatus(this.phase, {this.ready, this.reason});

  final IdeLinkPhase phase;
  final IdeReady? ready;
  final String? reason;
}

typedef IdeOpenChannel = Future<IdeChannel> Function();

/// Giữ stream rpc (nối lại lùi dần 1-16 s) và mở thêm stream `ai` / `term` /
/// `talk` có hạn mức. Rời mục / ra nền quá [idleCloseAfter] thì đóng hết, trừ
/// lúc đang tải tệp (giữ tới xong hoặc [transferGrace]).
final class IdeConnection {
  IdeConnection({
    required IdeOpenChannel openChannel,
    this.onRevoked,
    this.onReady,
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ],
    this.idleCloseAfter = const Duration(seconds: 60),
    this.transferGrace = const Duration(minutes: 5),
  }) : _openChannel = openChannel;

  static const maxAi = 6;
  static const maxTerm = 4;
  static const maxTalk = 1;

  final IdeOpenChannel _openChannel;

  /// IDE gỡ máy [deviceId] (`ide_closed: revoked`): xoá khoá nếu còn đúng máy đó.
  final Future<void> Function(String deviceId)? onRevoked;
  final void Function(IdeReady ready)? onReady;
  final List<Duration> backoff;
  final Duration idleCloseAfter;
  final Duration transferGrace;

  final _statusController = StreamController<IdeLinkStatus>.broadcast();
  final _rpcFrames = StreamController<Map<String, Object?>>.broadcast();
  final _rpcLost = StreamController<void>.broadcast();

  IdeLinkStatus _status = const IdeLinkStatus(IdeLinkPhase.idle);
  IdeChannel? _rpc;
  StreamSubscription<Map<String, Object?>>? _rpcSub;
  Timer? _retryTimer;
  Timer? _idleTimer;
  Timer? _graceTimer;
  int _attempt = 0;
  bool _wanted = false;
  bool _connecting = false;

  /// Tăng khi gắn lại máy: lần nối đang dở bằng khoá cũ bị bỏ.
  int _epoch = 0;
  bool _disposed = false;
  int _transfers = 0;
  final _extra = <IdeChannel>{};
  final _extraKind = <IdeChannel, IdeStreamKind>{};
  final _opening = <IdeStreamKind, int>{};

  IdeLinkStatus get status => _status;
  Stream<IdeLinkStatus> get statuses => _statusController.stream;

  /// Khung của stream rpc (mọi lần nối).
  Stream<Map<String, Object?>> get rpcFrames => _rpcFrames.stream;

  /// Phát mỗi lần stream rpc rơi: yêu cầu đang chờ phải báo lỗi, KHÔNG gửi lại.
  Stream<void> get rpcLost => _rpcLost.stream;

  /// Mã `stream` của lần nối rpc hiện tại (dùng ký khoá xác nhận).
  String get rpcStreamId => _rpc?.stream ?? '';

  IdeReady? get ready => _status.ready;

  void _set(IdeLinkStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Bắt đầu giữ đường nối (gọi khi vào mục IDE).
  void start() {
    if (_disposed) return;
    _wanted = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_rpc == null && !_connecting && _retryTimer == null) {
      unawaited(_connect());
    }
  }

  /// Vừa gắn lại máy (khoá mới): bỏ trạng thái "đã gỡ" và đường nối bằng khoá
  /// cũ, nối lại bằng khoá mới.
  Future<void> restartAfterPairing() async {
    if (_disposed) return;
    _epoch++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    final rpc = _rpc;
    _rpc = null;
    await _rpcSub?.cancel();
    _rpcSub = null;
    if (rpc != null) {
      if (!_rpcLost.isClosed) _rpcLost.add(null);
      await rpc.close();
    }
    await closeAll(keepRpc: false);
    if (_disposed) return;
    _set(const IdeLinkStatus(IdeLinkPhase.idle));
    start();
  }

  /// Nối lại ngay (nút Thử lại).
  void retryNow() {
    if (_disposed || _status.phase == IdeLinkPhase.revoked) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    _wanted = true;
    if (_rpc == null && !_connecting) unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_connecting || _disposed || !_wanted) return;
    _connecting = true;
    final epoch = _epoch;
    _set(
      IdeLinkStatus(
        _attempt == 0 ? IdeLinkPhase.connecting : IdeLinkPhase.reconnecting,
      ),
    );
    try {
      final channel = await _openChannel();
      if (_disposed || !_wanted || epoch != _epoch) {
        await channel.close();
        _connecting = false;
        if (!_disposed && _wanted) unawaited(_connect());
        return;
      }
      channel.send({'type': 'rpc'});
      _rpc = channel;
      _attempt = 0;
      _rpcSub = channel.frames.listen((frame) {
        if (!_rpcFrames.isClosed) _rpcFrames.add(frame);
      });
      unawaited(channel.done.then((close) => _onRpcClosed(channel, close)));
      _connecting = false;
      _set(IdeLinkStatus(IdeLinkPhase.ready, ready: channel.ready));
      onReady?.call(channel.ready);
    } on IdeHandshakeException catch (error) {
      _connecting = false;
      if (epoch != _epoch) {
        if (!_disposed && _wanted) unawaited(_connect());
        return;
      }
      await _handleFailure(error.reason, deviceId: error.deviceId);
    } on Object {
      _connecting = false;
      if (epoch != _epoch) {
        if (!_disposed && _wanted) unawaited(_connect());
        return;
      }
      await _handleFailure('socket');
    }
  }

  void _onRpcClosed(IdeChannel channel, IdeChannelClose close) {
    if (!identical(_rpc, channel)) return;
    _rpc = null;
    unawaited(_rpcSub?.cancel());
    _rpcSub = null;
    if (!_rpcLost.isClosed) _rpcLost.add(null);
    if (close.reason == 'local') return;
    unawaited(_handleFailure(close.reason, deviceId: channel.deviceId));
  }

  Future<void> _handleFailure(String reason, {String deviceId = ''}) async {
    if (_disposed) return;
    if (reason == 'revoked') {
      _wanted = false;
      _retryTimer?.cancel();
      _retryTimer = null;
      _set(IdeLinkStatus(IdeLinkPhase.revoked, reason: reason));
      await closeAll(keepRpc: false);
      await onRevoked?.call(deviceId);
      return;
    }
    if (reason == 'unauthorized') {
      // IDE từ chối khoá (có thể chỉ tạm): dừng, không xoá, người dùng tự thử
      // lại hoặc gắn lại.
      _wanted = false;
      _retryTimer?.cancel();
      _retryTimer = null;
      _set(IdeLinkStatus(IdeLinkPhase.idle, reason: reason));
      await closeAll(keepRpc: false);
      return;
    }
    if (reason == 'idle') {
      // IDE đóng vì im lâu (ping không tính): đóng bình thường, mở lại khi
      // người dùng thao tác (thử lại, vào lại màn, gọi mới).
      _wanted = false;
      _set(IdeLinkStatus(IdeLinkPhase.idle, reason: reason));
      return;
    }
    if (reason == 'not_paired' ||
        reason == 'no_session' ||
        reason == 'wrong_user') {
      // Thiếu khoá / phiên hoặc khác tài khoản: nối lại cũng vô ích.
      _wanted = false;
      _set(IdeLinkStatus(IdeLinkPhase.idle, reason: reason));
      return;
    }
    if (!_wanted) return;
    final delay =
        backoff[_attempt < backoff.length ? _attempt : backoff.length - 1];
    _attempt++;
    _set(
      IdeLinkStatus(
        reason == 'ide_offline'
            ? IdeLinkPhase.offline
            : IdeLinkPhase.reconnecting,
        reason: reason,
      ),
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }

  int _limit(IdeStreamKind kind) => switch (kind) {
    IdeStreamKind.ai => maxAi,
    IdeStreamKind.term => maxTerm,
    IdeStreamKind.talk => maxTalk,
    IdeStreamKind.rpc => 1,
  };

  /// Mở thêm một stream `ai` / `term` / `talk` và gửi [firstFrame] chọn kiểu.
  /// Quá hạn mức ném [IdeBusy].
  Future<IdeChannel> openStream(
    IdeStreamKind kind,
    Map<String, Object?> firstFrame,
  ) async {
    if (kind == IdeStreamKind.rpc) {
      throw ArgumentError('Stream rpc do IdeConnection giữ.');
    }
    if (_disposed) throw const IdeBusy('Kết nối IDE đã đóng.');
    // Giữ chỗ trước khi chờ mở: hai lần mở cùng lúc không vượt hạn mức.
    final used =
        _extraKind.values.where((k) => k == kind).length +
        (_opening[kind] ?? 0);
    if (used >= _limit(kind)) {
      throw const IdeBusy('Đã mở quá số phiên cho phép.');
    }
    _opening[kind] = (_opening[kind] ?? 0) + 1;
    final IdeChannel channel;
    try {
      channel = await _openChannel();
    } finally {
      _opening[kind] = (_opening[kind] ?? 1) - 1;
    }
    if (_disposed) {
      // Đăng xuất / đổi phiên trong lúc mở: không để stream đã xác thực sống.
      await channel.close();
      throw const IdeBusy('Kết nối IDE đã đóng.');
    }
    channel.send(firstFrame);
    _extra.add(channel);
    _extraKind[channel] = kind;
    unawaited(
      channel.done.then((close) {
        _extra.remove(channel);
        _extraKind.remove(channel);
        if (close.refused) {
          unawaited(_handleFailure(close.reason, deviceId: channel.deviceId));
        }
      }),
    );
    return channel;
  }

  /// Đánh dấu có tệp đang tải lên / xuống: không đóng kết nối khi ra nền.
  void beginTransfer() => _transfers++;

  void endTransfer() {
    if (_transfers > 0) _transfers--;
    if (_transfers == 0 && _graceTimer != null) {
      _graceTimer?.cancel();
      _graceTimer = null;
      unawaited(_stopAll());
    }
  }

  /// Rời mục IDE hoặc app ra nền: sau [idleCloseAfter] đóng hết.
  void markInactive() {
    if (_disposed || _idleTimer != null) return;
    _idleTimer = Timer(idleCloseAfter, () {
      _idleTimer = null;
      if (_transfers > 0) {
        _graceTimer?.cancel();
        _graceTimer = Timer(transferGrace, () {
          _graceTimer = null;
          unawaited(_stopAll());
        });
      } else {
        unawaited(_stopAll());
      }
    });
  }

  /// Quay lại mục IDE / app ra trước: huỷ hẹn đóng, nối lại nếu đã đóng.
  void markActive() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    if (!_wanted && _status.phase != IdeLinkPhase.revoked) {
      start();
    }
  }

  Future<void> _stopAll() async {
    _wanted = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    await closeAll(keepRpc: false);
    if (_status.phase != IdeLinkPhase.revoked) {
      _set(const IdeLinkStatus(IdeLinkPhase.idle));
    }
  }

  /// Đóng các stream phụ (và rpc nếu [keepRpc] sai).
  Future<void> closeAll({bool keepRpc = true}) async {
    for (final channel in _extra.toList()) {
      await channel.close();
    }
    if (!keepRpc) {
      final rpc = _rpc;
      if (rpc != null) await rpc.close();
    }
  }

  /// Gửi khung trên stream rpc; `false` khi chưa nối.
  bool sendRpc(Map<String, Object?> frame) {
    final rpc = _rpc;
    if (rpc != null) return rpc.send(frame);
    // Người dùng vừa thao tác sau khi stream đóng vì `idle`: nối lại cho lần sau.
    if (_status.reason == 'idle' && _status.phase == IdeLinkPhase.idle) {
      start();
    }
    return false;
  }

  Future<void> dispose() async {
    _disposed = true;
    _wanted = false;
    _retryTimer?.cancel();
    _idleTimer?.cancel();
    _graceTimer?.cancel();
    await closeAll(keepRpc: false);
    await _rpcSub?.cancel();
    await _statusController.close();
    await _rpcFrames.close();
    await _rpcLost.close();
  }
}
