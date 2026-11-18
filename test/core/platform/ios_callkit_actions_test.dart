import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Thân hàm Swift `func <name>(...) { ... }` (không lồng ngoặc nhọn).
String _swiftFunctionBody(String source, String name) {
  final match = RegExp(
    'func $name\\([^)]*\\)\\s*\\{([^{}]*)\\}',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'Không tìm thấy hàm $name');
  return match!.group(1)!;
}

void main() {
  test('AppDelegate fulfill lệnh Nghe / Từ chối / Kết thúc của CallKit '
      '(plugin giao việc này cho CallkitIncomingAppDelegate)', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('CallkitIncomingAppDelegate'));
    // Không fulfill lệnh Nghe thì CallKit không mở audio session: bấm Nghe ở
    // màn hình khoá mà không nghe thấy gì.
    for (final name in const ['onAccept', 'onDecline', 'onEnd']) {
      expect(
        _swiftFunctionBody(appDelegate, name),
        contains('action.fulfill()'),
        reason: '$name phải gọi action.fulfill()',
      );
    }

    final plugin = File(
      'third_party/flutter_callkit_incoming/ios/flutter_callkit_incoming/'
      'Classes/SwiftFlutterCallkitIncomingPlugin.swift',
    ).readAsBytesSync();
    // Plugin chỉ tự fulfill khi AppDelegate KHÔNG nhận việc này; đổi bản
    // plugin thì xem lại hàm trên.
    expect(
      String.fromCharCodes(plugin),
      contains('appDelegate.onAccept(call, action)'),
    );
  });
}
