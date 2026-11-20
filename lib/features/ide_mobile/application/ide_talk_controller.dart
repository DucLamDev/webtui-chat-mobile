import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ide_channel.dart';
import '../data/ide_connection.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_talk_models.dart';
import 'ide_talk_service.dart';

enum IdeTalkLink {
  connecting,
  live,

  /// Mất kết nối / app ở nền: tự mở lại, có nút "Nối lại".
  lost,

  /// Cuộc đã bị xoá (`gone`).
  gone,
  notFound,
  denied,
  busy,
  failed,
}

/// Tệp / ảnh đính kèm đã chọn trên máy (tách khỏi widget để test).
final class IdeTalkAttachment {
  const IdeTalkAttachment({
    required this.name,
    required this.mime,
    required this.size,
    required this.image,
    required this.read,
  });

  final String name;
  final String mime;
  final int size;
  final bool image;
  final Stream<List<int>> Function() read;
}

final class IdeTalkState {
  const IdeTalkState({
    this.link = IdeTalkLink.connecting,
    this.conversation,
    this.working = const {},
    this.message = '',
  });

  final IdeTalkLink link;
  final IdeTalkConversation? conversation;

  /// Khoá các thao tác đang chạy (chống bấm hai lần): `send`, `stop`...
  final Set<String> working;
  final String message;

  bool isWorking(String key) => working.contains(key);

  IdeTalkState copyWith({
    IdeTalkLink? link,
    IdeTalkConversation? conversation,
    Set<String>? working,
    String? message,
  }) => IdeTalkState(
    link: link ?? this.link,
    conversation: conversation ?? this.conversation,
    working: working ?? this.working,
    message: message ?? this.message,
  );
}

/// Điều khiển một stream `talk` của một cuộc: khung đầy đủ → state, `delta`
/// thay tin cuối, `heartbeat` (im quá [idleReopenAfter] thì mở lại), `gone`.
/// Đổi sang cuộc khác = controller mới (state sạch). Đóng / ra nền thì đóng
/// stream, không giữ chỗ trong bộ đếm của kết nối.
class IdeTalkController extends StateNotifier<IdeTalkState> {
  IdeTalkController({
    required IdeConnection connection,
    required IdeTalkService service,
    required this.talkId,
    this.idleReopenAfter = const Duration(seconds: 50),
    this.idleCheckEvery = const Duration(seconds: 5),
    this.retryAfter = const Duration(seconds: 4),
    this.deltaBackoffBase = const Duration(seconds: 1),
  }) : _connection = connection,
       _service = service,
       super(const IdeTalkState());

  final IdeConnection _connection;
  final IdeTalkService _service;
  final String talkId;
  final Duration idleReopenAfter;
  final Duration idleCheckEvery;
  final Duration retryAfter;

  /// Giãn cách mở lại khi delta mang mã tin lạ: base, 2×, 4×… tối đa 30×.
  final Duration deltaBackoffBase;

  /// Số lần liền nhận delta mã tin lạ (về 0 khi một delta khớp).
  static const maxDeltaMisses = 5;
  int _deltaMisses = 0;

  IdeChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _sub;
  Timer? _watchdog;
  Timer? _retry;
  final _clock = Stopwatch()..start();
  Duration _lastFrame = Duration.zero;
  Duration _lastDeltaReopen = const Duration(days: -1);
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  bool _paused = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_disposed || _paused) return;
    final generation = ++_generation;
    // Chờ stream cũ đóng hẳn: còn đếm trong hạn mức thì mở lại bị `busy`.
    await _stopChannel();
    if (_disposed || generation != _generation) return;
    _retry?.cancel();
    _set(state.copyWith(link: IdeTalkLink.connecting));
    _connection.start();
    final IdeChannel channel;
    try {
      channel = await _connection.openStream(IdeStreamKind.talk, {
        'type': 'talk',
        'id': talkId,
      });
    } on IdeBusy {
      if (_disposed || generation != _generation) return;
      _set(state.copyWith(link: IdeTalkLink.busy));
      return;
    } on IdeHandshakeException catch (e) {
      if (_disposed || generation != _generation) return;
      if (!e.fatal) {
        _lose();
        return;
      }
      // Hết phiên / không có quyền / máy bị gỡ: tự nối lại chỉ lặp lỗi (và
      // làm mới token mãi). Dừng, chờ người dùng bấm Thử lại.
      _retry?.cancel();
      _set(
        state.copyWith(
          link: e.reason == 'forbidden'
              ? IdeTalkLink.denied
              : IdeTalkLink.failed,
          message: e.reason,
        ),
      );
      return;
    } on Object {
      if (_disposed || generation != _generation) return;
      _lose();
      return;
    }
    if (_disposed || generation != _generation || _paused) {
      await channel.close();
      return;
    }
    _channel = channel;
    _lastFrame = _clock.elapsed;
    _sub = channel.frames.listen(_onFrame);
    unawaited(channel.done.then((close) => _onClosed(channel)));
    _watchdog = Timer.periodic(idleCheckEvery, (_) => _checkIdle());
  }

  void _checkIdle() {
    if (_channel == null || _disposed) return;
    if (_clock.elapsed - _lastFrame > idleReopenAfter) unawaited(_open());
  }

  void _onFrame(Map<String, Object?> f) {
    _lastFrame = _clock.elapsed;
    if (f['type'] == 'error') {
      final code = f['code'] is String ? f['code']! as String : '';
      final link = switch (code) {
        'forbidden' => IdeTalkLink.denied,
        'not_found' => IdeTalkLink.notFound,
        'busy' => IdeTalkLink.busy,
        _ => IdeTalkLink.failed,
      };
      unawaited(_stopChannel());
      _set(
        state.copyWith(
          link: link,
          message: f['message'] is String ? f['message']! as String : '',
        ),
      );
      return;
    }
    if (f['type'] != 'talk_delta') return;
    final frame = IdeTalkFrame.parse(f);
    switch (frame) {
      case null:
      case IdeTalkHeartbeat():
        return;
      case IdeTalkGone():
        unawaited(_stopChannel());
        _set(state.copyWith(link: IdeTalkLink.gone));
      case IdeTalkFull(:final conversation):
        if (conversation.id != talkId) return;
        _set(
          state.copyWith(link: IdeTalkLink.live, conversation: conversation),
        );
      case IdeTalkDelta(:final message, :final talkId):
        // Khung của cuộc khác thì bỏ qua (khung không ghi id thì nhận).
        if (talkId != null && talkId != this.talkId) return;
        final conv = state.conversation;
        final msgs = conv?.messages ?? const <IdeTalkMessage>[];
        if (conv == null || msgs.isEmpty || msgs.last.id != message.id) {
          // Tin lạ: mở lại để nhận khung đầy đủ, giãn dần; quá
          // [maxDeltaMisses] lần liền thì báo lỗi (có nút Nối lại).
          final gap = _deltaMisses == 0
              ? Duration.zero
              : deltaBackoffBase * (1 << (_deltaMisses - 1)).clamp(1, 30);
          if (_clock.elapsed - _lastDeltaReopen < gap) return;
          if (_deltaMisses >= maxDeltaMisses) {
            unawaited(_stopChannel());
            _set(
              state.copyWith(
                link: IdeTalkLink.failed,
                message: 'Tin nhận về không khớp.',
              ),
            );
            return;
          }
          _deltaMisses++;
          _lastDeltaReopen = _clock.elapsed;
          unawaited(_open());
          return;
        }
        _deltaMisses = 0;
        _set(
          state.copyWith(
            link: IdeTalkLink.live,
            conversation: conv.withMessages([
              ...msgs.sublist(0, msgs.length - 1),
              message,
            ]),
          ),
        );
    }
  }

  void _onClosed(IdeChannel channel) {
    if (!identical(_channel, channel)) return;
    unawaited(_stopChannel());
    if (_disposed || _paused) return;
    _lose();
  }

  void _lose() {
    _set(state.copyWith(link: IdeTalkLink.lost));
    _retry?.cancel();
    _retry = Timer(retryAfter, () {
      if (!_disposed && !_paused && state.link == IdeTalkLink.lost) {
        unawaited(_open());
      }
    });
  }

  Future<void> _stopChannel() async {
    final channel = _channel;
    _channel = null;
    _watchdog?.cancel();
    _watchdog = null;
    unawaited(_sub?.cancel());
    _sub = null;
    if (channel == null) return;
    await channel.close();
    await channel.done
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw TimeoutException('close'),
        )
        .then((_) {}, onError: (_) {});
  }

  /// Nối lại bằng tay.
  void reconnect() {
    if (_disposed) return;
    if (const {
      IdeTalkLink.lost,
      IdeTalkLink.busy,
      IdeTalkLink.failed,
    }.contains(state.link)) {
      _paused = false;
      _deltaMisses = 0;
      unawaited(_open());
    }
  }

  /// App ra nền: đóng stream, không đếm vào hạn mức.
  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    _generation++;
    _retry?.cancel();
    unawaited(_stopChannel());
    if (state.link == IdeTalkLink.live ||
        state.link == IdeTalkLink.connecting) {
      _set(state.copyWith(link: IdeTalkLink.lost));
    }
  }

  /// Quay lại: mở lại stream (khung đầu là bản đầy đủ).
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    if (state.link == IdeTalkLink.gone ||
        state.link == IdeTalkLink.denied ||
        state.link == IdeTalkLink.notFound) {
      return;
    }
    unawaited(_open());
  }

  // ----- thao tác (chống bấm hai lần theo khoá) -----

  Future<T?> guard<T>(String key, Future<T> Function() body) async {
    if (state.working.contains(key) || _disposed) return null;
    _set(state.copyWith(working: {...state.working, key}));
    try {
      return await body();
    } finally {
      if (!_disposed) {
        _set(state.copyWith(working: {...state.working}..remove(key)));
      }
    }
  }

  /// Gửi tin: tải ảnh / tệp lên lấy `ref`, rồi `talk.send` (đang bận thì xếp
  /// hàng chờ). Trả `null` nếu đang gửi lượt khác.
  Future<IdeTalkSendResult?> send(
    String text, {
    List<IdeTalkAttachment> attachments = const [],
  }) => guard('send', () async {
    final body = text.trim();
    if (body.isEmpty) throw const IdeBadRequest('Tin nhắn trống.');
    if (text.length > ideTalkMaxText) {
      throw const IdeTooLarge('Tin nhắn quá dài.');
    }
    final images = attachments.where((a) => a.image).toList();
    final files = attachments.where((a) => !a.image).toList();
    if (images.length > ideTalkMaxImages || files.length > ideTalkMaxFiles) {
      throw const IdeTooLarge('Đính kèm quá nhiều.');
    }
    // Kiểm cỡ MỌI tệp trước khi tải cái đầu tiên (không tải dở rồi mới lỗi).
    for (final a in attachments) {
      if (a.size > (a.image ? ideTalkMaxImageBytes : ideTalkMaxFileBytes)) {
        throw IdeTooLarge(a.image ? 'Ảnh quá 20 MB.' : 'Tệp quá 50 MB.');
      }
    }
    final imageRefs = <String>[];
    final fileRefs = <String>[];
    for (final a in attachments) {
      final ref = await _service.uploadAttachment(
        image: a.image,
        name: a.name,
        mime: a.mime,
        size: a.size,
        read: a.read,
      );
      (a.image ? imageRefs : fileRefs).add(ref);
    }
    final result = await _service.send(
      id: talkId,
      text: text,
      queue: state.conversation?.working ?? false,
      images: imageRefs,
      files: fileRefs,
    );
    if (_disposed) return result;
    if (state.link == IdeTalkLink.lost) reconnect();
    return result;
  });

  Future<void> stop() async {
    await guard('stop', () => _service.stop(talkId));
  }

  Future<void> queueRun() async {
    await guard('queue_run', () => _service.queueRun(talkId));
  }

  Future<void> unqueue(String item) async {
    await guard('unqueue:$item', () => _service.unqueue(talkId, item));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    unawaited(_stopChannel());
    super.dispose();
  }

  void _set(IdeTalkState next) {
    if (!_disposed) state = next;
  }
}
