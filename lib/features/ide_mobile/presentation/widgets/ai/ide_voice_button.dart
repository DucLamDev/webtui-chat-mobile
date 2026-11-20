import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';

/// Nút micro: đọc giọng nói tiếng Việt, chuyển thành chữ gửi về [onText]
/// (khi người dùng nói xong, một lần). Máy không hỗ trợ / từ chối quyền thì chỉ
/// báo nhẹ, không làm hỏng ô nhập.
class IdeVoiceButton extends StatefulWidget {
  const IdeVoiceButton({required this.onText, this.speech, super.key});

  final ValueChanged<String> onText;

  /// Để test thay bản giả.
  final SpeechToText? speech;

  @override
  State<IdeVoiceButton> createState() => _IdeVoiceButtonState();
}

class _IdeVoiceButtonState extends State<IdeVoiceButton> {
  late final SpeechToText _speech = widget.speech ?? SpeechToText();
  bool _listening = false;
  bool _ready = false;
  bool _unsupported = false;

  @override
  void dispose() {
    if (_listening) unawaited(_speech.cancel());
    super.dispose();
  }

  void _warn(String vi, String en) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(tr(vi, en))));
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_ready) {
      bool ok;
      try {
        ok = await _speech.initialize(
          onStatus: (s) {
            if (!mounted) return;
            if (s == 'done' || s == 'notListening') {
              setState(() => _listening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      } on Object {
        ok = false;
      }
      if (!mounted) return;
      if (!ok) {
        setState(() => _unsupported = true);
        _warn(
          'Không dùng được giọng nói: hãy cấp quyền micro / nhận dạng giọng nói trong Cài đặt máy.',
          'Voice input unavailable: allow microphone / speech recognition in Settings.',
        );
        return;
      }
      _ready = true;
    }
    setState(() => _listening = true);
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'vi_VN',
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          partialResults: false,
          cancelOnError: true,
        ),
        onResult: (r) {
          final text = r.recognizedWords.trim();
          if (r.finalResult && text.isNotEmpty) widget.onText(text);
        },
      );
    } on Object {
      if (mounted) {
        setState(() => _listening = false);
        _warn('Chưa nghe được, thử lại.', 'Could not listen, try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening
          ? tr('Dừng nghe', 'Stop listening')
          : tr('Nói để nhập', 'Speak to type'),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: _toggle,
      icon: Icon(
        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _listening
            ? IdeWb.danger
            : _unsupported
            ? IdeWb.text2
            : IdeWb.text,
      ),
    );
  }
}
