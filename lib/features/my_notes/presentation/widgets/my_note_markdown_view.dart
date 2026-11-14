import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/markdown/my_note_markdown.dart';

/// Hiển thị nội dung ghi chú đã render từ markdown. Chọn / sao chép được; chạm
/// liên kết mở bằng trình duyệt ngoài.
class MyNoteMarkdownView extends ConsumerStatefulWidget {
  const MyNoteMarkdownView({required this.source, super.key});

  final String source;

  @override
  ConsumerState<MyNoteMarkdownView> createState() => _MyNoteMarkdownViewState();
}

class _MyNoteMarkdownViewState extends ConsumerState<MyNoteMarkdownView> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String url) async {
    final opened = await ref.read(externalUrlLauncherProvider).open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được liên kết này.')),
      );
    }
  }

  TextSpan _span(List<MarkdownInline> inlines, TextStyle base) {
    return TextSpan(
      style: base,
      children: [
        for (final inline in inlines)
          switch (inline) {
            MarkdownText(:final text, :final bold, :final italic) => TextSpan(
              text: text,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : null,
                fontStyle: italic ? FontStyle.italic : null,
              ),
            ),
            MarkdownCode(:final text) => TextSpan(
              text: text,
              style: const TextStyle(
                fontFamily: 'monospace',
                backgroundColor: WebTuiColors.primarySoft,
              ),
            ),
            MarkdownLink(:final label, :final url) => TextSpan(
              text: label,
              style: const TextStyle(
                color: WebTuiColors.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: _recognizer(url),
            ),
          },
      ],
    );
  }

  TapGestureRecognizer _recognizer(String url) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => unawaited(_open(url));
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final blocks = parseMyNoteMarkdown(widget.source);
    final body = WebTuiTypography.bodyMedium.copyWith(
      color: WebTuiColors.textPrimary,
      height: 1.5,
    );
    final children = <Widget>[];
    for (final block in blocks) {
      children.add(_block(block, body));
    }
    return SelectionArea(
      child: Column(
        key: const Key('my_note_markdown_view'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _block(MarkdownBlock block, TextStyle body) {
    switch (block) {
      case MarkdownHeading(:final level, :final inlines):
        final style =
            switch (level) {
              1 => WebTuiTypography.titleLarge,
              2 => WebTuiTypography.titleMedium,
              _ => WebTuiTypography.bodyMedium,
            }.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w800,
            );
        return Padding(
          padding: const EdgeInsets.only(top: WebTuiSpacing.sm, bottom: 4),
          child: Text.rich(_span(inlines, style)),
        );
      case MarkdownParagraph(:final inlines):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(_span(inlines, body)),
        );
      case MarkdownBullet(:final inlines, :final depth):
        return _listRow(
          depth,
          Padding(
            padding: const EdgeInsets.only(top: 9, right: 8),
            child: Icon(
              depth == 0 ? Icons.circle : Icons.circle_outlined,
              size: 6,
              color: WebTuiColors.textSecondary,
            ),
          ),
          Text.rich(_span(inlines, body)),
        );
      case MarkdownNumbered(:final number, :final inlines, :final depth):
        return _listRow(
          depth,
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('$number.', style: body),
          ),
          Text.rich(_span(inlines, body)),
        );
      case MarkdownCheckbox(:final checked, :final inlines, :final depth):
        return _listRow(
          depth,
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Icon(
              checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              key: Key(checked ? 'md_checkbox_checked' : 'md_checkbox_open'),
              size: 20,
              color: checked
                  ? WebTuiColors.primary
                  : WebTuiColors.textSecondary,
            ),
          ),
          Text.rich(
            _span(
              inlines,
              checked
                  ? body.copyWith(
                      color: WebTuiColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    )
                  : body,
            ),
          ),
        );
      case MarkdownCodeBlock(:final code):
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
          padding: const EdgeInsets.all(WebTuiSpacing.sm),
          decoration: BoxDecoration(
            color: WebTuiColors.backgroundMuted,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: body.copyWith(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        );
    }
  }

  Widget _listRow(int depth, Widget marker, Widget content) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          marker,
          Expanded(child: content),
        ],
      ),
    );
  }
}
