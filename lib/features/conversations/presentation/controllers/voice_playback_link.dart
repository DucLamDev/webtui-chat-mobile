import 'package:flutter/foundation.dart';

import '../../domain/entities/rich_message.dart';

/// Nối trình phát của một tin thoại với phần "Xem lời" của cùng tin: trình phát
/// báo vị trí đang phát, phần lời tô đoạn đang nghe và nhờ trình phát tua tới
/// đầu một đoạn.
final class VoicePlaybackLink extends ChangeNotifier {
  int _positionMs = 0;
  Future<void> Function(int milliseconds)? _seekAndPlay;

  /// Vị trí đang phát (mili giây); 0 khi chưa phát hoặc đã hết bài.
  int get positionMs => _positionMs;

  /// Có trình phát đang gắn để tua được không.
  bool get canSeek => _seekAndPlay != null;

  void reportPosition(int milliseconds) {
    final next = milliseconds < 0 ? 0 : milliseconds;
    if (next == _positionMs) return;
    _positionMs = next;
    notifyListeners();
  }

  void attach(Future<void> Function(int milliseconds) seekAndPlay) {
    _seekAndPlay = seekAndPlay;
    notifyListeners();
  }

  /// Chỉ gỡ khi đúng hàm đang gắn (trình phát cũ gỡ muộn không làm mất trình
  /// phát mới).
  void detach(Future<void> Function(int milliseconds) seekAndPlay) {
    // So bằng `==`: hai lần lấy cùng một phương thức của cùng đối tượng bằng nhau
    // nhưng không chắc là cùng một đối tượng hàm.
    if (_seekAndPlay != seekAndPlay) return;
    _seekAndPlay = null;
    _positionMs = 0;
    notifyListeners();
  }

  Future<void> seekAndPlay(int milliseconds) async {
    final seek = _seekAndPlay;
    if (seek == null) return;
    await seek(milliseconds < 0 ? 0 : milliseconds);
  }
}

/// Đoạn lời đang nghe ở vị trí [positionMs]: đoạn bắt đầu muộn nhất mà không
/// sau vị trí đang phát. Khoảng lặng giữa hai đoạn vẫn giữ đoạn trước (đỡ
/// nháy). Trước đoạn đầu, sau khi đoạn cuối đã hết, danh sách rỗng hay vị trí
/// âm thì trả -1. Không cần danh sách đã sắp xếp.
int activeTranscriptSegmentIndex(
  List<FileTranscriptSegment> segments,
  int positionMs,
) {
  if (segments.isEmpty || positionMs < 0) return -1;
  var active = -1;
  var activeStart = -1;
  var lastEnd = -1;
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    if (segment.startMs < 0) continue;
    final end = segment.endMs > segment.startMs
        ? segment.endMs
        : segment.startMs;
    if (end > lastEnd) lastEnd = end;
    if (segment.startMs <= positionMs && segment.startMs >= activeStart) {
      active = index;
      activeStart = segment.startMs;
    }
  }
  return positionMs < lastEnd ? active : -1;
}

/// "1:05" từ mili giây.
String formatTranscriptTime(int milliseconds) {
  final seconds = milliseconds <= 0 ? 0 : milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
