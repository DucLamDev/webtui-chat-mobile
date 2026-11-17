import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/markdown/my_note_line_ops.dart';

/// Controller cho ô soạn ghi chú kiểu app Ghi chú iPhone: văn bản vẫn là
/// markdown nhưng hiển thị thẳng định dạng (ẩn ký hiệu). Mỗi ký tự văn bản
/// ứng đúng một ký tự hiển thị: dấu bị ẩn là chữ cỡ rất nhỏ trong suốt, dấu
/// thay bằng hình (chấm, ô tick, vạch quote) là một WidgetSpan.
class MyNoteRichTextController extends TextEditingController {
  MyNoteRichTextController({super.text});

  /// true: vẫn hiện định dạng, bấm ô tick không đổi gì.
  bool readOnly = false;

  /// Gọi sau khi bấm ô tick đã đổi văn bản (màn soạn dùng để tự lưu).
  VoidCallback? onChecklistToggled;

  String? _parsedText;
  List<MyNoteLine> _lines = const [];
  List<MyNoteTextRange> _markers = const [];
  final _lineCache = <String, List<InlineSpan>>{};
  Object? _lineCacheKey;

  /// Các dòng của văn bản hiện tại (phân tích lại khi chữ đổi).
  List<MyNoteLine> get lines {
    _ensureParsed(text);
    return _lines;
  }

  void _ensureParsed(String source) {
    if (identical(_parsedText, source) || _parsedText == source) return;
    _parsedText = source;
    _lines = parseMyNoteLines(source);
    _markers = myNoteHiddenLineMarkersOf(_lines);
  }

  /// Giá trị hiện tại dạng [MyNoteEdit].
  MyNoteEdit get edit => myNoteEditFromValue(value);

  /// Gán chữ + vùng chọn trong một lần báo thay đổi.
  void applyEdit(MyNoteEdit edit) {
    value = TextEditingValue(
      text: edit.text,
      selection: TextSelection(
        baseOffset: edit.selectionStart,
        extentOffset: edit.selectionEnd,
      ),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = _snapCursor(newValue, value);
  }

  /// Con trỏ rơi vào dấu ẩn đầu dòng → dời ra ngay sau dấu. Đang lùi trái từ
  /// ngay sau dấu thì nhảy về cuối dòng trên, để không bị kẹt.
  TextEditingValue _snapCursor(TextEditingValue next, TextEditingValue prev) {
    final selection = next.selection;
    if (!selection.isValid || !selection.isCollapsed) return next;
    if (next.composing.isValid && !next.composing.isCollapsed) return next;
    _ensureParsed(next.text);
    final offset = selection.baseOffset;
    final marker = _markerAt(offset);
    if (marker == null) return next;
    final previous = prev.selection;
    final stepLeft = identical(prev.text, next.text) || prev.text == next.text
        ? previous.isValid &&
              previous.isCollapsed &&
              previous.baseOffset == marker.end &&
              offset == marker.end - 1
        : false;
    final target = stepLeft && marker.start > 0 ? marker.start - 1 : marker.end;
    if (target == offset) return next;
    return next.copyWith(selection: TextSelection.collapsed(offset: target));
  }

  MyNoteTextRange? _markerAt(int offset) {
    final markers = _markers;
    var low = 0;
    var high = markers.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final marker = markers[mid];
      if (offset < marker.start) {
        high = mid - 1;
      } else if (offset >= marker.end) {
        low = mid + 1;
      } else {
        return marker;
      }
    }
    return null;
  }

  void _toggleChecked(int lineStart) {
    if (readOnly) return;
    final before = edit;
    final after = toggleMyNoteCheckedAt(before, lineStart);
    if (after == before) return;
    applyEdit(after);
    onChecklistToggled?.call();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    _ensureParsed(source);
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final base = style ?? const TextStyle();
    // Đổi nền sáng / tối hoặc kiểu chữ gốc thì bỏ bộ nhớ đệm dòng.
    final cacheKey = (WebTuiColors.brightness, base);
    if (_lineCacheKey != cacheKey || _lineCache.length > 4000) {
      _lineCache.clear();
      _lineCacheKey = cacheKey;
    }
    final builder = _SpanBuilder(
      controller: this,
      source: source,
      base: base,
      selection: selection,
      composing: composing,
    );
    final sel = selection;
    for (final line in _lines) {
      // Dòng không có ô tick, không bị vùng chọn / chữ gõ dở chạm vào thì
      // dùng lại span đã dựng (chỉ phụ thuộc chữ của dòng).
      final cacheable =
          line.info.style != MyNoteBlockStyle.checklist &&
          !(sel.isValid && sel.start <= line.end && sel.end >= line.start) &&
          !(composing.isValid &&
              composing.start <= line.end &&
              composing.end >= line.start);
      if (!cacheable) {
        builder.addLine(line);
        continue;
      }
      final key =
          '${line.index == 0 ? 1 : 0}${line.isFence ? 1 : 0}'
          '${line.inCode ? 1 : 0}${line.end < source.length ? 1 : 0}'
          '${line.text}';
      final cached = _lineCache[key];
      if (cached != null) {
        builder.spans.addAll(cached);
        continue;
      }
      final from = builder.spans.length;
      builder.addLine(line);
      _lineCache[key] = builder.spans.sublist(from);
    }
    return TextSpan(style: builder.bodyStyle, children: builder.spans);
  }
}

