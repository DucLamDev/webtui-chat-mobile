import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/platform/external_url_launcher.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/markdown/ide_markdown.dart';

class _Launcher implements ExternalUrlLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

const _bad = [
  'javascript:alert(1)',
  'JavaScript:alert(document.cookie)',
  ' javascript:alert(1)',
  'file:///etc/passwd',
  'file:///data/data/app/shared_prefs/x.xml',
  'intent://scan/#Intent;scheme=zxing;package=com.evil;end',
  'intent:#Intent;action=android.settings.SETTINGS;end',
  'data:text/html,<script>alert(1)</script>',
  'content://com.android.contacts/contacts',
  'tel:+84000000000',
  'webtui://ide/pair',
];

void main() {
  testWidgets('markdown IDE: liên kết javascript:, file:, intent:... bị chặn', (
    tester,
  ) async {
    for (final url in _bad) {
      final launcher = _Launcher();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebTuiTheme.light(),
          home: Scaffold(
            body: IdeMarkdown(text: 'Xem [bấm]($url) nhé', launcher: launcher),
          ),
        ),
      );
      final spans = <TextSpan>[];
      void walk(InlineSpan s) {
        if (s is! TextSpan) return;
        spans.add(s);
        s.children?.forEach(walk);
      }

      for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
        walk(r.text);
      }
      for (final s in spans.where((s) => s.recognizer != null)) {
        (s.recognizer! as TapGestureRecognizer).onTap!();
      }
      await tester.pumpAndSettle();
      expect(find.text('Mở liên kết?'), findsNothing, reason: url);
      expect(launcher.opened, isEmpty, reason: url);
    }
  });

  test('trình mở liên kết ngoài chỉ gửi http(s) xuống máy', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('webtui/launcher');
    final sent = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call.arguments);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const launcher = MethodChannelExternalUrlLauncher();
    for (final url in _bad) {
      expect(await launcher.open(url), isFalse, reason: url);
    }
    expect(sent, isEmpty);
    expect(await launcher.open('https://example.com/a'), isTrue);
    expect(sent, hasLength(1));
  });
}
