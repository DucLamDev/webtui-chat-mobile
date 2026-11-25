import 'package:record/record.dart';

import '../domain/ide_web_ports.dart';

/// Xin quyền micro của hệ điều hành (chuỗi quyền sẵn có của app).
final class RecordIdeWebMicPermission implements IdeWebMicPermission {
  const RecordIdeWebMicPermission();

  @override
  Future<bool> request() async {
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission();
    } on Object {
      return false;
    } finally {
      try {
        await recorder.dispose();
      } on Object {
        // Không giữ gì.
      }
    }
  }
}
