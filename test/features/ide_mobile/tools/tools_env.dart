import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_project_controllers.dart';

import '../support/more_env.dart';
import '../support/rpc_env.dart';

export '../support/more_env.dart' show ideTestProjects, sentOps;
export '../support/rpc_env.dart';

/// Như `pumpMore` nhưng có `/ide/jobs/:id`, bước vân tay và ghi đè tuỳ ý.
Future<IdeRpcEnv> pumpTool(
  WidgetTester tester,
  Widget screen,
  IdeFakeHandler handler, {
  required Set<String> ops,
  IdeStepHandler? step,
  List<String>? pushed,
  List<Override> overrides = const [],
  double textScale = 1,
  Size size = const Size(411, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  WebTuiColors.apply(Brightness.light);
  final env = IdeRpcEnv(handler, ops: ops.toList(), step: step);
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/ide/jobs/:id',
        builder: (_, state) {
          pushed?.add(state.uri.toString());
          return const Scaffold(body: Text('màn việc'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideRpcClientProvider.overrideWithValue(env.rpc),
        ideProjectsProvider.overrideWith((ref) async => ideTestProjects),
        ideLinkStatusProvider.overrideWith(
          (ref) => Stream.value(
            IdeLinkStatus(IdeLinkPhase.ready, ready: IdeReady(ops: ops)),
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: WebTuiTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await settle(tester, 4);
  return env;
}

/// Gửi `need_step` cho lần gọi cuối rồi trả về mã yêu cầu.
Future<Object?> emitNeedStep(WidgetTester tester, IdeRpcEnv env) async {
  final req = env.lastSocket!.sentOfType('op').last['req'];
  env.lastSocket!.emit({
    'type': 'need_step',
    'req': req,
    'challenge': 'Y2g=',
    'summary': 'x',
  });
  await settle(tester);
  return req;
}

/// Cho tin giả tới nơi rồi chạy hết hoạt ảnh.
Future<void> settleAll(WidgetTester tester) async {
  await settle(tester);
  await tester.pumpAndSettle();
}
