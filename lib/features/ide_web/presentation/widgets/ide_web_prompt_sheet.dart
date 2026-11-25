import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_web_prompter.dart';
import '../../domain/ide_web_device_key.dart';
import '../../domain/ide_web_file.dart';
import 'ide_web_buttons.dart';
import 'ide_web_code_window.dart';

/// Bảng trượt hỏi người dùng thay mặt trang IDE. Trả route để màn đóng được ngay
/// khi trang đổi / app bị khoá.
ModalBottomSheetRoute<bool> ideWebPromptRoute({
  required BuildContext context,
  required IdeWebPrompt prompt,
  required String host,
  required VoidCallback onVisibilityChanged,
}) => ModalBottomSheetRoute<bool>(
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: WebTuiColors.of(context).surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  sheetAnimationStyle: AnimationStyle(
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 180),
  ),
  builder: (_) => _RouteWatcher(
    onChanged: onVisibilityChanged,
    child: IdeWebPromptSheet(prompt: prompt, host: host),
  ),
);

class IdeWebPromptSheet extends StatelessWidget {
  const IdeWebPromptSheet({
    required this.prompt,
    required this.host,
    super.key,
  });

  final IdeWebPrompt prompt;

  /// Trang nào đang hỏi.
  final String host;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    final view = _view(prompt);
    void answer(bool value) => Navigator.of(context).pop(value);
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Asker(host: host),
                      const SizedBox(height: 20),
                      Semantics(
                        header: true,
                        child: Text(
                          view.title,
                          style: WebTuiTypography.titleLarge.copyWith(
                            fontSize: 22,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (view.subject case final subject?) ...[
                        _SubjectCard(subject),
                        const SizedBox(height: 16),
                      ],
                      for (final fact in view.facts) _FactRow(fact),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IdeWebButton.primary(
                      IdeWebAction(
                        key: const Key('ide_web_prompt_ok'),
                        label: view.confirm,
                        destructive: view.destructive,
                        onPressed: () => answer(true),
                      ),
                    ),
                    const SizedBox(height: 6),
                    IdeWebButton.secondary(
                      IdeWebAction(
                        key: const Key('ide_web_prompt_cancel'),
                        label: view.decline,
                        onPressed: () => answer(false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ai đang hỏi: dấu hiệu VPSTTT IDE và đúng địa chỉ trang.
class _Asker extends StatelessWidget {
  const _Asker({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Row(
      children: [
        const IdeWebMark(size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VPSTTT IDE',
                style: WebTuiTypography.bodyMedium.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              IdeWebHostLabel(host: host),
            ],
          ),
        ),
      ],
    );
  }
}

/// Địa chỉ trang kèm ổ khoá.
class IdeWebHostLabel extends StatelessWidget {
  const IdeWebHostLabel({required this.host, super.key});

  final String host;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded, size: 12, color: c.accentGreen),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.bodySmall.copyWith(
              fontSize: 12.5,
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

typedef _Fact = ({IconData icon, String text});

class _FactRow extends StatelessWidget {
  const _FactRow(this.fact);

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(fact.icon, size: 22, color: c.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              fact.text,
              style: WebTuiTypography.bodyMedium.copyWith(
                fontSize: 15.5,
                height: 1.42,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Subject = ({String badge, Color color, String name, String detail});

/// Thứ đang được hỏi: tệp (kèm loại) hoặc địa chỉ ngoài.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard(this.subject);

  final _Subject subject;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.backgroundMuted,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: subject.color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: subject.badge.isEmpty
                ? const Icon(Icons.public_rounded, color: Colors.white)
                : Text(
                    subject.badge,
                    textScaler: TextScaler.noScaling,
                    style: WebTuiTypography.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                if (subject.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subject.detail,
                    style: WebTuiTypography.bodySmall.copyWith(
                      fontSize: 13.5,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _PromptView = ({
  String title,
  _Subject? subject,
  List<_Fact> facts,
  String confirm,
  String decline,
  bool destructive,
});

_PromptView _view(IdeWebPrompt prompt) {
  final later = tr('Để sau', 'Not now');
  final cancel = tr('Huỷ', 'Cancel');
  return switch (prompt) {
    IdeWebCreateKeyPrompt(:final purpose) => (
      title: tr(
        'Đăng ký điện thoại này với VPSTTT IDE?',
        'Register this phone with VPSTTT IDE?',
      ),
      subject: null,
      facts: [
        (
          icon: Icons.memory_rounded,
          text: tr(
            'Máy tạo một khoá nằm trong chip bảo mật, không ai lấy ra được.',
            'Your phone creates a key inside its security chip. It cannot be taken out.',
          ),
        ),
        if (purpose == IdeWebKeyPurpose.biometric)
          (
            icon: Icons.fingerprint_rounded,
            text: tr(
              'Mỗi lần dùng khoá phải xác nhận bằng vân tay hoặc khuôn mặt.',
              'Each use needs your fingerprint or face.',
            ),
          )
        else
          (
            icon: Icons.verified_user_rounded,
            text: tr(
              'Lần sau VPSTTT IDE nhận ra điện thoại này.',
              'VPSTTT IDE will recognize this phone next time.',
            ),
          ),
        (
          icon: Icons.person_off_rounded,
          text: tr(
            'Khoá tự xoá khi người khác đăng nhập trên máy này.',
            'The key is erased when someone else signs in on this phone.',
          ),
        ),
      ],
      confirm: tr('Đăng ký điện thoại', 'Register phone'),
      decline: later,
      destructive: false,
    ),
    IdeWebDeleteKeyPrompt() => (
      title: tr('Xoá khoá của điện thoại này?', 'Delete this phone’s key?'),
      subject: null,
      facts: [
        (
          icon: Icons.link_off_rounded,
          text: tr(
            'VPSTTT IDE không còn nhận ra điện thoại này.',
            'VPSTTT IDE will no longer recognize this phone.',
          ),
        ),
        (
          icon: Icons.replay_rounded,
          text: tr(
            'Muốn dùng lại thì phải đăng ký từ đầu.',
            'You will have to register again to use it.',
          ),
        ),
      ],
      confirm: tr('Xoá khoá', 'Delete key'),
      decline: cancel,
      destructive: true,
    ),
    IdeWebSaveFilePrompt(:final name, :final bytes) => (
      title: tr('Lưu tệp về điện thoại?', 'Save this file to your phone?'),
      subject: _file(name, _size(bytes)),
      facts: const [],
      confirm: tr('Lưu tệp', 'Save file'),
      decline: cancel,
      destructive: false,
    ),
    IdeWebOpenSavedFilePrompt(:final name) => (
      title: tr('Mở bằng ứng dụng khác?', 'Open in another app?'),
      subject: _file(name, ''),
      facts: const [],
      confirm: tr('Chọn ứng dụng', 'Choose an app'),
      decline: cancel,
      destructive: false,
    ),
    IdeWebMicrophonePrompt() => (
      title: tr('Cho VPSTTT IDE dùng micro?', 'Let VPSTTT IDE use the mic?'),
      subject: null,
      facts: [
        (
          icon: Icons.graphic_eq_rounded,
          text: tr(
            'Giọng nói của bạn được gửi tới VPSTTT IDE.',
            'Your voice is sent to VPSTTT IDE.',
          ),
        ),
        (
          icon: Icons.mic_off_rounded,
          text: tr(
            'Micro tự tắt khi rời màn, khoá ứng dụng hoặc có cuộc gọi.',
            'The mic stops when you leave, lock the app, or get a call.',
          ),
        ),
        (
          icon: Icons.visibility_rounded,
          text: tr(
            'Thanh trên luôn báo khi đang thu.',
            'The top bar always shows when it is recording.',
          ),
        ),
      ],
      confirm: tr('Cho phép micro', 'Allow microphone'),
      decline: tr('Không cho phép', 'Don’t allow'),
      destructive: false,
    ),
    IdeWebExternalLinkPrompt(:final uri) => (
      title: tr(
        'Mở trang ngoài VPSTTT IDE?',
        'Open a page outside VPSTTT IDE?',
      ),
      subject: (
        badge: '',
        color: IdeWebInk.slate,
        name: uri.host,
        detail: tr('Mở bằng trình duyệt của máy', 'Opens in your browser'),
      ),
      facts: const [],
      confirm: tr('Mở trang', 'Open page'),
      decline: tr('Ở lại', 'Stay'),
      destructive: false,
    ),
  };
}

const _documentColors = <String, Color>{
  'pdf': Color(0xFFC8372D),
  'doc': Color(0xFF2457B5),
  'docx': Color(0xFF2457B5),
  'xls': Color(0xFF1E7145),
  'xlsx': Color(0xFF1E7145),
  'csv': Color(0xFF1E7145),
  'pptx': Color(0xFFB8471B),
  'png': Color(0xFF6A4BC4),
  'jpg': Color(0xFF6A4BC4),
  'jpeg': Color(0xFF6A4BC4),
  'zip': Color(0xFF8A6410),
};

_Subject _file(String name, String detail) {
  final extension = ideWebExtension(name);
  return (
    badge: extension.isEmpty || extension.length > 4
        ? tr('TỆP', 'FILE')
        : extension.toUpperCase(),
    color: _documentColors[extension] ?? IdeWebInk.slate,
    name: name,
    detail: detail,
  );
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  final text = (bytes / (1024 * 1024)).toStringAsFixed(1);
  return '${tr(text.replaceAll('.', ','), text)} MB';
}

/// Báo khi màn khác đè lên / rời khỏi bảng hỏi.
class _RouteWatcher extends StatefulWidget {
  const _RouteWatcher({required this.onChanged, required this.child});

  final VoidCallback onChanged;
  final Widget child;

  @override
  State<_RouteWatcher> createState() => _RouteWatcherState();
}

class _RouteWatcherState extends State<_RouteWatcher> {
  bool? _current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent;
    if (current == _current) return;
    _current = current;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
