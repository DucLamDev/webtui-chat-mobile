import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../data/ide_channel.dart';
import '../data/ide_connection.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_term.dart';

enum IdeTermLink {
  connecting,
  live,

  /// Mất kết nối (phiên vẫn chạy trên máy tính): có nút "Nối lại".
  lost,

  /// IDE đóng stream (`ide_error`) khi phiên đang chạy: thường do thiết bị
  /// khác gắn phiên này (phiên vẫn sống). KHÔNG tự nối lại, chờ người dùng bấm
  /// "Mở lại ở đây" để hai máy không giành nhau.
  taken,

  /// Phiên đã kết thúc (`texit`).
  exited,

  /// IDE cấm terminal trên điện thoại (`forbidden`).
  denied,

  /// Đã mở quá số terminal cho phép (`busy`).
  busy,

  /// Phiên không còn (`not_found`).
  notFound,

  /// Lỗi mở khác.
  failed,
}

final class IdeTermSnapshot {
  const IdeTermSnapshot({
    this.link = IdeTermLink.connecting,
    this.name = '',
    this.exitCode,
    this.message = '',
    this.ctrl = false,
    this.alt = false,
  });

  final IdeTermLink link;
  final String name;
  final int? exitCode;
  final String message;
  final bool ctrl;
  final bool alt;

  bool get isLive => link == IdeTermLink.live;

  IdeTermSnapshot copyWith({
    IdeTermLink? link,
    String? name,
    int? exitCode,
    String? message,
    bool? ctrl,
    bool? alt,
  }) => IdeTermSnapshot(
    link: link ?? this.link,
    name: name ?? this.name,
    exitCode: exitCode ?? this.exitCode,
    message: message ?? this.message,
    ctrl: ctrl ?? this.ctrl,
    alt: alt ?? this.alt,
  );
}

/// Điều khiển một stream `term`: mở / gắn phiên, nhận `tout` đưa vào xterm,
/// gửi `tin` / `resize`, báo `texit`, nối lại khi người dùng bấm.
/// Đóng màn chỉ đóng stream, không giết phiên (chỉ `term.kill` mới giết).
class IdeTermController extends StateNotifier<IdeTermSnapshot> {
  IdeTermController({
    required IdeConnection connection,
    required IdeTermOpenTarget target,
    this.pingEvery = const Duration(seconds: 20),
    this.resizeDebounce = const Duration(milliseconds: 150),
    int initialCols = 80,
    int initialRows = 24,
  }) : _connection = connection,
       _target = target,
       _openCols = initialCols,
       _openRows = initialRows,
       super(IdeTermSnapshot(name: target.name ?? '')) {
    terminal = Terminal(maxLines: 5000)
      ..resize(initialCols, initialRows)
      ..onOutput = _onTyped
      ..onResize = (w, h, _, _) => _onViewResize(w, h);
  }

  final IdeConnection _connection;
  final IdeTermOpenTarget _target;
  final Duration pingEvery;
  final Duration resizeDebounce;

  /// Bộ máy vẽ terminal (giữ nguyên khi màn dựng lại).
  late final Terminal terminal;

