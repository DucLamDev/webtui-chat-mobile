import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ide_errors.dart';
import '../domain/ide_media_models.dart';
import 'ide_media_service.dart';
import 'ide_project_service.dart';

bool _yes() => true;

enum IdeAppPhase { loading, noTool, ready, error }

/// Dòng tiến trình hiện tối đa chừng này (dòng cuối của log việc).
const ideAppLogLines = 14;

/// Trạng thái màn xem trước app: kiểm máy, phiên, khung ảnh (1 giây / lần),
/// mở / đổi thiết lập (việc nền) và dừng. CHỈ XEM: không có thao tác chạm / gõ.
class IdeAppScreenController extends ChangeNotifier {
  IdeAppScreenController({
    required this.media,
    required this.jobs,
    required this.project,
    required this.canRun,
    required this.isActive,
    this.hasCheck = _yes,
    this.linkReady = _yes,
    this.frameInterval = const Duration(seconds: 1),
    this.jobPoll = const Duration(milliseconds: 1000),
  }) {
    _poller = IdePoller(
      interval: frameInterval,
      shouldRun: () =>
          !_disposed && isActive() && linkReady() && _session != null,
      task: _tickFrame,
    );
  }

  final IdeMediaService media;
  final IdeProjectService jobs;
  final String project;
  final bool Function() canRun;
  final bool Function() hasCheck;

  /// Kết nối IDE đang ready: mất kết nối / bị gỡ thì không hỏi khung.
  final bool Function() linkReady;
  final bool Function() isActive;
  final Duration frameInterval;
  final Duration jobPoll;

  late final IdePoller _poller;
  bool _disposed = false;

  /// Thế hệ lượt hỏi khung: tăng khi run / stop / đóng phiên, kết quả cũ bị bỏ.
  int _gen = 0;
  IdeAppPhase phase = IdeAppPhase.loading;
  Object? error;
  IdeAppStatus status = const IdeAppStatus();
  IdeAppFrame? frame;

  /// Đang dựng (khung báo `busy`).
  bool building = false;

  /// Chưa có phiên (khung báo `not_found`).
  bool notOpen = false;
  bool frameFailing = false;
  bool running = false;
  bool stopping = false;
  List<String> log = const [];
  String? runError;
  String? runMessage;
  IdeAppSession? _session;

  IdeAppSession? get session => _session;

  Future<void> load() async {
    phase = IdeAppPhase.loading;
    error = null;
    _notify();
    try {
      if (hasCheck() && !(await media.appCheck()).run) {
        if (_disposed) return;
        phase = IdeAppPhase.noTool;
        return _notify();
      }
      final st = await media.appStatus();
      if (_disposed) return;
      _apply(st);
      phase = IdeAppPhase.ready;
    } on Object catch (e) {
      if (_disposed) return;
      error = e;
      phase = IdeAppPhase.error;
    }
    _notify();
    if (phase == IdeAppPhase.ready) _startFrames();
  }

  void _apply(IdeAppStatus st) {
    status = st;
    _session = st.sessionOf(project);
    notOpen = _session == null;
    building = _session?.starting ?? false;
    if (_session == null) frame = null;
  }

  void _startFrames() {
    if (_session == null) return _poller.stop();
    _poller.start();
    unawaited(_poller.poke());
  }

  /// App về lại / màn hiện lại: hỏi ngay một khung.
  void resume() {
    if (_disposed || phase != IdeAppPhase.ready) return;
    if (_session != null) {
      _poller.start();
      unawaited(_poller.poke());
    }
  }

