import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

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
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setAudioContext(_context);
      await player.setReleaseMode(ReleaseMode.loop);
      if (_stopped) return;
      await player.play(AssetSource(_asset), volume: 0.8);
    } on Object {
      // Không phát được chuông thì cuộc gọi vẫn tiếp tục.
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
