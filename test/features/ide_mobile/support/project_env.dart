import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/platform/external_url_launcher.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_controllers.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/controllers/ide_project_ops_controllers.dart';

import 'rpc_env.dart';

/// Mọi op GĐ3 mà test dùng (IDE giả báo đủ).
const ideProjectTestOps = [
  'projects.list',
  'projects.info',
  'git.status',
  'git.log',
  'pr.create',
  'git.merge',
  'mergeq.view',
  'mergeq.mine',
  'mergeq.mode',
  'mergeq.log',
  'mergeq.withdraw',
  'mergeq.light_list',
  'mergeq.light_clear',
  'deploy.preview',
  'deploy.run',
  'deploy.pull',
  'deploy.history',
  'deploy.rollback',
  'deploy.restore',
  'my.preview',
  'my.sync',
  'my.deploy',
  'my.pull',
  'my.history',
  'my.rollback',
  'my.restore',
  'to_git.check',
  'to_git.apply',
  'targets.show',
  'targets.set',
  'targets.remove',
  'targets.auto',
  'term.targets',
  'vps.request',
  'vps.requests',
  'jobs.list',
  'jobs.tail',
];

Map<String, Object?> proj(
  String name, {
  String kind = 'git',
  bool? my,
  List<Map<String, Object?>>? targets,
  Map<String, Object?>? can,
}) => {
  'name': name,
  'root': '/srv/$name',
  'kind': kind,
  'my': ?my,
  'targets': ?targets,
  'can': ?can,
};

/// Đồng hồ giả cho hạn 15 phút.
final class TestClock {
  DateTime now = DateTime(2026, 11, 19, 10);
  DateTime call() => now;
}

final class ProjectHarness {
  ProjectHarness(this.env, this.clock, this.router);

  final IdeRpcEnv env;
  final TestClock clock;
  final GoRouter router;
  final launched = <String>[];
}

final class _FakeLauncher implements ExternalUrlLauncher {
  _FakeLauncher(this.urls);
  final List<String> urls;

  @override
  Future<bool> open(String url) async {
    urls.add(url);
    return true;
  }
}

/// Dựng [home] trong router thật; `/ide/jobs/:id` và `/ide/mergeq` hiện chữ.
Future<ProjectHarness> pumpProject(
  WidgetTester tester,
  IdeFakeHandler handler,
  Widget home, {
  List<String> ops = ideProjectTestOps,
  IdeStepHandler? step,
  Brightness brightness = Brightness.light,
  IdeLinkPhase phase = IdeLinkPhase.ready,
  List<Override> overrides = const [],
  bool settleNow = true,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  WebTuiColors.apply(brightness);
  final env = IdeRpcEnv(handler, ops: ops, step: step);
  addTearDown(() => tester.runAsync(env.dispose));
  await tester.runAsync(env.up);
  final clock = TestClock();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/ide/jobs/:id',
        builder: (_, s) =>
            Scaffold(body: Text('JOB ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/ide/mergeq',
        builder: (_, s) => Scaffold(body: Text('MERGEQ ${s.uri.query}')),
      ),
      GoRoute(
        path: '/ide/deploy',
        builder: (_, s) => Scaffold(body: Text('DEPLOY ${s.uri.query}')),
      ),
    ],
  );
  final h = ProjectHarness(env, clock, router);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideRpcClientProvider.overrideWithValue(env.rpc),
        ideLinkStatusProvider.overrideWith(
          (ref) => Stream.value(
            IdeLinkStatus(phase, ready: IdeReady(ops: ops.toSet())),
          ),
        ),
        ideProjectPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
        ideProjectNowProvider.overrideWithValue(clock.call),
        externalUrlLauncherProvider.overrideWithValue(
          _FakeLauncher(h.launched),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: brightness == Brightness.dark
            ? WebTuiTheme.dark()
            : WebTuiTheme.light(),
      ),
    ),
  );
  if (settleNow) await pumpFor(tester);
  return h;
}

/// Cho tin giả tới nơi và hẹn giờ ngắn chạy xong.
Future<void> pumpFor(WidgetTester tester, [int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Bản xem trước chuẩn mẫu.
Map<String, Object?> previewResult({
  String target = 'prod',
  bool deleteMany = false,
  List<Map<String, Object?>>? files,
}) => {
  'project': 'web',
  'target': target,
  'kind': 'vps',
  'sha': 'abcdef1234567890',
  'subject': 'Sửa trang chủ',
  'base': {'commit': '1111111222', 'at': 1, 'by': 'an', 'subject': 'Bản cũ'},
  'files':
      files ??
      [
        {'s': 'A', 'path': 'src/moi.php'},
        {'s': 'M', 'path': 'src/cu.php'},
        {'s': 'N', 'path': 'src/may-chu.php'},
        {'s': 'D', 'path': 'src/xoa.php'},
      ],
  'total': 4,
  'truncated': false,
  'diff': '+dòng mới\n-dòng cũ',
  'warnings': ['Máy chủ có tệp mới hơn'],
  'delete_many': deleteMany,
};