  Future<void> _tickFrame() async {
    final gen = _gen;
    try {
      final f = await media.appFrame(project);
      if (_disposed || gen != _gen) return;
      building = false;
      notOpen = false;
      frameFailing = false;
      if (f != null) frame = f; // khung hỏng: bỏ, giữ khung cũ
      _notify();
    } on IdeNotFound {
      if (_disposed || gen != _gen) return;
      // Phiên đã đóng (người khác dừng / hết hạn): thôi hỏi, hỏi lại trạng thái.
      frame = null;
      _poller.stop();
      try {
        final st = await media.appStatus();
        if (_disposed || gen != _gen) return;
        _apply(st);
      } on Object {
        if (_disposed || gen != _gen) return;
        _session = null;
        notOpen = true;
      }
      if (_session == null) notOpen = true;
      _notify();
      if (_session != null) _startFrames();
    } on IdeBusy {
      if (_disposed || gen != _gen) return;
      building = true; // đang dựng: hỏi tiếp ở nhịp sau
      _notify();
    } on IdeForbidden catch (e) {
      if (_disposed || gen != _gen) return;
      _poller.stop();
      error = e;
      phase = IdeAppPhase.error;
      _notify();
    } on Object {
      if (_disposed || gen != _gen) return;
      frameFailing = true; // giữ khung cũ, nhịp sau thử lại
      _notify();
    }
  }

  /// Mở màn hình app hoặc đổi thiết lập (việc nền); ghi ≤ 14 dòng cuối.
  Future<void> run({String? device, bool? dark}) async {
    if (running || !canRun() || _disposed) return;
    _gen++;
    running = true;
    runError = null;
    runMessage = null;
    log = const [];
    _notify();
    try {
      final job = await media.appRun(project, device: device, dark: dark);
      final out = await jobs.waitJob(
        job,
        poll: jobPoll,
        isCancelled: () => _disposed,
        onLog: (text) {
          if (_disposed) return;
          log = ideLastLines(text, ideAppLogLines);
          _notify();
        },
      );
      if (_disposed) return;
      final res = out.result;
      final msg = res is Map && res['message'] is String
          ? res['message'] as String
          : '';
      if (out.ok && !(res is Map && res['ok'] == false)) {
        runMessage = msg;
      } else {
        // Lời do IDE gửi: cắt ngắn để không chiếm cả màn.
        runError = _clip(
          msg.isNotEmpty
              ? msg
              : (log.isNotEmpty ? log.last : 'Không mở được màn hình app.'),
        );
      }
      try {
        _apply(await media.appStatus());
      } on Object {
        // giữ trạng thái cũ
      }
    } on IdeCancelled {
      // Chỉ do đóng màn; còn lại vẫn phải nhả cờ `running` ở dưới.
      if (_disposed) return;
    } on Object catch (e) {
      if (_disposed) return;
      runError = e is IdeException && e.message.isNotEmpty ? e.message : '$e';
      runErrorObject = e;
    }
    if (_disposed) return;
    running = false;
    _notify();
    if (_session != null) _startFrames();
  }

  Object? runErrorObject;

  Future<void> stop() async {
    if (stopping || _disposed) return;
    _gen++;
    stopping = true;
    runError = null;
    _notify();
    try {
      await media.appStop(project);
      if (_disposed) return;
      _gen++;
      _poller.stop();
      _session = null;
      frame = null;
      notOpen = true;
      building = false;
      try {
        _apply(await media.appStatus());
      } on Object {
        // đã dừng; trạng thái làm mới ở lần sau
      }
    } on Object catch (e) {
      if (_disposed) return;
      runErrorObject = e;
      runError = e is IdeException && e.message.isNotEmpty ? e.message : '$e';
    }
    if (_disposed) return;
    stopping = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _poller.dispose();
    super.dispose();
  }
}

/// [n] dòng cuối (bỏ dòng trống), mỗi dòng cắt ≤ 300 ký tự.
List<String> ideLastLines(String text, int n) {
  final lines = text
      .split(RegExp(r'\r?\n|\r'))
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .map((l) => l.length > 300 ? l.substring(0, 300) : l)
      .toList();
  return lines.length <= n ? lines : lines.sublist(lines.length - n);
}

/// Trần độ dài lời lỗi chạy app hiện trên màn (ký tự).
const ideAppRunErrorMax = 500;

String _clip(String s) =>
    s.length <= ideAppRunErrorMax ? s : '${s.substring(0, ideAppRunErrorMax)}…';
