import 'package:flutter/painting.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

/// Trên ngưỡng này (ký tự) thì không tô màu để khỏi giật (xem / sửa).
const ideHighlightMaxChars = 120000;

/// Tô màu mã bằng `re_highlight` (MIT). Chỉ nạp ngôn ngữ hay gặp để app nhỏ.
class IdeHighlighter {
  IdeHighlighter._();

  static final Highlight _hl = Highlight()
    ..registerLanguages({
      'bash': langBash,
      'c': langC,
      'cpp': langCpp,
      'csharp': langCsharp,
      'css': langCss,
      'dart': langDart,
      'dockerfile': langDockerfile,
      'go': langGo,
      'ini': langIni,
      'java': langJava,
      'javascript': langJavascript,
      'json': langJson,
      'kotlin': langKotlin,
      'makefile': langMakefile,
      'markdown': langMarkdown,
      'php': langPhp,
      'python': langPython,
      'ruby': langRuby,
      'rust': langRust,
      'scss': langScss,
      'sql': langSql,
      'swift': langSwift,
      'typescript': langTypescript,
      'xml': langXml,
      'yaml': langYaml,
    });

  static Map<String, TextStyle> _theme(bool dark) {
    final base = dark ? githubDarkTheme : githubTheme;
    // Bỏ 'root' (nền riêng của kiểu): nền do màn hình quyết định.
    return {
      for (final e in base.entries)
        if (e.key != 'root') e.key: e.value,
    };
  }

  /// Tô màu [code]; `null` nếu ngôn ngữ lạ, mã quá dài hoặc tô lỗi (khi đó
  /// vẽ chữ thường). Chữ ghép lại luôn bằng đúng [code].
  static TextSpan? highlight(
    String code,
    String language, {
    required TextStyle style,
    required bool dark,
  }) {
    if (language.isEmpty ||
        code.isEmpty ||
        code.length > ideHighlightMaxChars) {
      return null;
    }
    try {
      final result = _hl.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(style, _theme(dark));
      result.render(renderer);
      final span = renderer.span;
      if (span == null || span.toPlainText() != code) return null;
      return TextSpan(style: style, children: span.children, text: span.text);
    } on Object {
      return null;
    }
  }
}
