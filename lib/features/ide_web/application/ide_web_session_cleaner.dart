import 'dart:async';

import '../domain/ide_web_owner.dart';
import '../domain/ide_web_ports.dart';
import 'ide_web_serial.dart';

/// Dọn VPSTTT IDE khi phiên chat kết thúc theo bất kỳ lối nào. Xoá hỏng thì cờ
/// `needsClear` còn đó: lần mở sau phải xoá xong mới được tạo WebView.
final class IdeWebSessionCleaner {
  IdeWebSessionCleaner({
    required IdeWebDataCleaner data,
    required IdeWebDataMarkerStore markers,
    this.timeout = const Duration(seconds: 5),
  }) : _data = data,
       _markers = markers;

  final IdeWebDataCleaner _data;
  final IdeWebDataMarkerStore _markers;
  final Duration timeout;
  final _serial = IdeWebSerial();
  final _open = <Future<void> Function()>{};

  /// Màn đang mở đăng ký cách tự đóng; trả hàm gỡ đăng ký.
  void Function() registerOpenView(Future<void> Function() close) {
    _open.add(close);
    return () => _open.remove(close);
  }

  /// Đóng màn đang mở rồi xoá dữ liệu WebView. Chưa từng mở IDE thì không chạm
  /// WebView. Không ném lỗi.
  Future<void> clearAll() async {
    try {
      // Đóng trước: trang còn sống sẽ ghi lại cookie sau khi xoá.
      for (final close in _open.toList()) {
        try {
          await close().timeout(timeout);
        } on Object {
          // Vẫn xoá dữ liệu.
        }
      }
      await _serial.run(_clear).timeout(timeout);
    } on Object {
      // Cờ needsClear đã ghi: lần mở sau xoá tiếp.
    }
  }

  /// Chuẩn bị tạo WebView cho [owner]; `false` = chưa dọn được dữ liệu người
  /// trước, không được mở.
  Future<bool> prepareFor(IdeWebOwner owner) async {
    try {
      await _serial
          .run(() async {
            final marker = await _markers.read();
            if (marker != null && !marker.isUsedBy(owner)) await _clear();
            await _markers.write(IdeWebDataMarker.usedBy(owner.digest));
          })
          .timeout(timeout);
      return true;
    } on Object {
      return false;
    }
  }

  /// [current] vừa đăng nhập: xoá dữ liệu người trước / lần xoá dở. Không ném lỗi.
  Future<void> dropOtherOwner(IdeWebOwner current) async {
    try {
      await _serial
          .run(() async {
            final marker = await _markers.read();
            if (marker != null && !marker.isUsedBy(current)) await _clear();
          })
          .timeout(timeout);
    } on Object {
      // Lần mở màn IDE sẽ xoá tiếp.
    }
  }

  Future<void> _clear() async {
    if (await _markers.read() == null) return;
    await _markers.write(const IdeWebDataMarker.needsClear());
    await _data.clearAll().timeout(timeout);
    await _markers.clear();
  }
}
