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

/// Âm báo phát một lần của cuộc gọi (phát tiếp cả khi màn gọi đã đóng).
enum CallCue {
  /// Tiếng kết thúc cuộc gọi: gác máy, bị từ chối, bên kia gác / huỷ.
  ended('sounds/ket-thuc-cuoc-goi.mp3'),

  /// Lời báo không liên lạc được người nhận: gọi đi hết giờ đổ chuông mà
  /// không máy nào bắt (người nhận mất mạng, tắt máy, không nghe). Tệp gốc
  /// tên "khi người nhận ở nơi không có wifi", đổi tên để chuỗi trong mã không
  /// có chữ tiếng Việt thiếu dấu (luật test chữ).
  unreachable('sounds/khi-nguoi-nhan-o-noi-mat-wifi.mp3');

  const CallCue(this.asset);

  /// Đường dẫn trong `assets/` (khai trong pubspec.yaml).
  final String asset;
}

/// Chuông của cuộc gọi trong app: chuông chờ khi gọi đi (đến lúc bên kia nhận)
/// và nhạc chuông khi có cuộc gọi đến lúc app đang mở; âm báo một lần khi
/// cuộc gọi kết thúc ([playCue]). Lỗi phát âm thanh không được làm hỏng cuộc
/// gọi nên mọi lỗi đều bị bỏ qua.
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


  /// Tiếng chờ phía người gọi trong lúc máy bên kia đổ chuông (lặp).
  static const ringbackAsset = 'sounds/nguoi-goi-cho-nguoi-khac-nghe.mp3';

  /// Nhạc chuông khi có cuộc gọi đến lúc app đang mở (lặp).
  static const ringtoneAsset = 'sounds/nhac-chuong-khi-co-cuoc-goi-den.mp3';

  /// Chuông chờ phía người gọi.
  factory CallTonePlayer.ringback() {
    return CallTonePlayer._(ringbackAsset, _ringbackContext);
  }

  /// Nhạc chuông khi có cuộc gọi đến lúc app đang mở.
  factory CallTonePlayer.ringtone() {
    return CallTonePlayer._(ringtoneAsset, _ringtoneContext);
  }

  /// Phát [cue] một lần rồi tự giải phóng (không phụ thuộc màn gọi còn mở).
  static Future<void> playCue(CallCue cue) async {
    final level = volume.clamp(0.0, 1.0);
    // Âm lượng 0 (Cài đặt): không phát cả âm báo.
    if (level <= 0) return;
    final player = createPlayer();
    var released = false;
    void release() {
      if (released) return;
      released = true;
      unawaited(player.dispose().catchError((Object _) {}));
    }

    // Phòng khi không nhận được sự kiện phát xong: lời báo dài nhất ~8 giây.
    final guard = Timer(const Duration(seconds: 15), release);
    try {
      await player.setAudioContext(_ringbackContext);
      await player.setReleaseMode(ReleaseMode.release);
      unawaited(
        player.onPlayerComplete.first.then((_) {
          guard.cancel();
          release();
        }),
      );
      await player.play(AssetSource(cue.asset), volume: level);
    } on Object {
      // Không phát được âm báo thì bỏ qua.
      guard.cancel();
      release();
    }
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
      await player.play(AssetSource(ringtoneAsset), volume: clamped);
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
