import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/platform/external_url_launcher.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/workspace_tools_screen.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_notes_access_provider.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/work_hub_providers.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/meetings_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/my_tasks_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/shared_files_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/shortcuts_manage_screen.dart';

import '../work_hub_fakes.dart';

final class FakeLauncher implements ExternalUrlLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

/// Dựng một màn bằng router thật nhỏ: `/` là màn kiểm thử, các route con của
/// tab Công việc dùng màn thật, route khác chỉ hiện chữ để biết đã tới đâu.
Widget workHubApp({
  required FakeWorkHubRepository repository,
  required FakeTaskRepository tasks,
  Widget home = const Scaffold(body: WorkspaceToolsScreen(workspaceId: 'ws')),
  bool workHub = true,
  bool myNotes = true,
  FakeLauncher? launcher,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final router = GoRouter(
    navigatorKey: navigatorKey,
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/my-tasks',
        builder: (_, state) => MyTasksScreen(
          workspaceId: 'ws',
          startWithSearch: state.uri.queryParameters['search'] == '1',
        ),
      ),
      GoRoute(
        path: '/meetings',
        builder: (_, _) => const MeetingsScreen(workspaceId: 'ws'),
      ),
      GoRoute(
        path: '/files',
        builder: (_, _) => const SharedFilesScreen(workspaceId: 'ws'),
      ),
      GoRoute(
        path: '/shortcuts',
        builder: (_, _) => const ShortcutsManageScreen(workspaceId: 'ws'),
      ),
      GoRoute(
        path: '/my-notes',
        builder: (_, _) => const Scaffold(body: Text('màn My Note')),
      ),
      GoRoute(
        path: '/conversations/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'kênh ${state.pathParameters['id']} '
            '${state.uri.queryParameters['tool']} '
            '${state.uri.queryParameters['taskId']}',
          ),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      workHubRepositoryProvider.overrideWithValue(repository),
      collaborationTaskRepositoryProvider.overrideWithValue(tasks),
      workHubEnabledProvider.overrideWithValue(workHub),
      myNotesEnabledProvider.overrideWithValue(myNotes),
      externalUrlLauncherProvider.overrideWithValue(launcher ?? FakeLauncher()),
    ],
    child: MaterialApp.router(theme: WebTuiTheme.light(), routerConfig: router),
  );
}
