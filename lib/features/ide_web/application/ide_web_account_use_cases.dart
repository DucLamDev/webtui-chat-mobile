import 'ide_web_device_keys.dart';
import 'ide_web_session_cleaner.dart';
import 'ide_web_use_cases.dart';

/// Vừa có người đăng nhập: khoá thiết bị và dữ liệu WebView của người khác bị
/// xoá hẳn, không đợi tới lúc mở IDE. Cùng người thì giữ nguyên.
final class DropOtherIdeWebOwnerUseCase {
  const DropOtherIdeWebOwnerUseCase({
    required IdeWebSessionReader sessions,
    required IdeWebDeviceKeys keys,
    required IdeWebSessionCleaner cleaner,
  }) : _sessions = sessions,
       _keys = keys,
       _cleaner = cleaner;

  final IdeWebSessionReader _sessions;
  final IdeWebDeviceKeys _keys;
  final IdeWebSessionCleaner _cleaner;

  Future<void> execute() async {
    final session = await _sessions.capture();
    if (session == null) return;
    try {
      await _keys.dropOtherOwner(session.owner);
    } on Object {
      // Bản ghi còn đó: lần sau xoá tiếp.
    }
    await _cleaner.dropOtherOwner(session.owner);
  }
}
