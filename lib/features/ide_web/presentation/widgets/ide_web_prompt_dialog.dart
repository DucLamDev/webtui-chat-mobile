import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_web_prompter.dart';
import '../../domain/ide_web_device_key.dart';

/// Hộp xác nhận của app cho yêu cầu từ trang IDE.
class IdeWebPromptDialog extends StatelessWidget {
  const IdeWebPromptDialog({required this.prompt, super.key});

  final IdeWebPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final text = ideWebPromptText(prompt);
    final destructive = prompt is IdeWebDeleteKeyPrompt;
    return WebTuiDialog(
      title: text.title,
      message: text.message,
      icon: text.icon,
      tone: destructive ? WebTuiDialogTone.danger : WebTuiDialogTone.normal,
      actions: [
        WebTuiDialogAction(
          key: const Key('ide_web_prompt_cancel'),
          label: tr('Huỷ', 'Cancel'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        WebTuiDialogAction(
          key: const Key('ide_web_prompt_ok'),
          label: text.confirm,
          primary: true,
          destructive: destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

({String title, String message, String confirm, IconData icon})
ideWebPromptText(IdeWebPrompt prompt) => switch (prompt) {
  IdeWebCreateKeyPrompt(:final purpose) => (
    title: tr(
      'Đăng ký thiết bị này với VPSTTT IDE?',
      'Register this device with VPSTTT IDE?',
    ),
    message: purpose == IdeWebKeyPurpose.biometric
        ? tr(
            'Máy tạo một khoá an toàn, mỗi lần dùng phải xác nhận bằng vân tay hoặc khuôn mặt.',
            'Your phone creates a secure key that needs your fingerprint or face each time.',
          )
        : tr(
            'Máy tạo một khoá an toàn để VPSTTT IDE nhận ra thiết bị này.',
            'Your phone creates a secure key so VPSTTT IDE can recognize this device.',
          ),
    confirm: tr('Đăng ký', 'Register'),
    icon: Icons.key_rounded,
  ),
  IdeWebDeleteKeyPrompt() => (
    title: tr('Xoá khoá thiết bị?', 'Delete the device key?'),
    message: tr(
      'Thiết bị này sẽ phải đăng ký lại với VPSTTT IDE.',
      'This device will have to register with VPSTTT IDE again.',
    ),
    confirm: tr('Xoá', 'Delete'),
    icon: Icons.key_off_rounded,
  ),
  IdeWebSaveFilePrompt(:final name, :final bytes) => (
    title: tr('Lưu tệp về máy?', 'Save this file?'),
    message: '$name\n${_size(bytes)}',
    confirm: tr('Lưu', 'Save'),
    icon: Icons.download_rounded,
  ),
  IdeWebOpenSavedFilePrompt(:final name) => (
    title: tr('Mở bằng ứng dụng khác?', 'Open in another app?'),
    message: name,
    confirm: tr('Mở', 'Open'),
    icon: Icons.open_in_new_rounded,
  ),
  IdeWebMicrophonePrompt() => (
    title: tr(
      'VPSTTT IDE muốn dùng micro',
      'VPSTTT IDE wants to use the microphone',
    ),
    message: tr(
      'Giọng nói được gửi tới VPSTTT IDE. Micro tự tắt khi bạn rời màn này.',
      'Your voice is sent to VPSTTT IDE. The microphone stops when you leave this screen.',
    ),
    confirm: tr('Cho phép', 'Allow'),
    icon: Icons.mic_rounded,
  ),
  IdeWebExternalLinkPrompt(:final uri) => (
    title: tr('Mở liên kết ngoài ứng dụng?', 'Open this link outside the app?'),
    message: uri.host,
    confirm: tr('Mở', 'Open'),
    icon: Icons.open_in_new_rounded,
  ),
};

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