  final _mods = IdeTermModifiers();
  IdeChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _sub;
  Timer? _pingTimer;
  Timer? _resizeTimer;
  IdeTermUtf8Decoder _decoder = IdeTermUtf8Decoder();
  bool _started = false;
  bool _disposed = false;
  int _generation = 0;
  String _name = '';
  int _openCols;
  int _openRows;
  int _sentCols = 0;
  int _sentRows = 0;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_disposed) return;
    final generation = ++_generation;
    _set(state.copyWith(link: IdeTermLink.connecting, message: ''));
    _connection.start();
    final frame = _name.isNotEmpty
        ? IdeTermOpenTarget.existing(_name).frame(_openCols, _openRows)
        : _target.frame(_openCols, _openRows);
    final IdeChannel channel;
    try {
      channel = await _connection.openStream(IdeStreamKind.term, frame);
    } on IdeBusy catch (e) {
      if (_disposed || generation != _generation) return;
      _set(
        state.copyWith(
          link: IdeTermLink.busy,
          message: e.message.isEmpty
              ? 'Đã mở quá số terminal cho phép'
              : e.message,
        ),
      );
      return;
    } on Object {
      if (_disposed || generation != _generation) return;
      _set(state.copyWith(link: IdeTermLink.lost));
      return;
    }
    if (_disposed || generation != _generation) {
      await channel.close();
      return;
    }
    _channel = channel;
    _sentCols = 0;
    _sentRows = 0;
    _sub = channel.frames.listen(_onFrame);
    unawaited(channel.done.then((close) => _onClosed(channel, close)));
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingEvery, (_) => _send({'type': 'ping'}));
  }

  void _onFrame(Map<String, Object?> f) {
    switch (f['type']) {
      case 'tready':
        final name = f['name'];
        if (name is String && name.isNotEmpty) _name = name;
        _sentCols = _asInt(f['cols']) ?? 0;
        _sentRows = _asInt(f['rows']) ?? 0;
        _set(state.copyWith(link: IdeTermLink.live, name: _name));
        // Màn đã đo xong khác cỡ IDE biết: báo ngay.
        _flushResize();
      case 'tout':
        final data = f['data'];
        if (data is! String) return;
        final List<int> bytes;
        try {
          bytes = base64Decode(data);
        } on FormatException {
          return;
        }
        final text = _decoder.decode(bytes);
        // Terminal tự trả lời (vị trí con trỏ...) qua onOutput: gửi nguyên văn.
        if (text.isNotEmpty) _raw(() => terminal.write(text));
      case 'texit':
        final code = _asInt(f['code']) ?? 0;
        _stopChannel();
        _set(state.copyWith(link: IdeTermLink.exited, exitCode: code));
      case 'error':
        final code = f['code'] is String ? f['code']! as String : '';
        final message = f['message'] is String ? f['message']! as String : '';
        final link = switch (code) {
          'forbidden' => IdeTermLink.denied,
          'busy' => IdeTermLink.busy,
          'not_found' => IdeTermLink.notFound,
          _ => IdeTermLink.failed,
        };
        _stopChannel();
        _set(state.copyWith(link: link, message: message));
    }
  }

  void _onClosed(IdeChannel channel, IdeChannelClose close) {
    if (!identical(_channel, channel)) return;
    final wasLive = state.link == IdeTermLink.live;
    _stopChannel();
    if (_disposed) return;
    // Luồng bị IDE đóng khi đang chạy: phiên được gắn ở máy khác.
    final taken = wasLive && close.reason == 'ide_error' && _name.isNotEmpty;
    _set(
      state.copyWith(
        link: taken ? IdeTermLink.taken : IdeTermLink.lost,
        message: close.reason,
      ),
    );
  }

  void _stopChannel() {
    final channel = _channel;
    _channel = null;
    _pingTimer?.cancel();
    _resizeTimer?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    if (channel != null) unawaited(channel.close());
  }

  /// Nối lại phiên đã mất kết nối (hoặc bị máy khác chiếm, theo yêu cầu người
  /// dùng) bằng `{"type":"term","name"}`.
  void reconnect() {
    if (_disposed ||
        (state.link != IdeTermLink.lost && state.link != IdeTermLink.taken)) {
      return;
    }
    _stopChannel();
    // IDE vẽ lại màn hình khi gắn: xoá bản cũ để không chồng chữ.
    terminal.write('\x1b[?1049l\x1b[0m\x1b[?1l\x1b[?25h\x1b[?2004l');
    terminal.mainBuffer.clear();
    terminal.write('\x1b[H');
    _decoder = IdeTermUtf8Decoder();
    _openCols = terminal.viewWidth;
    _openRows = terminal.viewHeight;
    unawaited(_open());
  }

  // ----- gõ phím -----

  /// Đang dán / terminal tự trả lời: không áp Ctrl / Alt dính.
  bool _rawOutput = false;

  void _raw(void Function() body) {
    _rawOutput = true;
    try {
      body();
    } finally {
      _rawOutput = false;
    }
  }

  /// Văn bản từ bàn phím mềm: áp Ctrl / Alt dính rồi gửi.
  void _onTyped(String text) {
    if (_rawOutput) {
      sendText(text);
      return;
    }
    final out = _mods.applyTyped(text);
    _syncMods();
    sendText(out);
  }

  /// Dán chữ đã làm sạch ([ideTermCleanPaste]); bọc chế độ dán an toàn nếu
  /// chương trình đang chạy bật nó.
  void paste(String text) {
    final clean = ideTermCleanPaste(text);
    if (clean.isEmpty) return;
    _raw(() => terminal.paste(clean));
  }

  /// Gửi nguyên văn (không áp Ctrl / Alt). Chia khung ≤ 64 KB.
  void sendText(String text) {
    if (!state.isLive || text.isEmpty) return;
    for (final chunk in ideTermChunks(text)) {
      _send({'type': 'tin', 'data': base64Encode(chunk)});
    }
  }

  void toggleCtrl() {
    _mods.ctrl = !_mods.ctrl;
    _syncMods();
  }

  void toggleAlt() {
    _mods.alt = !_mods.alt;
    _syncMods();
  }

  /// Phím phụ gửi chuỗi cố định (Esc, Tab, `|`...): Ctrl / Alt dính áp lên.
  void pressText(String text) {
    sendText(_mods.applyTyped(text));
    _syncMods();
  }

  /// Phím điều hướng: dựng chuỗi theo bổ trợ đang giữ và chế độ con trỏ.
  void pressNav(String Function(int mod, bool appCursor) build) {
    sendText(_mods.applyKey((mod) => build(mod, terminal.cursorKeysMode)));
    _syncMods();
  }

  void _syncMods() {
    if (_mods.ctrl != state.ctrl || _mods.alt != state.alt) {
      _set(state.copyWith(ctrl: _mods.ctrl, alt: _mods.alt));
    }
  }

  // ----- đổi cỡ -----

  void _onViewResize(int cols, int rows) {
    _openCols = cols;
    _openRows = rows;
    if (!state.isLive) return;
    _resizeTimer?.cancel();
    _resizeTimer = Timer(resizeDebounce, _flushResize);
  }

  void _flushResize() {
    if (!state.isLive) return;
    final cols = ideTermCols(terminal.viewWidth);
    final rows = ideTermRows(terminal.viewHeight);
    if (cols == _sentCols && rows == _sentRows) return;
    _sentCols = cols;
    _sentRows = rows;
    _send({'type': 'resize', 'cols': cols, 'rows': rows});
  }

  // ----- tiện ích -----

  bool _send(Map<String, Object?> frame) => _channel?.send(frame) ?? false;

  void _set(IdeTermSnapshot next) {
    if (!_disposed) state = next;
  }

  int? _asInt(Object? v) => v is num ? v.toInt() : null;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _stopChannel();
    super.dispose();
  }
}
