import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_project.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_more_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_project_controllers.dart';

import 'rpc_env.dart';

const ideTestProjects = [
  IdeProject(name: 'web', root: '/srv/web', label: 'Web chính', branch: 'main'),
  IdeProject(name: 'my:blog', root: '/srv/blog', my: true),
];

/// Dựng một màn của tab Thêm với rpc giả, danh sách dự án giả và router thật
/// (có sẵn đường dẫn con để bắt `context.push`).
Future<IdeRpcEnv> pumpMore(
  WidgetTester tester,
  Widget screen,
  IdeFakeHandler handler, {
  Set<String>? ops,
  List<IdeProject> projects = ideTestProjects,
  List<String>? pushed,
  IdeDatePicker? datePicker,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 1000);
  addTearDown(tester.view.reset);
  WebTuiColors.apply(brightness);
  final env = IdeRpcEnv(handler, ops: ops?.toList());
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/ide/tasks/:id',
        builder: (_, state) {
          pushed?.add(state.uri.toString());
          return const Scaffold(body: Text('chi tiết việc'));
        },
      ),
      GoRoute(
        path: '/ide/:page',
        builder: (_, state) {
          pushed?.add(state.uri.toString());
          return const Scaffold(body: Text('màn con'));
        },
      ),
      GoRoute(
        path: '/ide/notes/:id',
        builder: (_, state) {
          pushed?.add(state.uri.toString());
          return const Scaffold(body: Text('chi tiết ghi chú'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideRpcClientProvider.overrideWithValue(env.rpc),
        ideProjectsProvider.overrideWith((ref) async => projects),
        ideLinkStatusProvider.overrideWith(
          (ref) => Stream.value(
            IdeLinkStatus(
              IdeLinkPhase.ready,
              ready: IdeReady(ops: ops ?? const {}),
            ),
          ),
        ),
        if (datePicker != null)
          ideDatePickerProvider.overrideWithValue(datePicker),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? WebTuiTheme.dark()
            : WebTuiTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await settle(tester, 4);
  return env;
}

/// Các lần gọi `op` đã gửi (kèm tham số).
List<Map<String, Object?>> sentOps(IdeRpcEnv env, String op) => [
  for (final f in env.lastSocket!.sentOfType('op'))
    if (f['op'] == op) Map<String, Object?>.from(f['args']! as Map),
];
