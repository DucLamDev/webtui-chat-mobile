import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_task_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../widgets/ide_wb.dart';
import 'ide_more_common.dart';
import 'ide_task_form.dart';

String ideTaskStatusLabel(String status) => switch (status) {
  'doing' => tr('Đang làm', 'In progress'),
  'done' => tr('Xong', 'Done'),
  _ => tr('Cần làm', 'To do'),
};

Color ideTaskStatusColor(String status) => switch (status) {
  'doing' => IdeWb.accentInk,
  'done' => IdeWb.ok,
  _ => IdeWb.text,
};

/// Việc cần làm: của tôi hoặc theo dự án, lọc trạng thái, thêm việc.
class IdeTasksScreen extends ConsumerStatefulWidget {
  const IdeTasksScreen({this.project, super.key});

  /// `project` trên đường dẫn; có thì mở sẵn chế độ theo dự án.
  final String? project;

  @override
  ConsumerState<IdeTasksScreen> createState() => _IdeTasksScreenState();
}

class _IdeTasksScreenState extends ConsumerState<IdeTasksScreen> {
  late bool _mine = widget.project == null || widget.project!.isEmpty;
  int _filter = 0; // 0 tất cả, 1..3 theo ideTaskStatuses

  @override
  Widget build(BuildContext context) {
    final chips = [
      WebTuiFilterChipData(label: tr('Tất cả', 'All')),
      for (final s in ideTaskStatuses)
        WebTuiFilterChipData(label: ideTaskStatusLabel(s)),
    ];
    return IdeMorePage(
      title: tr('Việc cần làm', 'Tasks'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              0,
            ),
            child: WebTuiSegmentedTabs(
              key: const Key('ide_tasks_scope'),
              tabs: [tr('Của tôi', 'Mine'), tr('Theo dự án', 'By project')],
              selectedIndex: _mine ? 0 : 1,
              onChanged: (i) => setState(() => _mine = i == 0),
            ),
          ),
          WebTuiFilterChipBar(
            chips: chips,
            selectedIndex: _filter,
            onSelected: (i) => setState(() => _filter = i),
            semanticLabel: tr('Lọc trạng thái', 'Filter by status'),
          ),
          Expanded(
            child: _mine
                ? _TasksLoader(
                    key: const ValueKey('mine'),
                    mine: true,
                    status: _filter == 0 ? null : ideTaskStatuses[_filter - 1],
                  )
                : IdeProjectScope(
                    initial: widget.project,
                    builder: (context, p) => _TasksLoader(
                      key: ValueKey('p:${p.name}'),
                      project: p.name,
                      status: _filter == 0
                          ? null
                          : ideTaskStatuses[_filter - 1],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TasksLoader extends ConsumerWidget {
  const _TasksLoader({this.mine = false, this.project, this.status, super.key});

  final bool mine;
  final String? project;
  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(ideMoreServiceProvider);
    return IdeLoader<IdeTaskList>(
      load: () => service.tasks(project: project, mine: mine),
      builder: (context, list, reload) => _TaskListView(
        list: list,
        reload: reload,
        status: status,
        showProject: mine,
        defaultProject: project,
      ),
    );
  }
}

class _TaskListView extends ConsumerWidget {
  const _TaskListView({
    required this.list,
    required this.reload,
    required this.status,
    required this.showProject,
    this.defaultProject,
  });

  final IdeTaskList list;
  final Future<void> Function() reload;
  final String? status;
  final bool showProject;
  final String? defaultProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = filterAndSortTasks(list.tasks, status);
    final selected = ref.watch(ideSelectedProjectNameProvider);
    final canAdd = list.projects.isNotEmpty;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: reload,
          child: tasks.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 320,
                      child: WebTuiEmptyState(
                        title: tr('Chưa có việc nào', 'No tasks'),
                        message: status == null
                            ? tr(
                                'Chưa có việc nào ở đây. Bấm "Thêm việc" để tạo.',
                                'Nothing here yet. Tap "Add task".',
                              )
                            : tr(
                                'Không có việc nào ở trạng thái này.',
                                'No tasks in this status.',
                              ),
                        icon: Icons.task_alt_rounded,
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  key: const Key('ide_tasks_list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    WebTuiSpacing.lg,
                    WebTuiSpacing.sm,
                    WebTuiSpacing.lg,
                    96,
                  ),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: WebTuiSpacing.sm),
                  itemBuilder: (context, i) => IdeTaskCard(
                    task: tasks[i],
                    showProject: showProject,
                    onTap: () async {
                      await context.push('/ide/tasks/${tasks[i].id}');
                      if (context.mounted) await reload();
                    },
                  ),
                ),
        ),
        if (canAdd)
          Positioned(
            right: WebTuiSpacing.lg,
            bottom: WebTuiSpacing.lg,
            child: FloatingActionButton.extended(
              key: const Key('ide_task_add'),
              onPressed: () async {
                final saved = await showIdeTaskForm(
                  context,
                  list: list,
                  defaultProject: defaultProject ?? selected,
                );
                if (saved) await reload();
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Thêm việc', 'Add task')),
            ),
          ),
      ],
    );
  }
}

class IdeTaskCard extends StatelessWidget {
  const IdeTaskCard({
    required this.task,
    required this.onTap,
    this.showProject = false,
    super.key,
  });

  final IdeTask task;
  final VoidCallback onTap;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final due = task.due;
    final state = ideDueState(due, DateTime.now(), done: task.isDone);
    final dueColor = switch (state) {
      IdeDueState.overdue => IdeWb.danger,
      IdeDueState.today || IdeDueState.soon => IdeWb.warn,
      _ => IdeWb.text2,
    };
    return IdeCard(
      key: Key('ide_task_${task.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ideVisibleText(task.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: IdeType.titleMedium.copyWith(
              color: IdeWb.textStrong,
              decoration: task.isDone ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IdeTag(
                ideTaskStatusLabel(task.status),
                color: ideTaskStatusColor(task.status),
              ),
              if (due != null)
                IdeTag(
                  state == IdeDueState.overdue
                      ? '${tr('Quá hạn', 'Overdue')} ${ideDueDisplay(due)}'
                      : '${tr('Hạn', 'Due')} ${ideDueDisplay(due)}',
                  color: dueColor,
                ),
              if (task.assignee.isNotEmpty ||
                  (showProject && task.project.isNotEmpty))
                Text(
                  [
                    if (task.assignee.isNotEmpty) ideVisibleText(task.assignee),
                    if (showProject && task.project.isNotEmpty)
                      ideVisibleText(task.project),
                  ].join(' · '),
                  style: IdeType.bodySmall.copyWith(color: IdeWb.text),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