/// Đổi [TextEditingValue] sang [MyNoteEdit] (vùng chọn hỏng → cuối văn bản).
MyNoteEdit myNoteEditFromValue(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid) {
    return MyNoteEdit.collapsed(value.text, value.text.length);
  }
  return MyNoteEdit(
    value.text,
    selectionStart: selection.start,
    selectionEnd: selection.end,
  );
}

/// Enter trên dòng danh sách / checklist / quote → dòng mới cùng dấu; Enter
/// trên dòng chỉ có dấu → thoát danh sách; xoá lùi ngay sau dấu → bỏ dấu.
class MyNoteListInputFormatter extends TextInputFormatter {
  const MyNoteListInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid || !newValue.selection.isValid) {
      return newValue;
    }
    final before = myNoteEditFromValue(oldValue);
    final after = myNoteEditFromValue(newValue);
    final delta = newValue.text.length - oldValue.text.length;
    MyNoteEdit? result;
    if (delta == 1 - (before.selectionEnd - before.selectionStart)) {
      result = myNoteHandleNewline(before, after);
    } else if (delta == -1) {
      result = myNoteHandleBackspace(before, after);
    }
    if (result == null) return newValue;
    return TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
  }
}

const _monospaceFallback = ['Menlo', 'Courier', 'monospace'];
const _transparent = Color(0x00000000);
final _urlRe = RegExp(r'https?://[^\s<>()]+');
final _trailingPunctuationRe = RegExp(r'[.,;:!?]+$');

/// Đoạn có kiểu trong một dòng, vị trí tương đối [start, end).
final class _Range {
  const _Range(this.start, this.end);

  final int start;
  final int end;
}

