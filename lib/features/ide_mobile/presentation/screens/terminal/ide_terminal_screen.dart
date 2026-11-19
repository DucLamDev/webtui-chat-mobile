import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_term_controller.dart';
import '../../../domain/ide_term.dart';
import '../../controllers/ide_term_controllers.dart';
import '../../widgets/terminal/ide_term_extra_keys.dart';
import '../../widgets/terminal/ide_term_pinch.dart';
import '../../widgets/terminal/ide_term_theme.dart';

/// Màn một terminal. Đóng màn chỉ đóng stream, phiên vẫn chạy trên máy tính.
class IdeTerminalScreen extends ConsumerStatefulWidget {
  const IdeTerminalScreen({required this.target, this.title = '', super.key});

  final IdeTermOpenTarget target;
  final String title;

  @override
  ConsumerState<IdeTerminalScreen> createState() => _State();
}

class _State extends ConsumerState<IdeTerminalScreen> {
  final _view = TerminalController();
  final _focus = FocusNode();
  double _font = ideTermDefaultFont;
  double _pinchBase = ideTermDefaultFont;

  @override
  void initState() {
    super.initState();
    _wake(true);
  }

  @override
  void dispose() {
    _wake(false);
    _view.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Giữ màn hình sáng khi đang mở; máy không hỗ trợ thì bỏ qua.
  void _wake(bool on) {
    try {
      unawaited(
        (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError(
          (Object _) {},
        ),
      );
    } on Object {
      // Không có plugin (test): không sao.
    }
  }

  Future<void> _copy(IdeTermController c) async {
    final range = _view.selection;
    if (range == null) return;
    final text = c.terminal.buffer.getText(range);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _view.clearSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('Đã sao chép', 'Copied'))));
  }

  Future<void> _paste(IdeTermController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty || !mounted) return;
    if (text.contains('\n')) {
      final lines = text.trimRight().split('\n').length;
      final ok = await showWebTuiConfirmDialog(
        context,
        title: tr('Dán nhiều dòng?', 'Paste multiple lines?'),
        message: tr(
          'Nội dung có $lines dòng và có thể chạy ngay trong terminal.',
          'The text has $lines lines and may run right away in the terminal.',
        ),
        confirmLabel: tr('Dán', 'Paste'),
        icon: Icons.content_paste_rounded,
      );
      if (!ok) return;
    }
    c.terminal.paste(text);
  }

  @override
  Widget build(BuildContext context) {
    final provider = ideTermControllerProvider(widget.target);
    final snap = ref.watch(provider);
    final c = ref.read(provider.notifier);
    final brightness = Theme.of(context).brightness;
    final theme = ideTermTheme(brightness);
    final title = snap.name.isNotEmpty
        ? snap.name
        : (widget.title.isNotEmpty ? widget.title : 'Terminal');

    final Widget body = switch (snap.link) {
      IdeTermLink.denied => _Notice(
        icon: Icons.terminal_rounded,
        title: tr(
          'Quản trị đã tắt terminal trên điện thoại.',
          'The admin turned terminal off on phones.',
        ),
      ),
      IdeTermLink.busy => _Notice(
        icon: Icons.layers_clear_outlined,
        title: tr(
          'Đã mở quá số terminal cho phép',
          'Too many terminals are open',
        ),
        message: tr(
          'Hãy đóng bớt terminal ở máy khác rồi thử lại.',
          'Close some terminals elsewhere and try again.',
        ),
      ),
      // Gắn lại: phiên đã bị đóng. Mở mới: thư mục dự án hoặc máy chủ đã
      // chọn không còn trên IDE.
      IdeTermLink.notFound when widget.target.name == null => _Notice(
        icon: Icons.search_off_rounded,
        title: tr(
          'Không tìm thấy dự án hoặc máy chủ đã chọn',
          'The chosen project or server was not found',
        ),
        message: tr(
          'Có thể thư mục đã bị xoá hoặc bạn không còn quyền vào máy đó. Hãy chọn lại.',
          'The folder may be gone or you lost access to that server. Pick again.',
        ),
      ),
      IdeTermLink.notFound => _Notice(
        icon: Icons.search_off_rounded,
        title: tr('Phiên này không còn', 'This session is gone'),
      ),
      IdeTermLink.failed => _Notice(
        icon: Icons.error_outline_rounded,
        title: tr('Không mở được terminal', 'Could not open the terminal'),
        message: snap.message,
      ),
      _ => _terminal(snap, c, theme),
    };

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (snap.link == IdeTermLink.live ||
              snap.link == IdeTermLink.exited) ...[
            AnimatedBuilder(
              animation: _view,
              builder: (_, _) => IconButton(
                key: const Key('term_copy'),
                tooltip: tr('Sao chép', 'Copy'),
                onPressed: _view.selection == null ? null : () => _copy(c),
                icon: const Icon(Icons.copy_rounded),
              ),
            ),
            if (snap.isLive)
              IconButton(
                key: const Key('term_paste'),
                tooltip: tr('Dán', 'Paste'),
                onPressed: () => _paste(c),
                icon: const Icon(Icons.content_paste_rounded),
              ),
          ],
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _terminal(
    IdeTermSnapshot snap,
    IdeTermController c,
    TerminalTheme theme,
  ) {
    return Column(
      children: [
        _Banner(snap: snap, onReconnect: c.reconnect),
        Expanded(
          child: IdeTermPinch(
            onStart: () => _pinchBase = _font,
            onScale: (s) {
              final next = ideTermClampFont(_pinchBase * s);
              if ((next - _font).abs() >= 0.25) setState(() => _font = next);
            },
            child: TerminalView(
              c.terminal,
              key: const Key('term_view'),
              controller: _view,
              focusNode: _focus,
              theme: theme,
              textStyle: TerminalStyle(fontSize: _font),
              autofocus: true,
              deleteDetection: true,
              readOnly: !snap.isLive,
              padding: const EdgeInsets.all(4),
            ),
          ),
        ),
        if (snap.isLive)
          IdeTermExtraKeys(
            ctrl: snap.ctrl,
            alt: snap.alt,
            onToggleCtrl: c.toggleCtrl,
            onToggleAlt: c.toggleAlt,
            onText: c.pressText,
            onNav: c.pressNav,
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.snap, required this.onReconnect});

  final IdeTermSnapshot snap;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final (String? text, Color color, bool retry) = switch (snap.link) {
      IdeTermLink.connecting => (
        tr('Đang kết nối...', 'Connecting...'),
        WebTuiColors.accentAmber,
        false,
      ),
      IdeTermLink.lost => (
        tr(
          'Mất kết nối. Phiên vẫn chạy trên máy tính.',
          'Disconnected. The session keeps running on the computer.',
        ),
        WebTuiColors.danger,
        true,
      ),
      IdeTermLink.exited => (
        tr(
          'Phiên đã kết thúc (mã ${snap.exitCode ?? 0})',
          'Session ended (code ${snap.exitCode ?? 0})',
        ),
        WebTuiColors.textSecondary,
        false,
      ),
      _ => (null, WebTuiColors.textMuted, false),
    };
    if (text == null) return const SizedBox.shrink();
    return Material(
      color: WebTuiColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.lg,
          vertical: WebTuiSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                text,
                key: const Key('term_banner'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ),
            if (retry)
              TextButton(
                key: const Key('term_reconnect'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: onReconnect,
                child: Text(tr('Nối lại', 'Reconnect')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, this.message = ''});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.background,
      child: WebTuiEmptyState(
        key: const Key('term_notice'),
        title: title,
        message: message,
        icon: icon,
      ),
    );
  }
}
