import 'package:flutter/material.dart';

import '../../../application/ide_highlighter.dart';
import 'ide_code_view.dart';

/// Ô sửa mã: tô màu nhẹ theo ngôn ngữ (nhớ kết quả, chỉ tô lại khi chữ đổi;
/// quá dài thì để chữ thường).
class IdeCodeController extends TextEditingController {
  IdeCodeController({super.text, this.language = ''});

  final String language;
  String? _cachedFor;
  bool? _cachedDark;
  TextSpan? _cached;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? ideCodeStyle();
    final dark = ideIsDarkNow();
    final t = text;
    // Đang gõ tiếng Việt (có vùng soạn): để chữ thường, tránh nhấp nháy.
    if (language.isEmpty || (withComposing && value.composing.isValid)) {
      return super.buildTextSpan(
        context: context,
        style: base,
        withComposing: withComposing,
      );
    }
    if (_cachedFor != t || _cachedDark != dark) {
      _cached = IdeHighlighter.highlight(t, language, style: base, dark: dark);
      _cachedFor = t;
      _cachedDark = dark;
    }
    return _cached ?? TextSpan(text: t, style: base);
  }
}
