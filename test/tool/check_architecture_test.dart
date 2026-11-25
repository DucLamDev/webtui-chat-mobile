import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Chạy công cụ thật trên một cây `lib/` tạm.
Future<ProcessResult> _check(Map<String, String> files) async {
  final root = Directory.systemTemp.createTempSync('check-arch-');
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((path, content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  });
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final dart = flutterRoot == null
      ? 'dart'
      : '$flutterRoot/bin/cache/dart-sdk/bin/dart';
  return Process.run(dart, [
    File('tool/check_architecture.dart').absolute.path,
  ], workingDirectory: root.path);
}

void main() {
  const webView =
      "import 'package:webview_flutter/webview_flutter.dart';\nclass A {}\n";

  test('WebView chỉ được import ở một tệp', () async {
    final ok = await _check({
      'lib/features/ide_web/data/webview_flutter_ide_view.dart': webView,
    });
    expect(ok.exitCode, 0, reason: '${ok.stderr}');

    for (final path in [
      'lib/features/ide_web/presentation/screens/a.dart',
      'lib/features/ide_web/data/b.dart',
      'lib/core/c.dart',
    ]) {
      final bad = await _check({path: webView});
      expect(bad.exitCode, 1, reason: path);
      expect('${bad.stderr}', contains('webview_flutter'));
    }
    final platform = await _check({
      'lib/core/d.dart':
          "import 'package:webview_flutter_android/webview_flutter_android.dart';",
    });
    expect(platform.exitCode, 1);
  });

  test('luật cũ vẫn chặn Dio ở presentation', () async {
    final bad = await _check({
      'lib/features/x/presentation/a.dart': "import 'package:dio/dio.dart';",
    });
    expect(bad.exitCode, 1);
  });
}
