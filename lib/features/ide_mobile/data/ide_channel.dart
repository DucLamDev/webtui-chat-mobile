import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/ide_ready.dart';

/// Ổ cắm văn bản tối thiểu (bọc `WebSocket`, có bản giả trong test).
abstract interface class IdeSocket {
  Stream<String> get messages;
  void send(String text);
  Future<void> close();
}

final class WebSocketIdeSocket implements IdeSocket {
  WebSocketIdeSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages =>
      _socket.where((event) => event is String).map((event) => event as String);

  @override
  void send(String text) {
    if (_socket.readyState == WebSocket.open) _socket.add(text);
  }

  @override
  Future<void> close() => _socket.close();
}

/// Lý do bắt tay không được tự nối lại: IDE từ chối / gỡ khoá máy, chưa gắn,
/// không có phiên chat, khác tài khoản, phiên hết hạn (401 sau khi làm mới
/// token), không được dùng IDE ở đây (403).
const ideFatalReasons = {
  'unauthorized',
  'revoked',
  'not_paired',
  'no_session',
  'wrong_user',
  'session_expired',
  'forbidden',
  ideDisabledReason,
};

/// Máy chủ chat tắt IDE (công tắc tắt khẩn): đóng mọi stream, không nối lại.
const ideDisabledReason = 'disabled';

/// Cổng chưa mở loại stream / thao tác này cho điện thoại. Không tự nối lại
/// (thử lại vẫn bị từ chối) nhưng không dừng các stream khác.
const ideNotAllowedReason = 'not_allowed';

/// Bắt tay thất bại hoặc IDE đóng ngay.
final class IdeHandshakeException implements Exception {
  const IdeHandshakeException(this.reason, {this.deviceId = ''});

  /// `unauthorized | revoked | ide_offline | timeout | socket | <lý do khác>`.
  final String reason;

  /// Mã máy đã dùng khi nối (`''` nếu chưa tới bước gửi khoá).
  final String deviceId;

  /// IDE gỡ máy này (xoá khoá đã gắn). `unauthorized` có thể chỉ là lỗi tạm
  /// (challenge quá hạn...) nên không tính.
  bool get revoked => reason == 'revoked';
  bool get offline => reason == 'ide_offline';

  /// Nối lại cũng vô ích (khoá / phiên / quyền sai): dừng, chờ người dùng.
  bool get fatal => ideFatalReasons.contains(reason);

  /// Cổng chưa mở cho điện thoại ([ideNotAllowedReason]): không thử lại.
  bool get notAllowed => reason == ideNotAllowedReason;

  @override
  String toString() => 'IdeHandshakeException($reason)';
}

/// Vì sao một stream đóng.
final class IdeChannelClose {
  const IdeChannelClose(this.reason);

  /// `ide_offline | revoked | limit | idle | slow_consumer | ... | dead |
  /// socket | local`.
  final String reason;

  bool get revoked => reason == 'revoked';

  /// IDE gỡ máy hoặc từ chối khoá: không tự nối lại.
  bool get refused => revoked || reason == 'unauthorized';

  /// Cổng chưa mở loại stream này cho điện thoại: không tự nối lại.
  bool get notAllowed => reason == ideNotAllowedReason;

  /// Máy chủ chat vừa tắt IDE: không tự nối lại.
  bool get disabled => reason == ideDisabledReason;
}

typedef IdeSignAuth =
    Future<String> Function(String nonce, String stream, String chatUser);

/// Một stream IDE (một WebSocket): bắt tay `challenge -> auth -> ready`, rồi
/// chuyển khung JSON. Giải nén `{"type":"gz"}`, gửi `ping` định kỳ và coi như
/// chết khi im quá [deadAfter].
final class IdeChannel {
  IdeChannel._(this._socket, this._deadAfter) {
    _subscription = _socket.messages.listen(
      _onMessage,
      onError: (_) => _onSocketEnd(),
      onDone: _onSocketEnd,
      cancelOnError: true,
    );
  }

  final IdeSocket _socket;
  final Duration _deadAfter;

  late final StreamSubscription<String> _subscription;
  Timer? _timer;
  final _handshake = StreamController<Map<String, Object?>>();
  final _frames = StreamController<Map<String, Object?>>();
  final _done = Completer<IdeChannelClose>();
  DateTime _lastInbound = DateTime.now();
  bool _handshakeDone = false;
  bool _closed = false;

  String stream = '';
  String chatUser = '';

  /// Mã máy (`d_…`) dùng khi bắt tay; factory đặt sau khi nối.
  String deviceId = '';
  IdeReady ready = const IdeReady();

  /// Khung sau `ready` (đã giải nén; không có `pong`, `ide_*`).
  Stream<Map<String, Object?>> get frames => _frames.stream;

  Future<IdeChannelClose> get done => _done.future;

  bool get isOpen => !_closed;

