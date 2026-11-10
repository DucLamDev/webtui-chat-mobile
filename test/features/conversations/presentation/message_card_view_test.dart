import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_card.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_cards/message_card_view.dart';

void main() {
  test('Dữ liệu thẻ hỏng hoặc quá cỡ trả về tin thường', () {
    for (final value in [
      null,
      [],
      'x',
      {'version': 3, 'title': 'Sai'},
      {'version': 2},
      {'version': 2, 'title': 'x' * 70000},
    ]) {
      expect(parseMessageCard(value), isNull);
    }
  });
  for (final theme in [ThemeData.light(), ThemeData.dark()]) {
    testWidgets(
      'Thẻ rỗng và thẻ lỗi an toàn trên màn hẹp ${theme.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final card = parseMessageCard({
          'version': 2,
          'title': 'Báo cáo',
          'sections': [
            {
              'type': 'chart',
              'chart': {'kind': 'bar', 'labels': [], 'series': []},
            },
            {
              'type': 'table',
              'table': {
                'columns': ['Tên'],
                'rows': [],
              },
            },
            {
              'type': 'diagram',
              'diagram': {'nodes': [], 'edges': []},
            },
            {
              'type': 'plan',
              'plan': {'steps': []},
            },
            {'type': 'chart', 'chart': 'hỏng'},
          ],
        })!;
        final message = ChatMessage(
          id: 'm',
          workspaceId: 'w',
          channelId: 'c',
          kind: 'bot',
          body: 'Báo cáo',
          createdAt: DateTime(2026),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [richCardsEnabledProvider.overrideWithValue(false)],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MessageCardView(
                    message: message,
                    card: card,
                    timeLabel: '10:00',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Báo cáo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
