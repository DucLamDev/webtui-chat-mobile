import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../../core/platform/external_url_launcher.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
import 'ide_blocks_model.dart';
import 'ide_chart_view.dart';
import 'ide_code_block.dart';
import 'ide_diagram_view.dart';
import 'ide_form_view.dart';

/// Màu chữ `{đỏ|…}` `{cam|…}` `{xanh|…}` `{lam|…}` (cùng bảng `MD_COLORS` của IDE).
const _colorNames = <String, String>{
  'đỏ': 'bad',
  'red': 'bad',
  'cam': 'warn',
  'amber': 'warn',
  'xanh': 'ok',
  'green': 'ok',
  'lam': 'info',
  'blue': 'info',
};

/// Màu theo ý nghĩa; chữ trên nền trắng / nền tối đều đạt tương phản đọc được.
/// [dark]: bảng màu của màn đang vẽ (mặc định theo máy).
Color ideTextColorFor(String kind, {bool? dark}) {
  dark ??= IdeWbPalette.current.isDark;
  return switch (kind) {
    'bad' => dark ? const Color(0xFFF28B8B) : const Color(0xFFC62828),
    'warn' => dark ? const Color(0xFFEDB04A) : const Color(0xFFA85A00),
    'ok' => dark ? const Color(0xFF3CCB94) : const Color(0xFF15803D),
    _ => dark ? const Color(0xFF6FB1FF) : const Color(0xFF0A6CDE),
  };
}

/// `{đỏ|chữ}` (cũng nhận `{đỏ\|chữ}` trong ô bảng). Tên màu lạ thì để nguyên.
class _ColorSyntax extends md.InlineSyntax {
  _ColorSyntax() : super(r'\{([^{}|\n\\]{1,12})\\?\|([^{}\n]+)\}');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final kind = _colorNames[match[1]!.trim().toLowerCase()];
    if (kind == null) {
      // tryMatch của gói markdown không tiến con trỏ khi trả false: tự thêm chữ gốc.
      parser.addNode(md.Text(match[0]!));
      return true;
    }
    final children = md.InlineParser(match[2]!, parser.document).parse();
    parser.addNode(md.Element('ide-color', children)..attributes['k'] = kind);
    return true;
  }
}

sealed class _Segment {}

final class _TextSegment extends _Segment {
  _TextSegment(this.text);
  final String text;
}

final class _FenceSegment extends _Segment {
  _FenceSegment(this.lang, this.body, {required this.closed});
  final String lang;
  final String body;
  final bool closed;
}

