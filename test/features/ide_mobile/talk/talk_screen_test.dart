import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_talk_screen.dart';

import '../support/rpc_env.dart';

const id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  testWidgets('màn chat: tin, truncated_before, chữ 1.6x không tràn', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(411, 900);
    addTearDown(t.view.reset);
    WebTuiColors.apply(Brightness.light);
    final env = IdeRpcEnv(
      (op, a) => <String, Object?>{},
      ops: ['talk.send', 'talk.share', 'talk.stop'],
    );
    addTearDown(() => t.runAsync(env.dispose));
    await t.runAsync(env.up);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ideRpcClientProvider.overrideWithValue(env.rpc),
          ideConnectionProvider.overrideWithValue(env.connection),
          ideLinkStatusProvider.overrideWith(
            (ref) => Stream.value(
              const IdeLinkStatus(
                IdeLinkPhase.ready,
                ready: IdeReady(ops: {'talk.send', 'talk.share', 'talk.stop'}),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: w!,
          ),
          home: const IdeTalkScreen(talkId: id),
        ),
      ),
    );
    await settle(t);
    env.lastSocket!.emit({
      'type': 'talk_delta',
      'id': id,
      'title': 'Họp tuần',
      'truncated_before': 7,
      'messages': [
        {'id': '1', 'role': 'user', 'text': 'Xin chào'},
        {'id': '2', 'role': 'assistant', 'text': 'Chào **bạn**'},
      ],
    });
    await settle(t);
    expect(find.text('Xin chào'), findsOneWidget);
    expect(find.byKey(const Key('talk_truncated')), findsOneWidget);
    expect(find.byKey(const Key('talk_input')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