/// Dựng cây span cho từng dòng; giữ đúng một ký tự hiển thị cho mỗi ký tự văn
/// bản.
final class _SpanBuilder {
  _SpanBuilder({
    required this.controller,
    required this.source,
    required TextStyle base,
    required this.selection,
    required this.composing,
  }) {
    // Giữ phông của ô nhập (phông hệ thống của theme).
    bodyStyle = base.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: WebTuiColors.textPrimary,
    );
    // Đề mục giãn dòng rộng hơn để có khoảng thở phía trên như app Ghi chú.
    titleStyle = bodyStyle.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    headingStyle = bodyStyle.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.55,
    );
    subheadingStyle = bodyStyle.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.5,
    );
    codeStyle = bodyStyle.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: _monospaceFallback,
      fontSize: 15,
      backgroundColor: WebTuiColors.chipBackground,
    );
    fenceStyle = codeStyle.copyWith(
      fontSize: 12,
      color: WebTuiColors.textMuted,
    );
  }

  final MyNoteRichTextController controller;
  final String source;
  final TextSelection selection;
  final TextRange composing;
  final spans = <InlineSpan>[];

  late final TextStyle bodyStyle;
  late final TextStyle titleStyle;
  late final TextStyle headingStyle;
  late final TextStyle subheadingStyle;
  late final TextStyle codeStyle;
  late final TextStyle fenceStyle;

  static const hiddenStyle = TextStyle(
    fontSize: 0.01,
    color: _transparent,
    backgroundColor: _transparent,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  TextStyle _lineStyle(MyNoteLine line) {
    if (line.isFence) return fenceStyle;
    if (line.inCode) return codeStyle;
    final info = line.info;
    if (line.index == 0) return titleStyle;
    return switch (info.style) {
      MyNoteBlockStyle.title => titleStyle,
      MyNoteBlockStyle.heading => headingStyle,
      MyNoteBlockStyle.subheading => subheadingStyle,
      MyNoteBlockStyle.quote => bodyStyle.copyWith(
        color: WebTuiColors.textSecondary,
      ),
      MyNoteBlockStyle.checklist when info.checked => bodyStyle.copyWith(
        color: WebTuiColors.textMuted,
      ),
      _ => bodyStyle,
    };
  }

  void addLine(MyNoteLine line) {
    final lineStyle = _lineStyle(line);
    final info = line.info;
    final t = line.text;
    var content = 0;
    if (!line.isCode && info.markerLength > 0) {
      content = info.markerLength;
      _addMarker(line, lineStyle);
    }
    if (content < t.length) {
      if (line.isCode) {
        _addText(line.start + content, t.substring(content), lineStyle);
      } else {
        _addContent(line, content, lineStyle);
      }
    }
    if (line.end < source.length) {
      // Ký tự xuống dòng mang kiểu của dòng, để cao dòng đúng.
      _addText(line.end, '\n', lineStyle);
    }
  }

  void _addMarker(MyNoteLine line, TextStyle lineStyle) {
    final info = line.info;
    final start = line.start;
    final t = line.text;
    switch (info.style) {
      case MyNoteBlockStyle.title ||
          MyNoteBlockStyle.heading ||
          MyNoteBlockStyle.subheading ||
          MyNoteBlockStyle.body ||
          MyNoteBlockStyle.monospace:
        _addText(start, t.substring(0, info.markerLength), hiddenStyle);
      case MyNoteBlockStyle.numbered:
        _addIndent(start, info.indent, lineStyle);
        final digitsEnd = info.markerLength - 1;
        _addText(
          start + info.indent,
          t.substring(info.indent, digitsEnd),
          lineStyle.copyWith(
            fontWeight: lineStyle.fontWeight == FontWeight.w400
                ? FontWeight.w500
                : lineStyle.fontWeight,
          ),
        );
        _addText(start + digitsEnd, ' ', lineStyle);
      case MyNoteBlockStyle.bullet ||
          MyNoteBlockStyle.checklist ||
          MyNoteBlockStyle.quote:
        _addIndent(start, info.indent, lineStyle);
        spans.add(_markerWidget(line, lineStyle));
        final restStart = info.indent + 1;
        if (restStart < info.markerLength) {
          _addText(
            start + restStart,
            t.substring(restStart, info.markerLength),
            hiddenStyle,
          );
        }
    }
  }

  /// Khoảng thụt danh sách lồng: giữ dấu cách nhưng giãn rộng ra.
  void _addIndent(int start, int indent, TextStyle lineStyle) {
    if (indent == 0) return;
    _addText(start, ' ' * indent, lineStyle.copyWith(letterSpacing: 10));
  }

  WidgetSpan _markerWidget(MyNoteLine line, TextStyle lineStyle) {
    final info = line.info;
    final Widget child;
    switch (info.style) {
      case MyNoteBlockStyle.checklist:
        child = _MyNoteCheckbox(
          checked: info.checked,
          enabled: !controller.readOnly,
          onTap: () => controller._toggleChecked(line.start),
        );
      case MyNoteBlockStyle.quote:
        child = Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            width: 3,
            height: (lineStyle.fontSize ?? 17) * 1.35,
            decoration: BoxDecoration(
              color: WebTuiColors.textMuted.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      default:
        child = SizedBox(
          width: 22,
          child: Text(
            '•',
            textAlign: TextAlign.center,
            style: lineStyle.copyWith(
              color: WebTuiColors.textPrimary,
              decoration: TextDecoration.none,
              backgroundColor: _transparent,
            ),
          ),
        );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: lineStyle,
      child: child,
    );
  }

  /// Phần chữ sau dấu đầu dòng: định dạng nội dòng, #tag, liên kết.
  void _addContent(MyNoteLine line, int content, TextStyle lineStyle) {
    final t = line.text;
    final inline = [
      for (final span in parseMyNoteInlineSpans(t))
        if (span.start >= content) span,
    ];
    final codeRanges = [
      for (final span in inline)
        if (span.style == MyNoteInlineStyle.code) span,
    ];
    bool inCodeSpan(int s, int e) =>
        codeRanges.any((c) => s >= c.start && e <= c.end);
    final tags = [
      for (final range in myNoteTagRangesInLine(t))
        if (range.start >= content && !inCodeSpan(range.start, range.end))
          _Range(range.start, range.end),
    ];
    final urls = <_Range>[];
    if (t.contains('http')) {
      for (final match in _urlRe.allMatches(t)) {
        final trimmed = match
            .group(0)!
            .replaceFirst(_trailingPunctuationRe, '');
        final end = match.start + trimmed.length;
        if (match.start >= content && !inCodeSpan(match.start, end)) {
          urls.add(_Range(match.start, end));
        }
      }
    }
    if (inline.isEmpty && tags.isEmpty && urls.isEmpty) {
      _addText(line.start + content, t.substring(content), lineStyle);
      return;
    }

    // Vùng chọn chạm đoạn nào thì hiện mờ dấu của đoạn đó để sửa được.
    final selStart = selection.isValid ? selection.start - line.start : -1;
    final selEnd = selection.isValid ? selection.end - line.start : -1;
    bool touched(MyNoteInlineSpan span) =>
        selection.isValid && selStart <= span.end && selEnd >= span.start;

    final cuts = <int>{content, t.length};
    for (final span in inline) {
      cuts.addAll([span.start, span.contentStart, span.contentEnd, span.end]);
    }
    for (final range in [...tags, ...urls]) {
      cuts.addAll([range.start, range.end]);
    }
    final points = cuts.where((p) => p >= content && p <= t.length).toList()
      ..sort();
    for (var i = 0; i + 1 < points.length; i++) {
      final s = points[i];
      final e = points[i + 1];
      if (e <= s) continue;
      var style = lineStyle;
      var isMark = false;
      var markVisible = false;
      for (final span in inline) {
        if (s < span.start || e > span.end) continue;
        final inMark = s < span.contentStart || e > span.contentEnd;
        if (inMark) {
          isMark = true;
          if (touched(span)) markVisible = true;
          continue;
        }
        style = switch (span.style) {
          MyNoteInlineStyle.bold => style.copyWith(fontWeight: FontWeight.w700),
          MyNoteInlineStyle.italic => style.copyWith(
            fontStyle: FontStyle.italic,
          ),
          MyNoteInlineStyle.strikethrough => style.copyWith(
            decoration: TextDecoration.lineThrough,
          ),
          MyNoteInlineStyle.code => style.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: _monospaceFallback,
            fontSize: (style.fontSize ?? 17) * 0.88,
            backgroundColor: WebTuiColors.chipBackground,
          ),
        };
      }
      if (isMark) {
        style = markVisible
            ? style.copyWith(color: WebTuiColors.textMuted)
            : hiddenStyle;
      } else if (tags.any((r) => s >= r.start && e <= r.end)) {
        style = style.copyWith(color: WebTuiColors.primary);
      } else if (urls.any((r) => s >= r.start && e <= r.end)) {
        style = style.copyWith(
          color: WebTuiColors.primary,
          decoration: TextDecoration.underline,
          decorationColor: WebTuiColors.primary,
        );
      }
      _addText(line.start + s, t.substring(s, e), style);
    }
  }

  /// Thêm chữ ở vị trí tuyệt đối [start]; tách phần đang gõ dở (composing)
  /// để gạch dưới như TextEditingController mặc định.
  void _addText(int start, String text, TextStyle style) {
    if (text.isEmpty) return;
    final end = start + text.length;
    if (!composing.isValid ||
        composing.isCollapsed ||
        composing.end <= start ||
        composing.start >= end ||
        identical(style, hiddenStyle)) {
      spans.add(TextSpan(text: text, style: style));
      return;
    }
    final cs = composing.start.clamp(start, end);
    final ce = composing.end.clamp(start, end);
    if (cs > start) {
      spans.add(TextSpan(text: text.substring(0, cs - start), style: style));
    }
    spans.add(
      TextSpan(
        text: text.substring(cs - start, ce - start),
        style: style.merge(
          const TextStyle(decoration: TextDecoration.underline),
        ),
      ),
    );
    if (ce < end) {
      spans.add(TextSpan(text: text.substring(ce - start), style: style));
    }
  }
}

/// Ô tick tròn 22px kiểu app Ghi chú iPhone, vùng bấm 32px.
class _MyNoteCheckbox extends StatelessWidget {
  const _MyNoteCheckbox({
    required this.checked,
    required this.enabled,
    required this.onTap,
  });

  final bool checked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      button: enabled,
      label: tr('Ô đánh dấu', 'Checkbox'),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          key: const ValueKey('my-note-checkbox'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? WebTuiColors.primaryFill : _transparent,
                  border: checked
                      ? null
                      : Border.all(color: WebTuiColors.textMuted, width: 1.5),
                ),
                child: checked
                    ? const Icon(
                        WebTuiIcons.check,
                        size: 14,
                        color: Color(0xFFFFFFFF),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
