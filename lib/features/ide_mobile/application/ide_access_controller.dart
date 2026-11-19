import 'dart:async';

import '../domain/ide_device_security.dart';

/// Hỏi vân tay / khoá màn hình khi vào mục IDE, nhớ tới khi app ở nền quá
/// [grace] (5 phút).
///
/// Thời gian nền đo bằng đồng hồ native tính cả lúc máy ngủ và người dùng
/// không chỉnh được ([IdeDeviceSecurity.uptimeMs]); giờ hệ thống chỉ dùng thêm
/// (lùi giờ thì cũng khoá). Không đọc được đồng hồ thì coi như quá hạn.
final class IdeAccessController {
  IdeAccessController(
    this._security, {
    DateTime Function()? now,
    this.grace = const Duration(minutes: 5),
    this.authTimeout = const Duration(minutes: 3),
  }) : _now = now ?? DateTime.now;

  final IdeDeviceSecurity _security;
  final DateTime Function() _now;
  final Duration grace;

  /// Hộp xác thực không trả lời sau thời gian này (Activity bị huỷ...) thì
  /// coi như lỗi, lần sau hỏi lại.
  final Duration authTimeout;

  bool _unlocked = false;
  DateTime? _backgroundWall;
  Future<int?>? _backgroundUptime;
  Future<bool>? _resuming;
  Future<DeviceOwnerAuthResult>? _asking;
  int _generation = 0;

  /// Đã mở và không đang kiểm thời gian nền.
  bool get unlocked => _unlocked && _resuming == null;

  void onBackground() {
    if (_backgroundWall != null) return;
    _backgroundWall = _now();
    _backgroundUptime = _readUptime();
  }

  /// Gọi khi app quay lại (gọi nhiều lần cũng được). Trả `true` nếu vẫn còn
  /// mở; trong lúc kiểm [unlocked] là `false`.
  Future<bool> onForeground() {
    final pending = _resuming;
    if (pending != null) return pending;
    final wall = _backgroundWall;
    final uptime = _backgroundUptime;
    _backgroundWall = null;
    _backgroundUptime = null;
    if (wall == null || uptime == null) return Future.value(unlocked);
    if (!_unlocked) return Future.value(false);
    final generation = _generation;
    final check = _stillWithinGrace(wall, uptime).then((ok) {
      if (generation == _generation && !ok) _unlocked = false;
      _resuming = null;
      return unlocked;
    });
    _resuming = check;
    return check;
  }

  Future<bool> _stillWithinGrace(DateTime wall, Future<int?> uptime) async {
    final wallGap = _now().difference(wall);
    if (wallGap.isNegative || wallGap >= grace) return false;
    final before = await uptime;
    final after = await _readUptime();
    if (before == null || after == null) return false;
    final gap = after - before;
    return gap >= 0 && gap < grace.inMilliseconds;
  }

  Future<int?> _readUptime() async {
    try {
      return await _security.uptimeMs();
    } catch (_) {
      return null;
    }
  }

  /// Khoá lại ngay (đăng xuất, gỡ gắn).
  void lock() {
    _generation++;
    _unlocked = false;
  }

  /// `ok` nếu đã mở (còn nhớ hoặc vừa xác thực). Gọi cùng lúc nhiều nơi thì
  /// chỉ hiện một hộp.
  Future<DeviceOwnerAuthResult> ensureUnlocked(String reason) {
    if (unlocked) return Future.value(DeviceOwnerAuthResult.ok);
    final resuming = _resuming;
    if (resuming != null) {
      return resuming.then(
        (ok) => ok ? DeviceOwnerAuthResult.ok : ensureUnlocked(reason),
      );
    }
    final asking = _asking;
    if (asking != null) return asking;
    final generation = _generation;
    final future = _security
        .authenticateDeviceOwner(reason)
        .timeout(authTimeout)
        .then<DeviceOwnerAuthResult>(
          (value) => value,
          onError: (Object _) => DeviceOwnerAuthResult.unavailable,
        )
        .then((value) {
          _asking = null;
          if (value == DeviceOwnerAuthResult.ok) {
            if (generation != _generation) {
              return DeviceOwnerAuthResult.cancelled;
            }
            _unlocked = true;
            _backgroundWall = null;
            _backgroundUptime = null;
          }
          return value;
        });
    _asking = future;
    return future;
  }
}