  /// Nối, bắt tay, trả kênh đã `ready`. Lỗi bắt tay ném
  /// [IdeHandshakeException] và đóng ổ cắm.
  static Future<IdeChannel> connect({
    required IdeSocket socket,
    required IdeSignAuth signAuth,
    Duration handshakeTimeout = const Duration(seconds: 15),
    Duration pingEvery = const Duration(seconds: 12),
    Duration deadAfter = const Duration(seconds: 35),
  }) async {
    final channel = IdeChannel._(socket, deadAfter);
    final iterator = StreamIterator<Map<String, Object?>>(
      channel._handshake.stream,
    );
    Future<Map<String, Object?>> next() async {
      final has = await iterator.moveNext().timeout(
        handshakeTimeout,
        onTimeout: () => throw const IdeHandshakeException('timeout'),
      );
      if (!has) throw const IdeHandshakeException('socket');
      final frame = iterator.current;
      if (frame['type'] == 'ide_offline') {
        throw const IdeHandshakeException('ide_offline');
      }
      if (frame['type'] == 'ide_closed') {
        throw IdeHandshakeException('${frame['reason'] ?? 'socket'}');
      }
      return frame;
    }

    try {
      final challenge = await next();
      final nonce = challenge['nonce'];
      final stream = challenge['stream'];
      final chatUser = challenge['chat_user'];
      if (challenge['type'] != 'challenge' ||
          nonce is! String ||
          stream is! String ||
          chatUser is! String) {
        throw const IdeHandshakeException('protocol');
      }
      final sig = await signAuth(nonce, stream, chatUser);
      socket.send(jsonEncode({'type': 'auth', 'sig': sig}));
      final ready = await next();
      if (ready['type'] != 'ready') {
        throw const IdeHandshakeException('protocol');
      }
      channel
        ..stream = stream
        ..chatUser = chatUser
        ..ready = IdeReady.fromFrame(ready)
        .._handshakeDone = true
        .._lastInbound = DateTime.now()
        .._timer = Timer.periodic(pingEvery, (_) => channel._tick());
      unawaited(iterator.cancel());
      return channel;
    } on Object {
      unawaited(iterator.cancel());
      channel._finish('handshake');
      rethrow;
    }
  }

  static Map<String, Object?>? _decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final frame = Map<String, Object?>.from(json);
      if (frame['type'] == 'gz') {
        final data = frame['data'];
        if (data is! String) return null;
        final inflated = ideGunzipBounded(base64Decode(data));
        if (inflated == null) return null;
        final inner = jsonDecode(utf8.decode(inflated));
        return inner is Map ? Map<String, Object?>.from(inner) : null;
      }
      return frame;
    } on Object {
      return null;
    }
  }

  void _onSocketEnd() {
    if (!_handshakeDone) {
      if (!_handshake.isClosed) {
        _handshake.add({'type': 'ide_closed', 'reason': 'socket'});
      }
    }
    _finish('socket');
  }

  void _onMessage(String text) {
    _lastInbound = DateTime.now();
    final frame = _decode(text);
    if (frame == null) return;
    if (!_handshakeDone) {
      if (!_handshake.isClosed) _handshake.add(frame);
      return;
    }
    switch (frame['type']) {
      case 'pong':
        return;
      case 'ide_offline':
        _finish('ide_offline');
        return;
      case 'ide_closed':
        _finish('${frame['reason'] ?? 'socket'}');
        return;
    }
    if (!_frames.isClosed) _frames.add(frame);
  }

  void _tick() {
    if (_closed) return;
    if (DateTime.now().difference(_lastInbound) > _deadAfter) {
      _finish('dead');
      return;
    }
    send({'type': 'ping'});
  }

  /// Gửi một khung JSON; `false` khi kênh đã đóng.
  bool send(Map<String, Object?> frame) {
    if (_closed) return false;
    _socket.send(jsonEncode(frame));
    return true;
  }

  void _finish(String reason) {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_socket.close().catchError((_) {}));
    if (!_handshake.isClosed) unawaited(_handshake.close());
    if (!_frames.isClosed) unawaited(_frames.close());
    if (!_done.isCompleted) _done.complete(IdeChannelClose(reason));
  }

  /// Đóng do app.
  Future<void> close() async => _finish('local');
}

/// Giới hạn sau giải nén của khung `gz` (chặn bom gzip).
const ideMaxInflatedBytes = 8 * 1024 * 1024;

/// Giải nén gzip từng khúc; vượt [limit] byte thì bỏ (`null`).
List<int>? ideGunzipBounded(List<int> data, {int limit = ideMaxInflatedBytes}) {
  final sink = _BoundedBytesSink(limit);
  try {
    gzip.decoder.startChunkedConversion(sink)
      ..add(data)
      ..close();
  } on _TooLarge {
    return null;
  }
  return sink.takeBytes();
}

final class _TooLarge implements Exception {
  const _TooLarge();
}

final class _BoundedBytesSink implements Sink<List<int>> {
  _BoundedBytesSink(this.limit);

  final int limit;
  final _out = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (_out.length + chunk.length > limit) throw const _TooLarge();
    _out.add(chunk);
  }

  @override
  void close() {}

  List<int> takeBytes() => _out.takeBytes();
}