final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*([^\s`]*)[^`]*$');

/// Tách khối mã bao ``` / ~~~ (cả khối chưa đóng khi đang chảy chữ).
List<_Segment> _split(String text) {
  final segments = <_Segment>[];
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final buf = <String>[];
  void flushText() {
    if (buf.isEmpty) return;
    segments.add(_TextSegment(buf.join('\n')));
    buf.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final m = _fenceOpen.firstMatch(lines[i]);
    if (m == null) {
      buf.add(lines[i++]);
      continue;
    }
    flushText();
    final marker = m[1]!;
    final lang = m[2]!.toLowerCase();
    final close = RegExp(
      '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
    );
    final body = <String>[];
    var closed = false;
    i++;
    while (i < lines.length) {
      if (close.hasMatch(lines[i])) {
        closed = true;
        i++;
        break;
      }
      body.add(lines[i++]);
    }
    segments.add(_FenceSegment(lang, body.join('\n'), closed: closed));
  }
  flushText();
  return segments;
}

final _colorPipe = RegExp(r'\{(đỏ|cam|xanh|lam|red|amber|green|blue)\|');
final _danglingColor = RegExp(r'\{[^{}|\n\\]{0,12}\\?\|([^{}\n]*)$');
final _danglingName = RegExp(r'\{[^{}|\n\\]{0,12}$');

String _prepareText(
  String text, {
  required bool streaming,
  required bool last,
}) {
  // Dấu | trong {đỏ|chữ} không phải vách ô bảng: thoát trước khi tách ô.
  var out = text.replaceAllMapped(_colorPipe, (m) => '{${m[1]}\\|');
  if (streaming && last) {
    // Chữ màu dở: "{đỏ|chữ đang gõ" chỉ hiện chữ, "{đỏ" / "{đỏ|" ẩn tới khi có chữ.
    out = out.replaceFirstMapped(_danglingColor, (m) => m[1]!);
    out = out.replaceFirst(_danglingName, '');
  }
  return out;
}

/// Quá ngưỡng này thì hiện chữ thường, không tô markdown.
const ideMarkdownMaxChars = 100 * 1024;

/// Markdown đủ dùng cho câu trả lời AI, kèm chữ màu và khối vẽ native
/// ` ```bieudo ` / ` ```form ` / ` ```sodo `. JSON sai → khối mã thường; khi
/// [streaming] mà khối chưa đóng → hiện tạm dạng mã.
class IdeMarkdown extends StatefulWidget {
  const IdeMarkdown({
    required this.text,
    this.onFormSubmit,
    this.streaming = false,
    this.formKey,
    this.onLink,
    this.style,
    this.launcher = const MethodChannelExternalUrlLauncher(),
    super.key,
  });

  final String text;

  /// Gửi biểu mẫu: nhận chuỗi trả lời giống IDE web. Null → biểu mẫu chỉ xem.
  ///
  /// Có thể trả `Future`: ném lỗi hoặc trả `false` nghĩa là gửi hỏng (biểu mẫu
  /// mở lại, không hiện "Đã gửi"). Trả `null` / không trả gì = đã gửi.
  final FutureOr<dynamic> Function(String answer)? onFormSubmit;
  final bool streaming;

  /// Mã tin (tuỳ chọn): biểu mẫu đã gửi vẫn hiện "Đã gửi" khi tin vẽ lại.
  final String? formKey;

  /// Mở liên kết; mặc định hỏi xác nhận (hiện tên miền) rồi chỉ mở http(s)
  /// bằng trình duyệt ngoài.
  final ValueChanged<String>? onLink;
  final ExternalUrlLauncher launcher;
  final TextStyle? style;

  @override
  State<IdeMarkdown> createState() => _IdeMarkdownState();
}

class _IdeMarkdownState extends State<IdeMarkdown> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String url) async {
    final custom = widget.onLink;
    if (custom != null) {
      custom(url);
      return;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mở liên kết?', 'Open link?')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: tr('Trang web: ', 'Website: ')),
                    TextSpan(
                      text: uri.host,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: WebTuiSpacing.sm),
              SelectableText(uri.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('ide_link_cancel'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Huỷ', 'Cancel')),
          ),
          FilledButton(
            key: const Key('ide_link_open'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Mở', 'Open')),
          ),
        ],
      ),
    );
    if (ok == true) unawaited(widget.launcher.open(uri.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final old = [..._recognizers];
    _recognizers.clear();
    final base =
        widget.style ??
        IdeType.bodyMedium.copyWith(
          color: IdeWbPalette.of(context).textStrong,
          fontWeight: FontWeight.w400,
          height: 1.45,
          fontSize: IdeType.chat,
        );
    if (widget.text.length > ideMarkdownMaxChars) {
      // Quá dài (> 100 KB): không tô markdown để khỏi đơ máy; vẫn chọn / chép được.
      return SelectableText(widget.text, style: base);
    }
    final r = _Renderer(
      base,
      _recognizers,
      (u) => unawaited(_open(u)),
      IdeWbPalette.of(context),
    );
    final segments = _split(widget.text);
    final children = <Widget>[];
    var formIndex = 0;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      switch (seg) {
        case _TextSegment():
          final text = _prepareText(
            seg.text,
            streaming: widget.streaming,
            last: i == segments.length - 1,
          );
          children.addAll(r.markdown(text));
        case _FenceSegment():
          final live = !(widget.streaming && !seg.closed);
          final Widget? native = live ? _native(seg, formIndex) : null;
          if (seg.lang == 'form') formIndex++;
          children.add(
            native ?? IdeCodeBlock(code: seg.body, language: seg.lang),
          );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final rec in old) {
        rec.dispose();
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : WebTuiSpacing.sm),
            child: children[i],
          ),
      ],
    );
  }

  Widget? _native(_FenceSegment seg, int formIndex) {
    switch (seg.lang) {
      case 'bieudo':
        final spec = parseIdeChart(seg.body);
        return spec == null ? null : IdeChartView(spec: spec);
      case 'form':
        final spec = parseIdeForm(seg.body);
        if (spec == null) return null;
        final submit = widget.onFormSubmit;
        final key = widget.formKey;
        return IdeFormView(
          spec: spec,
          sentKey: key == null ? null : '$key:$formIndex',
          onSubmit: submit,
        );
      case 'sodo':
        final spec = parseIdeDiagram(seg.body);
        return spec == null ? null : IdeDiagramView(spec: spec);
    }
    return null;
  }
}

