import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/workspace_tools_screen.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/workspace_modules.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_notes_access_provider.dart';

void main() {
  Widget app({required bool myNotes, List<Override> extra = const []}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: WorkspaceToolsScreen(workspaceId: 'workspace-1'),
          ),
        ),
        GoRoute(
          path: '/my-notes',
          builder: (_, state) =>
              Text('ghi chú ${state.uri.queryParameters['workspaceId']}'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [myNotesEnabledProvider.overrideWithValue(myNotes), ...extra],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('chỉ hiện My Note, không còn Việc của tôi / lưới công cụ', (
    tester,
  ) async {
    await tester.pumpWidget(app(myNotes: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workspace_module_my_notes')), findsOneWidget);
    expect(find.text('My Note'), findsOneWidget);
    expect(find.byKey(const Key('my_tasks_section')), findsNothing);
    for (final text in [
      'Việc của tôi',
      'Họp nhóm',
      'Đã chia sẻ',
      'Ghi chú chung',
      'Bảng trắng',
      'Tất cả công cụ',
    ]) {
      expect(find.text(text), findsNothing);
    }

    await tester.tap(find.byKey(const Key('workspace_module_my_notes')));
    await tester.pumpAndSettle();
    expect(find.text('ghi chú workspace-1'), findsOneWidget);
  });

  testWidgets('My Note bị tắt: hiện trạng thái rỗng rõ ràng', (tester) async {
    await tester.pumpWidget(app(myNotes: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workspace_tools_empty')), findsOneWidget);
    expect(find.textContaining('Chưa có tiện ích nào được bật'), findsWidgets);
    expect(find.byKey(const Key('workspace_module_my_notes')), findsNothing);
  });

  testWidgets('tiện ích đăng ký thêm và bật thì hiện cạnh My Note', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        myNotes: true,
        extra: [
          workspaceModulesProvider.overrideWithValue([
            WorkspaceModule(
              id: 'mini_app',
              title: 'Mini app',
              description: 'Thử nghiệm',
              icon: Icons.apps_rounded,
              routeFor: (id) => '/mini?workspaceId=$id',
              enabled: true,
            ),
            WorkspaceModule(
              id: 'ide',
              title: 'IDE',
              description: 'Chưa bật',
              icon: Icons.code_rounded,
              routeFor: (id) => '/ide',
              enabled: false,
            ),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workspace_module_mini_app')), findsOneWidget);
    expect(find.byKey(const Key('workspace_module_ide')), findsNothing);
  });
}
