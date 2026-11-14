import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_card.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_cards/message_card_view.dart';

import 'fake_rich_message_repository.dart';

const _ws = '11111111-1111-4111-8111-111111111111';
const _ch = '22222222-2222-4222-8222-222222222222';
const _task = '33333333-3333-4333-8333-333333333333';

Future<void> _pump(
  WidgetTester tester, {
  required FakeRichMessageRepository repository,
  required void Function(String) onPush,
}) async {
  final card = parseMessageCard({
    'version': 2,
    'title': 'Bạn được giao việc mới',
    'status': 'info',
    'actions': [
      {
        'type': 'open',
        'label': 'Mở việc',
        'tone': 'primary',
        'target': {
          'target_type': 'task',
          'workspace_id': _ws,
          'channel_id': _ch,
          'task_id': _task,
        },
      },
      {
        'type': 'callback',
        'label': 'Tắt báo loại này',
        'action_id': 'notice-mute',
      },
    ],
  })!;
  final message = ChatMessage(
    id: 'm1',
    workspaceId: _ws,
    channelId: _ch,
    kind: 'bot',
    body: 'Bạn được giao việc',
    createdAt: DateTime.utc(2026, 11),
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: MessageCardView(
              message: message,
              card: card,
              timeLabel: '10:00',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/conversations/:id',
        builder: (_, state) {
          onPush(state.uri.toString());
          return const Scaffold(body: Text('phòng chat'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        richMessageRepositoryProvider.overrideWithValue(repository),
        richCardsEnabledProvider.overrideWithValue(true),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nút Mở việc điều hướng, không gọi máy chủ', (tester) async {
    final repository = FakeRichMessageRepository();
    final pushed = <String>[];
    await _pump(tester, repository: repository, onPush: pushed.add);

    await tester.tap(find.text('Mở việc'));
    await tester.pumpAndSettle();

    expect(pushed.single, contains('/conversations/$_ch'));
    expect(pushed.single, contains('tool=tasks'));
    expect(pushed.single, contains('taskId=$_task'));
    expect(repository.invoked, isEmpty);
  });

  testWidgets('nút open vẫn hiện khi máy chủ chưa bật thẻ bản 2', (
    tester,
  ) async {
    final card = parseMessageCard({
      'version': 2,
      'title': 'Thẻ',
      'actions': [
        {
          'type': 'open',
          'label': 'Mở việc',
          'target': {'target_type': 'contacts'},
        },
        {'type': 'callback', 'label': 'Tắt', 'action_id': 'notice-mute'},
      ],
    })!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [richCardsEnabledProvider.overrideWithValue(false)],
        child: MaterialApp(
          home: Scaffold(
            body: MessageCardView(
              message: ChatMessage(
                id: 'm',
                workspaceId: _ws,
                channelId: _ch,
                kind: 'bot',
                body: '',
                createdAt: DateTime.utc(2026, 11),
              ),
              card: card,
              timeLabel: '10:00',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Mở việc'), findsOneWidget);
    expect(find.text('Tắt'), findsNothing);
  });

  testWidgets('lỗi nút callback hiện dòng đỏ dưới hàng nút, bấm lại được', (
    tester,
  ) async {
    final repository = FakeRichMessageRepository(
      invokeError: 'Việc này đã được xử lý.',
    );
    await _pump(tester, repository: repository, onPush: (_) {});

    await tester.tap(find.text('Tắt báo loại này'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message_card_action_error')), findsOneWidget);
    expect(find.text('Việc này đã được xử lý.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('Tắt báo loại này'));
    await tester.pumpAndSettle();
    expect(repository.invoked, ['notice-mute', 'notice-mute']);
  });
}