class _Renderer {
  _Renderer(this.base, this.recognizers, this.onLink, this.p);

  final TextStyle base;

  /// Bảng màu của màn đang vẽ: màn xem tệp luôn tối, chat AI theo máy.
  final IdeWbPalette p;
  final List<TapGestureRecognizer> recognizers;
  final void Function(String url) onLink;

  List<Widget> markdown(String text) {
    final document = md.Document(
      extensionSet: md.ExtensionSet(
        [const md.FencedCodeBlockSyntax(), const md.TableSyntax()],
        [md.StrikethroughSyntax(), md.AutolinkExtensionSyntax()],
      ),
      inlineSyntaxes: [_ColorSyntax()],
      encodeHtml: false,
    );
    final nodes = document.parseLines(text.split('\n'));
    return blocks(nodes);
  }

  List<Widget> blocks(List<md.Node> nodes) {
    final out = <Widget>[];
    final inlineRun = <md.Node>[];
    void flush() {
      if (inlineRun.isEmpty) return;
      final spans = [for (final n in inlineRun) inline(n, base)];
      inlineRun.clear();
      final hasText = spans.any((s) => s.toPlainText().trim().isNotEmpty);
      if (hasText) out.add(Text.rich(TextSpan(children: spans)));
    }

    for (final n in nodes) {
      if (n is md.Element && _isBlock(n.tag)) {
        flush();
        out.add(block(n));
      } else {
        inlineRun.add(n);
      }
    }
    flush();
    return out;
  }

  static bool _isBlock(String tag) => const {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'hr',
    'table',
  }.contains(tag);

