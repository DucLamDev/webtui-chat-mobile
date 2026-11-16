import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/collaboration_room.dart';
import '../controllers/collaboration_task_controller.dart';
import '../models/task_due_label.dart';
import 'task_editor_sheet.dart';

/// Tab Task của phòng cộng tác: lọc, nhóm theo trạng thái, giao việc, hạn chót.
class CollaborationTasksPanel extends ConsumerStatefulWidget {
  const CollaborationTasksPanel({
    required this.scope,
    this.focusTaskId,
    super.key,
  });

  final CollaborationTaskScope scope;

  /// Mở sẵn việc này (bấm từ thông báo / "Việc của tôi").
  final String? focusTaskId;

  @override
  ConsumerState<CollaborationTasksPanel> createState() =>
      _CollaborationTasksPanelState();
}

class _CollaborationTasksPanelState
    extends ConsumerState<CollaborationTasksPanel> {
  bool _showFinished = true;
  bool _showCancelled = false;
  bool _focusHandled = false;

  @override
  Widget build(BuildContext context) {
    final provider = collaborationTaskControllerProvider(widget.scope);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final now = DateTime.now();
    _openFocusedTaskOnce(state);

    final visible = state.visibleTasks(now);
    final overdueCount = state.tasks.where((t) => t.isOverdueAt(now)).length;
    final sections = <(CollaborationTaskStatus, List<CollaborationTask>)>[
      for (final status in CollaborationTaskStatus.values)
        (status, visible.where((task) => task.taskStatus == status).toList()),
    ];

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        key: const Key('collaboration_tasks_panel'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.md,
          WebTuiSpacing.lg,
          WebTuiSpacing.xl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Việc của phòng', 'Room tasks'),
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                key: const Key('tasks_add'),
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Giao việc', 'Assign task')),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in TaskListFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: WebTuiSpacing.xs),
                    child: ChoiceChip(
                      key: Key('tasks_filter_${filter.name}'),
                      label: Text(
                        filter == TaskListFilter.overdue && overdueCount > 0
                            ? '${filter.label} $overdueCount'
                            : filter.label,
                      ),
                      selected: state.filter == filter,
                      onSelected: (_) => controller.setFilter(filter),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          if (state.isLoading && state.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(WebTuiSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorMessage != null && state.tasks.isEmpty)
            WebTuiErrorState(
              title: tr('Chưa tải được công việc', "Couldn't load tasks"),
              message: state.errorMessage!,
              onRetry: controller.load,
            )
          else if (visible.isEmpty)
            WebTuiEmptyState(
              title: switch (state.filter) {
                TaskListFilter.all => tr(
                  'Phòng chưa có việc nào',
                  'No tasks in this room yet',
                ),
                TaskListFilter.assignedToMe => tr(
                  'Chưa có việc giao cho bạn',
                  'No tasks assigned to you',
                ),
                TaskListFilter.createdByMe => tr(
                  'Bạn chưa giao việc nào',
                  "You haven't assigned any tasks",
                ),
                TaskListFilter.overdue => tr(
                  'Không có việc quá hạn',
                  'No overdue tasks',
                ),
              },
              message: tr(
                'Bấm "Giao việc" để tạo việc, chọn người làm và hạn chót.',
                'Tap "Assign task" to create a task, pick an assignee and a due date.',
              ),
              icon: Icons.task_alt_rounded,
            )
          else
            for (final (status, tasks) in sections)
              if (tasks.isNotEmpty) ...[
                _SectionHeader(
                  status: status,
                  count: tasks.length,
                  collapsed: switch (status) {
                    CollaborationTaskStatus.done => !_showFinished,
                    CollaborationTaskStatus.cancelled => !_showCancelled,
                    _ => false,
                  },
                  onToggle: switch (status) {
                    CollaborationTaskStatus.done => () => setState(
                      () => _showFinished = !_showFinished,
                    ),
                    CollaborationTaskStatus.cancelled => () => setState(
                      () => _showCancelled = !_showCancelled,
                    ),
                    _ => null,
                  },
                ),
                if (!(status == CollaborationTaskStatus.done &&
                        !_showFinished) &&
                    !(status == CollaborationTaskStatus.cancelled &&
                        !_showCancelled))
                  for (final task in tasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                      child: TaskTile(
                        task: task,
                        state: state,
                        now: now,
                        onOpen: () => _openEditor(context, task: task),
                        onStatus: (status) =>
                            _changeStatus(context, task, status),
                      ),
                    ),
              ],
        ],
      ),
    );
  }

  void _openFocusedTaskOnce(CollaborationTaskState state) {
    final focusId = widget.focusTaskId;
    if (_focusHandled || focusId == null || state.isLoading) return;
    _focusHandled = true;
    final task = state.tasks.where((item) => item.id == focusId).firstOrNull;
    if (task == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openEditor(context, task: task));
    });
  }

  Future<void> _openEditor(
    BuildContext context, {
    CollaborationTask? task,
  }) async {
    final message = await showTaskEditorSheet(
      context,
      scope: widget.scope,
      task: task,
    );
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changeStatus(
    BuildContext context,
    CollaborationTask task,
    CollaborationTaskStatus status,
  ) async {
    final error = await ref
        .read(collaborationTaskControllerProvider(widget.scope).notifier)
        .changeStatus(task, status);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.status,
    required this.count,
    required this.collapsed,
    this.onToggle,
  });

  final CollaborationTaskStatus status;
  final int count;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      '${status.label} · $count',
      style: WebTuiTypography.labelSmall.copyWith(
        color: WebTuiColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(
        top: WebTuiSpacing.xs,
        bottom: WebTuiSpacing.xs,
      ),
      child: onToggle == null
          ? label
          : InkWell(
              key: Key('tasks_section_${status.apiValue}'),
              onTap: onToggle,
              borderRadius: BorderRadius.circular(WebTuiRadii.sm),
              child: SizedBox(
                height: 32,
                child: Row(
                  children: [
                    label,
                    Icon(
                      collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      size: 18,
                      color: WebTuiColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Một việc: nút trạng thái, tên, người làm, hạn (đỏ khi quá hạn), menu thao tác.
class TaskTile extends StatelessWidget {
  const TaskTile({
    required this.task,
    required this.state,
    required this.now,
    required this.onOpen,
    required this.onStatus,
    super.key,
  });

  final CollaborationTask task;
  final CollaborationTaskState state;
  final DateTime now;
  final VoidCallback onOpen;
  final ValueChanged<CollaborationTaskStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final status = task.taskStatus;
    final busy = state.busyTaskIds.contains(task.id);
    final canChangeStatus = state.canChangeStatus(task);
    final assignee = state.member(task.assigneeUserId);
    final finished =
        status == CollaborationTaskStatus.done ||
        status == CollaborationTaskStatus.cancelled;
    final urgency = taskDueUrgency(task.dueAt, now, active: task.isActive);
    final dueColor = switch (urgency) {
      TaskDueUrgency.overdue => WebTuiColors.danger,
      TaskDueUrgency.soon => WebTuiColors.accentAmber,
      TaskDueUrgency.none => WebTuiColors.textSecondary,
    };

    return Material(
      key: Key('task_tile_${task.id}'),
      color: WebTuiColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        side: BorderSide(
          color: urgency == TaskDueUrgency.overdue
              ? WebTuiColors.danger.withValues(alpha: 0.45)
              : WebTuiColors.border,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.xs,
            WebTuiSpacing.sm,
            WebTuiSpacing.xs,
            WebTuiSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 44,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        key: Key('task_toggle_${task.id}'),
                        tooltip: status == CollaborationTaskStatus.done
                            ? tr('Mở lại', 'Reopen')
                            : tr('Đánh dấu xong', 'Mark as done'),
                        onPressed: canChangeStatus
                            ? () => onStatus(
                                status == CollaborationTaskStatus.done
                                    ? CollaborationTaskStatus.open
                                    : CollaborationTaskStatus.done,
                              )
                            : null,
                        icon: Icon(
                          switch (status) {
                            CollaborationTaskStatus.open =>
                              Icons.radio_button_unchecked_rounded,
                            CollaborationTaskStatus.inProgress =>
                              Icons.timelapse_rounded,
                            CollaborationTaskStatus.done =>
                              Icons.check_circle_rounded,
                            CollaborationTaskStatus.cancelled =>
                              Icons.cancel_outlined,
                          },
                          color: switch (status) {
                            CollaborationTaskStatus.open =>
                              WebTuiColors.textSecondary,
                            CollaborationTaskStatus.inProgress =>
                              WebTuiColors.accentAmber,
                            CollaborationTaskStatus.done =>
                              WebTuiColors.accentGreen,
                            CollaborationTaskStatus.cancelled =>
                              WebTuiColors.textMuted,
                          },
                        ),
                      ),
              ),
              const SizedBox(width: WebTuiSpacing.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: finished
                              ? WebTuiColors.textMuted
                              : WebTuiColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          decoration: finished
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: WebTuiSpacing.xs),
                      Wrap(
                        spacing: WebTuiSpacing.md,
                        runSpacing: WebTuiSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (assignee == null)
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 16,
                                  color: WebTuiColors.textMuted,
                                )
                              else
                                WebTuiAvatar(
                                  label: assignee.name,
                                  imageUrl: assignee.avatarUrl,
                                  gender: WebTuiAvatarGender.parse(
                                    assignee.gender,
                                  ),
                                  size: 20,
                                ),
                              const SizedBox(width: WebTuiSpacing.xs),
                              Flexible(
                                child: Text(
                                  assignee?.name ??
                                      (task.assigneeUserId == null
                                          ? tr('Chưa giao', 'Unassigned')
                                          : tr(
                                              'Người đã rời phòng',
                                              'Left the room',
                                            )),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.bodySmall.copyWith(
                                    color: WebTuiColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (task.dueAt != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  urgency == TaskDueUrgency.overdue
                                      ? Icons.error_outline_rounded
                                      : Icons.schedule_rounded,
                                  size: 16,
                                  color: dueColor,
                                ),
                                const SizedBox(width: WebTuiSpacing.xxs),
                                Flexible(
                                  child: Text(
                                    urgency == TaskDueUrgency.overdue
                                        ? tr(
                                            'Quá hạn · ${formatTaskDue(task.dueAt!, now)}',
                                            'Overdue · ${formatTaskDue(task.dueAt!, now)}',
                                          )
                                        : formatTaskDue(task.dueAt!, now),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WebTuiTypography.bodySmall.copyWith(
                                      color: dueColor,
                                      fontWeight: urgency == TaskDueUrgency.none
                                          ? FontWeight.w400
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (canChangeStatus)
                PopupMenuButton<CollaborationTaskStatus>(
                  key: Key('task_menu_${task.id}'),
                  tooltip: tr('Đổi trạng thái', 'Change status'),
                  onSelected: onStatus,
                  itemBuilder: (_) => [
                    for (final option in CollaborationTaskStatus.values)
                      if (option != status)
                        PopupMenuItem(
                          value: option,
                          child: Text(switch (option) {
                            CollaborationTaskStatus.open => tr(
                              'Chuyển về Cần làm',
                              'Move to To do',
                            ),
                            CollaborationTaskStatus.inProgress => tr(
                              'Đang làm',
                              'In progress',
                            ),
                            CollaborationTaskStatus.done => tr(
                              'Đánh dấu xong',
                              'Mark as done',
                            ),
                            CollaborationTaskStatus.cancelled => tr(
                              'Huỷ việc',
                              'Cancel task',
                            ),
                          }),
                        ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
