import 'package:go_router/go_router.dart';

import '../../../domain/ide_note_models.dart';
import '../../../domain/ide_task_models.dart';
import '../../widgets/ide_access_gate.dart';
import 'ide_ailog_screen.dart';
import 'ide_changelog_screen.dart';
import 'ide_kientruc_screen.dart';
import 'ide_more_common.dart';
import 'ide_note_screen.dart';
import 'ide_notes_screen.dart';
import 'ide_oplog_screen.dart';
import 'ide_report_screen.dart';
import 'ide_task_detail_screen.dart';
import 'ide_tasks_screen.dart';

String? _project(GoRouterState s) {
  final p = s.uri.queryParameters['project'];
  return p == null || p.isEmpty ? null : p;
}

/// Đường dẫn của tab Thêm (hợp đồng GĐ3); mỗi màn bọc cổng vân tay.
List<GoRoute> ideMoreRoutes() => [
  GoRoute(
    path: '/ide/tasks',
    name: 'ide-tasks',
    builder: (context, state) =>
        IdeAccessGate(child: IdeTasksScreen(project: _project(state))),
  ),
  GoRoute(
    path: '/ide/tasks/:id',
    name: 'ide-task',
    builder: (context, state) {
      final id = state.pathParameters['id'];
      return IdeAccessGate(
        child: isIdeTaskId(id)
            ? IdeTaskDetailScreen(taskId: id!)
            : const IdeMoreNotFoundScreen(),
      );
    },
  ),
  GoRoute(
    path: '/ide/notes',
    name: 'ide-notes',
    builder: (context, state) =>
        IdeAccessGate(child: IdeNotesScreen(project: _project(state))),
  ),
  // Đặt trước `/ide/notes/:id` để "new" không bị hiểu là mã ghi chú.
  GoRoute(
    path: '/ide/notes/new',
    name: 'ide-note-new',
    builder: (context, state) {
      final project = _project(state);
      return IdeAccessGate(
        child: project != null
            ? IdeNoteScreen(project: project)
            : const IdeMoreNotFoundScreen(),
      );
    },
  ),
  GoRoute(
    path: '/ide/notes/:id',
    name: 'ide-note',
    builder: (context, state) {
      final id = state.pathParameters['id'];
      final project = _project(state);
      return IdeAccessGate(
        child: isIdeNoteId(id) && project != null
            ? IdeNoteScreen(project: project, noteId: id)
            : const IdeMoreNotFoundScreen(),
      );
    },
  ),
  GoRoute(
    path: '/ide/oplog',
    name: 'ide-oplog',
    builder: (context, state) =>
        IdeAccessGate(child: IdeOplogScreen(project: _project(state))),
  ),
  GoRoute(
    path: '/ide/ailog',
    name: 'ide-ailog',
    builder: (context, state) =>
        IdeAccessGate(child: IdeAiLogScreen(project: _project(state))),
  ),
  GoRoute(
    path: '/ide/report',
    name: 'ide-report',
    builder: (context, state) =>
        IdeAccessGate(child: IdeReportScreen(project: _project(state))),
  ),
  GoRoute(
    path: '/ide/kientruc',
    name: 'ide-kientruc',
    builder: (context, state) =>
        IdeAccessGate(child: IdeKientrucScreen(project: _project(state))),
  ),
  GoRoute(
    path: '/ide/changelog',
    name: 'ide-changelog',
    builder: (context, state) =>
        const IdeAccessGate(child: IdeChangelogScreen()),
  ),
];
