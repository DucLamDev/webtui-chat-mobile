import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../application/ide_highlighter.dart';

const ideCodeFontSize = 13.0;
const ideCodeLineHeight = 1.5;

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Roboto Mono', 'Courier'],
  fontSize: ideCodeFontSize,
  height: ideCodeLineHeight,
);

/// Kiểu chữ mã (màu chữ theo giao diện hiện tại).
TextStyle ideCodeStyle() => _mono.copyWith(color: WebTuiColors.textPrimary);

/// Ép mọi dòng cao bằng nhau để cột số dòng luôn thẳng hàng với chữ.
const ideCodeStrut = StrutStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Roboto Mono', 'Courier'],
  fontSize: ideCodeFontSize,
  height: ideCodeLineHeight,
  forceStrutHeight: true,
);

bool ideIsDarkNow() => WebTuiColors.brightness == Brightness.dark;

/// Chiều cao một dòng đã nhân cỡ chữ người dùng chọn.
double ideCodeLineExtent(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(ideCodeFontSize) * ideCodeLineHeight;

/// Bề rộng một ký tự (chữ đơn cách).
double ideCodeCharWidth(BuildContext context) {
  final p = TextPainter(
    text: TextSpan(text: '0000000000', style: ideCodeStyle()),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final w = p.width / 10;
  p.dispose();
  return w;
}

/// Cột số dòng.
class IdeLineNumbers extends StatelessWidget {
  const IdeLineNumbers({required this.lines, this.activeLine, super.key});

  final int lines;
  final int? activeLine;

  @override
  Widget build(BuildContext context) {
    final digits = '$lines'.length.clamp(2, 7);
    final width = ideCodeCharWidth(context) * digits + WebTuiSpacing.md * 2;
    final buf = StringBuffer();
    for (var i = 1; i <= lines; i++) {
      if (i > 1) buf.write('\n');
      buf.write(i);
    }
    return ExcludeSemantics(
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
        color: WebTuiColors.backgroundMuted,
        child: Text(
          buf.toString(),
          textAlign: TextAlign.right,
          strutStyle: ideCodeStrut,
          style: ideCodeStyle().copyWith(color: WebTuiColors.textMuted),
        ),
      ),
    );
  }
}

/// Xem mã chỉ đọc: số dòng, tô màu, chọn / chép được, nhảy tới một dòng.
class IdeCodeView extends StatefulWidget {
  const IdeCodeView({
    required this.text,
    this.language = '',
    this.jumpToLine,
    super.key,
  });

  final String text;
  final String language;

  /// Dòng (từ 1) cần cuộn tới và nền sáng lên.
  final int? jumpToLine;

  @override
  State<IdeCodeView> createState() => _IdeCodeViewState();
}

class _IdeCodeViewState extends State<IdeCodeView> {
  final _vertical = ScrollController();
  bool _jumped = false;

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  void _jump(double extent) {
    final line = widget.jumpToLine;
    if (line == null || _jumped) return;
    _jumped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      final target = ((line - 1) * extent - 120).clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      );
      _vertical.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = ideCodeStyle();
    final extent = ideCodeLineExtent(context);
    final span =
        IdeHighlighter.highlight(
          widget.text,
          widget.language,
          style: style,
          dark: ideIsDarkNow(),
        ) ??
        TextSpan(text: widget.text, style: style);
    final lines = '\n'.allMatches(widget.text).length + 1;
    _jump(extent);
    final hit = widget.jumpToLine;
    return Scrollbar(
      controller: _vertical,
      child: SingleChildScrollView(
        controller: _vertical,
        child: Stack(
          children: [
            if (hit != null && hit >= 1 && hit <= lines)
              Positioned(
                left: 0,
                right: 0,
                top: (hit - 1) * extent + WebTuiSpacing.sm,
                height: extent,
                child: ColoredBox(color: WebTuiColors.primarySoft),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                  child: IdeLineNumbers(lines: lines),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                      WebTuiSpacing.md,
                      WebTuiSpacing.sm,
                      WebTuiSpacing.lg,
                      WebTuiSpacing.sm,
                    ),
                    child: SelectableText.rich(span, strutStyle: ideCodeStrut),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
