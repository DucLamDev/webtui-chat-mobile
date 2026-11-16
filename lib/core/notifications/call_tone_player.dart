import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Chuông chờ dùng audio session `playAndRecord` như WebRTC để không làm mất
/// micro / loa của cuộc gọi.
final _ringbackContext = AudioContext(
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playAndRecord,
    options: const {
      AVAudioSessionOptions.allowBluetooth,
      AVAudioSessionOptions.mixWithOthers,
    },
  ),
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.voiceCommunicationSignalling,
    audioFocus: AndroidAudioFocus.none,
  ),
);

/// Nhạc chuông cuộc gọi đến dùng `playback` để vẫn kêu khi máy gạt công tắc
/// im lặng.
final _ringtoneContext = AudioContext(
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: const {AVAudioSessionOptions.mixWithOthers},
  ),
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.notificationRingtone,
    audioFocus: AndroidAudioFocus.gainTransient,
  ),
);

/// Chuông của cuộc gọi trong app: chuông chờ khi gọi đi (đến lúc bên kia nhận)
/// và nhạc chuông khi có cuộc gọi đến lúc app đang mở. Lỗi phát âm thanh không
/// được làm hỏng cuộc gọi nên mọi lỗi đều bị bỏ qua.
final class CallTonePlayer {
  CallTonePlayer._(this._asset, this._context);

  /// Âm lượng chuông trước khi người dùng chỉnh.
  static const defaultVolume = 0.8;

  /// Âm lượng chuông hiện tại (Cài đặt > Âm lượng, 0..1). App gán mỗi khi cài
  /// đặt đổi; 0 = không phát chuông (màn cuộc gọi, rung vẫn như cũ).
  static double volume = defaultVolume;

  /// Thời lượng phát thử khi thả tay khỏi thanh Âm lượng.
  static const previewDuration = Duration(milliseconds: 1500);

  /// Tạo trình phát (test thay bằng bản giả).
  @visibleForTesting
  static AudioPlayer Function() createPlayer = AudioPlayer.new;

  static AudioPlayer? _previewPlayer;
  static Timer? _previewTimer;

  /// Chuông chờ phía người gọi (425 Hz, 1 giây kêu / 4 giây nghỉ).
  factory CallTonePlayer.ringback() {
    return CallTonePlayer._('sounds/ringback.wav', _ringbackContext);
  }

  /// Nhạc chuông khi có cuộc gọi đến lúc app đang mở.
  factory CallTonePlayer.ringtone() {
    return CallTonePlayer._('sounds/ringtone.wav', _ringtoneContext);
  }

  final String _asset;
  final AudioContext _context;
  AudioPlayer? _player;
  bool _stopped = false;

  /// Bắt đầu phát lặp. Gọi nhiều lần không phát chồng.
  Future<void> start() async {
    if (_player != null || _stopped) return;
    final level = volume.clamp(0.0, 1.0);
    // Người dùng kéo Âm lượng về 0: không phát chuông.
    if (level <= 0) return;
    final player = createPlayer();
    _player = player;
    try {
      await player.setAudioContext(_context);
      await player.setReleaseMode(ReleaseMode.loop);
      if (_stopped) return;
      await player.play(AssetSource(_asset), volume: level);
    } on Object {
      // Không phát được chuông thì cuộc gọi vẫn tiếp tục.
    }
  }

  /// Phát thử nhạc chuông khoảng [previewDuration] ở [level] (thả tay khỏi
  /// thanh Âm lượng) để nghe mức vừa chọn. Lần phát mới dừng lần trước; 0 thì
  /// chỉ dừng. Lỗi phát bị bỏ qua.
  static Future<void> preview(double level) async {
    _previewTimer?.cancel();
    _previewTimer = null;
    final previous = _previewPlayer;
    _previewPlayer = null;
    if (previous != null) unawaited(_release(previous));
    final clamped = level.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final player = createPlayer();
    _previewPlayer = player;
    _previewTimer = Timer(previewDuration, () {
      if (!identical(_previewPlayer, player)) return;
      _previewPlayer = null;
      _previewTimer = null;
      unawaited(_release(player));
    });
    try {
      await player.setAudioContext(_ringtoneContext);
      await player.setReleaseMode(ReleaseMode.stop);
      if (!identical(_previewPlayer, player)) return;
      await player.play(AssetSource('sounds/ringtone.wav'), volume: clamped);
    } on Object {
      // Không phát thử được thì bỏ qua.
    }
  }

  static Future<void> _release(AudioPlayer player) async {
    try {
      await player.stop();
    } on Object {
      // Bỏ qua: chỉ là âm báo.
    } finally {
      unawaited(player.dispose());
    }
  }

  /// Dừng hẳn và giải phóng (sau khi dừng không phát lại được).
  Future<void> stop() async {
    _stopped = true;
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } on Object {
      // Bỏ qua: chỉ là âm báo.
    } finally {
      unawaited(player.dispose());
    }
  }
}
