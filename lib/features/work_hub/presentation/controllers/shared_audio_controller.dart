import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/playable_audio.dart';
import '../../domain/entities/work_hub.dart';
import 'shared_file_logic.dart';

/// Bộ phát tiếng, tách khỏi plugin để test bằng bản giả.
abstract interface class SharedAudioEngine {
  Stream<Duration> get onPosition;
  Stream<Duration> get onDuration;
  Stream<void> get onComplete;

  Future<void> playUrl(Uri uri);
  Future<void> playFile(File file);
  Future<void> stop();
  Future<void> dispose();
}

final class AudioplayersSharedAudioEngine implements SharedAudioEngine {
  AudioplayersSharedAudioEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get onPosition => _player.onPositionChanged;

  @override
  Stream<Duration> get onDuration => _player.onDurationChanged;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> playUrl(Uri uri) => _player.play(UrlSource(uri.toString()));

  @override
  Future<void> playFile(File file) => _player.play(DeviceFileSource(file.path));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

final sharedAudioEngineFactoryProvider = Provider<SharedAudioEngine Function()>(
  (ref) => AudioplayersSharedAudioEngine.new,
);

/// Phát ghi âm ngay tại dòng; chỉ một tệp phát cùng lúc.
final class SharedAudioController extends ChangeNotifier {
  SharedAudioController({
    required SharedAudioEngine Function() engineFactory,
    required SharedFileMediaResolver Function() resolver,
    bool Function(SharedFile file)? needsTranscode,
    Future<File> Function(File local, SharedFile file)? transcode,
  }) : _engineFactory = engineFactory,
       _resolver = resolver,
       _needsTranscode =
           needsTranscode ??
           ((file) =>
               audioNeedsTranscode(name: file.name, mimeType: file.mimeType)),
       _transcode =
           transcode ??
           ((local, file) =>
               playableAudioFile(source: local, cacheKey: file.id));

  final bool Function(SharedFile file) _needsTranscode;
  final Future<File> Function(File local, SharedFile file) _transcode;

  final SharedAudioEngine Function() _engineFactory;
  final SharedFileMediaResolver Function() _resolver;
  SharedAudioEngine? _engine;
  final _subs = <StreamSubscription<Object?>>[];
  int _generation = 0;
  bool _disposed = false;

  String? activeId;
  bool loading = false;
  bool failed = false;

  /// Lỗi do không giải mã được WebM / Ogg: màn hình lùi về "Mở bằng ứng dụng
  /// khác".
  bool decodeFailed = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool isActive(String id) => activeId == id;

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  SharedAudioEngine _ensureEngine() {
    final existing = _engine;
    if (existing != null) return existing;
    final engine = _engineFactory();
    _subs
      ..add(
        engine.onPosition.listen((value) {
          position = value;
          _notify();
        }),
      )
      ..add(
        engine.onDuration.listen((value) {
          duration = value;
          _notify();
        }),
      )
      ..add(
        engine.onComplete.listen((_) {
          activeId = null;
          position = Duration.zero;
          _notify();
        }),
      );
    return _engine = engine;
  }

  /// Bấm dòng: đang phát tệp này thì dừng, ngược lại phát tệp này ngay.
  Future<void> toggle(SharedFile file) async {
    if (activeId == file.id) {
      await stop();
      return;
    }
    final generation = ++_generation;
    final engine = _ensureEngine();
    await engine.stop();
    activeId = file.id;
    loading = true;
    failed = false;
    decodeFailed = false;
    position = Duration.zero;
    duration = Duration.zero;
    _notify();
    try {
      final resolver = _resolver();
      if (_needsTranscode(file)) {
        // AVPlayer không đọc được WebM / Ogg: tải về, giải mã ra WAV rồi phát.
        final local = await resolver.localFile(file);
        if (generation != _generation) return;
        File playable;
        try {
          playable = await _transcode(local, file);
        } on Object {
          decodeFailed = true;
          rethrow;
        }
        if (generation != _generation) return;
        await engine.playFile(playable);
        if (generation != _generation) return;
        loading = false;
        _notify();
        return;
      }
      final stream = await resolver.streamUri(file);
      if (generation != _generation) return;
      var started = false;
      if (stream != null) {
        try {
          await engine.playUrl(stream);
          started = true;
        } on Object {
          started = false;
        }
      }
      if (generation != _generation) return;
      if (!started) {
        final local = await resolver.localFile(file);
        if (generation != _generation) return;
        await engine.playFile(local);
      }
      if (generation != _generation) return;
      loading = false;
    } on Object {
      if (generation != _generation) return;
      loading = false;
      failed = true;
      activeId = null;
    }
    _notify();
  }

  Future<void> stop() async {
    _generation++;
    activeId = null;
    loading = false;
    position = Duration.zero;
    _notify();
    await _engine?.stop();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
    super.dispose();
  }
}
