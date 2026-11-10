/// `metadata.voice` của tin thoại: thời lượng và sóng âm để vẽ bong bóng trước
/// khi tải tệp.
final class MessageVoiceMetadata {
  const MessageVoiceMetadata({
    required this.durationMs,
    this.waveform = const [],
  });

  /// Thời lượng (0 – 3.600.000 ms).
  final int durationMs;

  /// Tối đa 64 số nguyên 0–100; rỗng = không có sóng âm.
  final List<int> waveform;

  Duration get duration => Duration(milliseconds: durationMs);

  static MessageVoiceMetadata? fromMetadata(Map<String, Object?> metadata) {
    final raw = metadata['voice'];
    if (raw is! Map) return null;
    final duration = raw['duration_ms'];
    if (duration is! num || !duration.isFinite) return null;
    final durationMs = duration.round();
    if (durationMs < 0 || durationMs > maxVoiceDurationMs) return null;
    final rawWaveform = raw['waveform'];
    return MessageVoiceMetadata(
      durationMs: durationMs,
      waveform: rawWaveform is List
          ? List.unmodifiable([
              for (final value in rawWaveform.take(maxVoiceWaveformBars))
                if (value is num && value.isFinite)
                  value.round().clamp(0, 100).toInt(),
            ])
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'duration_ms': durationMs.clamp(0, maxVoiceDurationMs).toInt(),
    if (waveform.isNotEmpty)
      'waveform': [
        for (final value in waveform.take(maxVoiceWaveformBars))
          value.clamp(0, 100).toInt(),
      ],
  };
}

const int maxVoiceDurationMs = 3600000;
const int maxVoiceWaveformBars = 64;

/// Gom các mẫu mức âm (dBFS, thường -160..0) lấy trong lúc ghi thành tối đa
/// [maxBars] cột 0–100 (mỗi cột lấy mức to nhất của nhóm mẫu). Không có mẫu
/// hợp lệ thì trả rỗng (khi đó chỉ gửi `duration_ms`).
List<int> voiceWaveformFromLevels(
  List<double> levelsDbfs, {
  int maxBars = maxVoiceWaveformBars,
  double floorDbfs = -60,
}) {
  final levels = [
    for (final level in levelsDbfs)
      if (level.isFinite) level,
  ];
  if (levels.isEmpty || maxBars <= 0) return const [];
  final bars = levels.length < maxBars ? levels.length : maxBars;
  final result = <int>[];
  for (var bar = 0; bar < bars; bar++) {
    final start = (bar * levels.length) ~/ bars;
    var end = ((bar + 1) * levels.length) ~/ bars;
    if (end <= start) end = start + 1;
    var peak = levels[start];
    for (var index = start + 1; index < end; index++) {
      if (levels[index] > peak) peak = levels[index];
    }
    final normalized = (peak - floorDbfs) / -floorDbfs;
    result.add((normalized.clamp(0.0, 1.0) * 100).round());
  }
  return List.unmodifiable(result);
}
