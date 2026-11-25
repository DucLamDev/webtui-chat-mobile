import '../domain/ide_web_device_key.dart';

/// Điều app hỏi người dùng thay mặt trang IDE (hộp của app, trang không vẽ được).
sealed class IdeWebPrompt {
  const IdeWebPrompt();
}

final class IdeWebCreateKeyPrompt extends IdeWebPrompt {
  const IdeWebCreateKeyPrompt(this.purpose);

  final IdeWebKeyPurpose purpose;
}

final class IdeWebDeleteKeyPrompt extends IdeWebPrompt {
  const IdeWebDeleteKeyPrompt();
}

final class IdeWebSaveFilePrompt extends IdeWebPrompt {
  const IdeWebSaveFilePrompt({required this.name, required this.bytes});

  final String name;
  final int bytes;
}

final class IdeWebOpenSavedFilePrompt extends IdeWebPrompt {
  const IdeWebOpenSavedFilePrompt(this.name);

  final String name;
}

final class IdeWebMicrophonePrompt extends IdeWebPrompt {
  const IdeWebMicrophonePrompt();
}

final class IdeWebExternalLinkPrompt extends IdeWebPrompt {
  const IdeWebExternalLinkPrompt(this.uri);

  final Uri uri;
}

abstract interface class IdeWebPrompter {
  Future<bool> confirm(IdeWebPrompt prompt);

  /// Đóng hộp đang hỏi (trang đã chuyển, màn bị che / đóng): coi như không đồng ý.
  void dismiss();

  /// Đóng màn IDE.
  void close();
}