  Widget block(md.Element e) {
    switch (e.tag) {
      case 'p':
        return Text.rich(
          TextSpan(
            children: [
              for (final c in e.children ?? <md.Node>[]) inline(c, base),
            ],
          ),
        );
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(e.tag.substring(1));
        final size = const [21.0, 19.0, 17.0, 16.0, 15.0, 15.0][level - 1];
        final style = base.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1.3,
        );
        return Padding(
          padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
          child: Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final c in e.children ?? <md.Node>[]) inline(c, style),
                ],
              ),
            ),
          ),
        );
      case 'hr':
        return const Divider(height: 16);
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: WebTuiSpacing.md),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: p.accentInk, width: 3)),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: p.text),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _spaced(blocks(e.children ?? const [])),
            ),
          ),
        );
      case 'pre':
        final code = e.children?.whereType<md.Element>().firstOrNull;
        final cls = code?.attributes['class'] ?? '';
        final lang = cls.startsWith('language-') ? cls.substring(9) : '';
        var body = code?.textContent ?? e.textContent;
        if (body.endsWith('\n')) body = body.substring(0, body.length - 1);
        return IdeCodeBlock(code: body, language: lang);
      case 'ul' || 'ol':
        return _list(e);
      case 'table':
        return _table(e);
    }
    return const SizedBox.shrink();
  }

  List<Widget> _spaced(List<Widget> items) => [
    for (var i = 0; i < items.length; i++)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : WebTuiSpacing.xs),
        child: items[i],
      ),
  ];

  Widget _list(md.Element e) {
    final ordered = e.tag == 'ol';
    final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
    var n = start;
    final rows = <Widget>[];
    for (final li
        in (e.children ?? const <md.Node>[]).whereType<md.Element>()) {
      if (li.tag != 'li') continue;
      final marker = ordered ? '${n++}.' : '•';
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ordered ? 28 : 18,
                child: Text(marker, style: base, textAlign: TextAlign.right),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: blocks(li.children ?? const []),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _table(md.Element e) {
    final rows = <TableRow>[];
    void addRows(md.Element? section, {required bool head}) {
      if (section == null) return;
      for (final tr
          in (section.children ?? const <md.Node>[]).whereType<md.Element>()) {
        final cells = <Widget>[];
        for (final c
            in (tr.children ?? const <md.Node>[]).whereType<md.Element>()) {
          final style = head
              ? base.copyWith(fontWeight: FontWeight.w700, fontSize: 13.5)
              : base.copyWith(fontSize: 13.5);
          final align = switch (c.attributes['align']) {
            'right' => TextAlign.right,
            'center' => TextAlign.center,
            _ => TextAlign.left,
          };
          cells.add(
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (final x in c.children ?? <md.Node>[])
                        inline(x, style),
                    ],
                  ),
                  textAlign: align,
                ),
              ),
            ),
          );
        }
        rows.add(
          TableRow(
            decoration: head ? BoxDecoration(color: p.chip) : null,
            children: cells,
          ),
        );
      }
    }

    final kids = (e.children ?? const <md.Node>[]).whereType<md.Element>();
    addRows(kids.where((x) => x.tag == 'thead').firstOrNull, head: true);
    addRows(kids.where((x) => x.tag == 'tbody').firstOrNull, head: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows
        .map((r) => r.children.length)
        .reduce((a, b) => a > b ? a : b);
    // Hàng thiếu ô thì bù ô trống để Table không lỗi.
    final fixed = [
      for (final r in rows)
        TableRow(
          decoration: r.decoration,
          children: [
            ...r.children,
            for (var i = r.children.length; i < cols; i++)
              const SizedBox.shrink(),
          ],
        ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(
              horizontalInside: BorderSide(color: p.border),
              verticalInside: BorderSide(color: p.border),
            ),
            children: fixed,
          ),
        ),
      ),
    );
  }

  InlineSpan inline(md.Node n, TextStyle style) {
    if (n is md.Text) return TextSpan(text: n.text, style: style);
    if (n is! md.Element) return const TextSpan();
    List<InlineSpan> kids(TextStyle s) => [
      for (final c in n.children ?? <md.Node>[]) inline(c, s),
    ];
    switch (n.tag) {
      case 'strong':
        return TextSpan(
          children: kids(style.copyWith(fontWeight: FontWeight.w800)),
        );
      case 'em':
        return TextSpan(
          children: kids(style.copyWith(fontStyle: FontStyle.italic)),
        );
      case 'del':
        return TextSpan(
          children: kids(
            style.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      case 'code':
        return TextSpan(
          text: n.textContent,
          style: style.merge(
            ideMonoStyle.copyWith(
              fontSize: (style.fontSize ?? 15) - 1.5,
              backgroundColor: p.chip,
            ),
          ),
        );
      case 'br':
        return TextSpan(text: '\n', style: style);
      case 'ide-color':
        return TextSpan(
          children: kids(
            style.copyWith(
              color: ideTextColorFor(n.attributes['k'] ?? '', dark: p.isDark),
            ),
          ),
        );
      case 'a':
        final href = n.attributes['href'] ?? '';
        final rec = TapGestureRecognizer()..onTap = () => onLink(href);
        recognizers.add(rec);
        return TextSpan(
          children: kids(
            style.copyWith(
              color: p.accentInk,
              decoration: TextDecoration.underline,
            ),
          ),
          recognizer: rec,
        );
      case 'img':
        return TextSpan(text: n.attributes['alt'] ?? '', style: style);
    }
    return TextSpan(children: kids(style));
  }
}
