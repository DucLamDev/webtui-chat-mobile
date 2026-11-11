import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_stream_merger.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_cards/streaming_message_bubble.dart';

void main() {
  group('giấu khối thẻ AI khi đang chạy dần', () {
    test('không có khối thì giữ nguyên', () {
      const body = 'Xin chào\n```bash\nls\n```';
      expect(visibleStreamingText(body), (text: body, drawing: false));
    });

    test('giấu từ dòng mở khối trở đi', () {
      expect(
        visibleStreamingText('Biểu đồ đây:\n\n```webtui-card\n{"version":2,'),
        (text: 'Biểu đồ đây:', drawing: true),
      );
      expect(visibleStreamingText('A\n  ```webtui-card  \n{}\n```\nB'), (
        text: 'A',
        drawing: true,
      ));
    });

    test('dòng mở khối đang gõ dở thì giấu tạm', () {
      expect(visibleStreamingText('A\n```webtui-'), (text: 'A', drawing: true));
      expect(visibleStreamingText('A\n```'), (text: 'A\n```', drawing: false));
      expect(visibleStreamingText('A\n```py'), (
        text: 'A\n```py',
        drawing: false,
      ));
    });
  });

  testWidgets('bong bóng ghi "Đang vẽ…" và không lộ JSON', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreamingMessageBubble(
            text: 'Doanh thu quý 1:\n```webtui-card\n{"version":2,"title"',
            timeLabel: '10:30',
          ),
        ),
      ),
    );
    expect(find.textContaining('Doanh thu quý 1:'), findsOneWidget);
    expect(find.textContaining('webtui-card'), findsNothing);
    expect(find.textContaining('"version"'), findsNothing);
    expect(find.text('10:30 · Đang vẽ…'), findsOneWidget);
  });

  testWidgets('chỉ có khối thì hiện "Đang vẽ…"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreamingMessageBubble(
            text: '```webtui-card\n{',
            timeLabel: '10:30',
          ),
        ),
      ),
    );
    expect(find.text('Đang vẽ…'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
  });
}
