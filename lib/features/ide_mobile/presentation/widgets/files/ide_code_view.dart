import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../application/ide_highlighter.dart';
import '../ide_wb.dart';

const ideCodeFontSize = 13.0;
const ideCodeLineHeight = 1.5;

const _mono = TextStyle(
  fontFamily: WebTuiTypography.monoFamily,
  fontFamilyFallback: WebTuiTypography.monoFallback,
  fontSize: ideCodeFontSize,
  height: ideCodeLineHeight,
  // Ghi rõ: ô sửa gộp kiểu chữ của theme (có giãn chữ), làm chữ trong trình sửa
  // rộng hơn chỗ đã đo và tự ngắt dòng.
  letterSpacing: 0,
  wordSpacing: 0,
);

/// Kiểu chữ mã, màu chữ theo bảng màu IDE của màn (màn sửa / xem tệp luôn tối).
TextStyle ideCodeStyle(BuildContext context) =>
    _mono.copyWith(color: IdeWbPalette.of(context).textStrong);

/// Ép mọi dòng cao bằng nhau để cột số dòng luôn thẳng hàng với chữ.
const ideCodeStrut = StrutStyle(
  fontFamily: WebTuiTypography.monoFamily,
  fontFamilyFallback: WebTuiTypography.monoFallback,
  fontSize: ideCodeFontSize,
  height: ideCodeLineHeight,
  forceStrutHeight: true,
);

/// Màn đang dùng bảng màu tối (để chọn bộ màu tô mã).
bool ideIsDark(BuildContext context) => IdeWbPalette.of(context).isDark;

/// Chiều cao một dòng đã nhân cỡ chữ người dùng chọn.
double ideCodeLineExtent(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(ideCodeFontSize) * ideCodeLineHeight;

/// Bề rộng một ký tự (chữ đơn cách).
double ideCodeCharWidth(BuildContext context) {
  final p = TextPainter(
    text: TextSpan(text: '0000000000', style: ideCodeStyle(context)),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final w = p.width / 10;
  p.dispose();
  return w;
}

/// Bề rộng cột số dòng cho [lines] dòng (chừa 1 điểm ảnh cho làm tròn).
double ideLineNumbersWidth(BuildContext context, int lines) =>
    (ideCodeCharWidth(context) * '$lines'.length.clamp(2, 7)).ceilToDouble() +
    1 +
    WebTuiSpacing.md * 2;

/// Cột số dòng.
class IdeLineNumbers extends StatelessWidget {
  const IdeLineNumbers({required this.lines, this.activeLine, super.key});

  final int lines;
  final int? activeLine;

  @override
  Widget build(BuildContext context) {
    final width = ideLineNumbersWidth(context, lines);
    final p = IdeWbPalette.of(context);
    final buf = StringBuffer();
    for (var i = 1; i <= lines; i++) {
      if (i > 1) buf.write('\n');
      buf.write(i);
    }
    return ExcludeSemantics(
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
        color: p.chip,
        child: Text(
          buf.toString(),
          textAlign: TextAlign.right,
          // Bề rộng đo vừa khít số chữ số: làm tròn lệch một chút cũng không
          // được để số ngắt xuống dòng (lệch số dòng với mã).
          softWrap: false,
          overflow: TextOverflow.visible,
          strutStyle: ideCodeStrut,
          style: ideCodeStyle(context).copyWith(color: p.text2),
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

  // Bộ nhớ kết quả tô: chỉ tô lại khi chữ / ngôn ngữ / sáng-tối đổi.
  String? _hlText;
  String? _hlLang;
  bool? _hlDark;
  TextStyle? _hlStyle;
  TextSpan? _hlSpan;
  int _hlSeq = 0;

  /// Chữ đã tô (hoặc null = chưa có / đang tô nền → vẽ chữ thường).
  TextSpan? _highlighted(TextStyle style, bool dark) {
    final text = widget.text;
    final lang = widget.language;
    if (_hlText == text &&
        _hlLang == lang &&
        _hlDark == dark &&
        _hlStyle == style) {
      return _hlSpan;
    }
    _hlText = text;
    _hlLang = lang;
    _hlDark = dark;
    _hlStyle = style;
    _hlSpan = null;
    final seq = ++_hlSeq;
    if (text.length <= ideHighlightSyncMaxChars) {
      _hlSpan = IdeHighlighter.highlight(text, lang, style: style, dark: dark);
    } else if (lang.isNotEmpty && text.length <= ideHighlightMaxChars) {
      // Tệp lớn: tô ở isolate nền, trong lúc chờ vẽ chữ thường.
      unawaited(() async {
        final segs = await ideHighlightSegmentsAsync(text, lang);
        if (!mounted || seq != _hlSeq || segs == null) return;
        setState(() {
          _hlSpan = IdeHighlighter.spanFromSegments(
            segs,
            style: style,
            dark: dark,
          );
        });
      }());
    }
    return _hlSpan;
  }

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
    final style = ideCodeStyle(context);
    final extent = ideCodeLineExtent(context);
    final span =
        _highlighted(style, ideIsDark(context)) ??
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
                child: ColoredBox(color: IdeWbPalette.of(context).accentSoft),
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
