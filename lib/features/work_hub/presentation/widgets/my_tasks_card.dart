import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_seamless.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../controllers/task_status_actions.dart';
import '../controllers/work_hub_providers.dart';
import 'work_common.dart';

Color get _greenTile => WebTuiColors.brightness == Brightness.dark
    ? const Color(0xFF14382C)
    : const Color(0xFFE7F7EE);
const _greenTileText = Color(0xFF1E9E5A);

/// Địa chỉ mở một việc trong kênh của nó (bảng việc của kênh).
String assignedTaskLocation(CollaborationTask task) {
  return Uri(
    path: '/conversations/${Uri.encodeComponent(task.channelId)}',
    queryParameters: {
      'workspaceId': task.workspaceId,
      'title': task.channelName ?? tr('Hội thoại', 'Conversation'),
      'tool': 'tasks',
      'taskId': task.id,
    },
  ).toString();
}

/// Phụ đề một việc: "tên kênh · Hạn dd/MM".
String assignedTaskSubtitle(CollaborationTask task) {
  final channel = task.channelName?.trim();
  final parts = <String>[
    if (channel != null && channel.isNotEmpty) channel,
    if (task.dueAt != null)
      tr(
        'Hạn ${workShortDate(task.dueAt!)}',
        'Due ${workShortDate(task.dueAt!)}',
      ),
  ];
  return parts.isEmpty ? tr('Không có hạn', 'No due date') : parts.join(' · ');
}

/// Phụ đề một việc ở tab Công việc: "Hạn dd/MM, HH:mm – tên kênh" (hạn không
/// có giờ thì bỏ giờ; không hạn thì chỉ tên kênh).
String workTabTaskSubtitle(CollaborationTask task) {
  final channel = task.channelName?.trim();
  final due = task.dueAt?.toLocal();
  final parts = <String>[
    if (due != null)
      tr(
        'Hạn ${workShortDate(due)}${_dueClock(due)}',
        'Due ${workShortDate(due)}${_dueClock(due)}',
      ),
    if (channel != null && channel.isNotEmpty) channel,
  ];
  return parts.isEmpty ? tr('Không có hạn', 'No due date') : parts.join(' – ');
}

String _dueClock(DateTime local) {
  if (local.hour == 0 && local.minute == 0) return '';
  return ', ${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Màu số "Hoàn thành": xanh lá đậm đủ tương phản trên nền trang.
Color get _doneCountColor => WebTuiColors.brightness == Brightness.dark
    ? const Color(0xFF3CCF89)
    : const Color(0xFF178A4C);

/// Số việc gần hạn hiện ở tab Công việc (danh sách đủ ở "Xem tất cả").
const myTasksPreviewLimit = 2;

/// Nhóm "Việc của tôi" ở tab Công việc: tiêu đề nhóm + "Xem tất cả", 3 cột số
/// liệu (không ô nền, ngăn bằng kẻ dọc mảnh) và tối đa [myTasksPreviewLimit]
/// việc gần hạn dạng dòng liền mạch.
class MyTasksCard extends ConsumerWidget {
  const MyTasksCard({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(myTasksOverviewProvider(workspaceId));
    return Column(
      key: const Key('my_tasks_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebTuiGroupHeader(
          title: tr('Việc của tôi', 'My tasks'),
          actionLabel: tr('Xem tất cả', 'See all'),
          actionKey: const Key('my_tasks_see_all'),
          onAction: () => context.push(
            Uri(
              path: '/my-tasks',
              queryParameters: {'workspaceId': workspaceId},
            ).toString(),
          ),
        ),
        overview.when(
          loading: () => const _TasksLoading(),
          error: (error, _) => WorkSeamlessError(
            message: workHubErrorText(error),
            onRetry: () => ref.invalidate(myTasksOverviewProvider),
          ),
          data: (data) => _TasksLoaded(
            overview: data,
            onChanged: () => ref.invalidate(myTasksOverviewProvider),
          ),
        ),
      ],
    );
  }
}

class _TasksLoading extends StatelessWidget {
  const _TasksLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('my_tasks_loading'),
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: WorkSkeleton(height: 48)),
              SizedBox(width: 16),
              Expanded(child: WorkSkeleton(height: 48)),
              SizedBox(width: 16),
              Expanded(child: WorkSkeleton(height: 48)),
            ],
          ),
          SizedBox(height: 18),
          WorkSkeleton(height: 36),
          SizedBox(height: 14),
          WorkSkeleton(height: 36),
        ],
      ),
    );
  }
}

class _TasksLoaded extends StatelessWidget {
  const _TasksLoaded({required this.overview, required this.onChanged});

  final MyTasksOverview overview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final summary = overview.summary;
    final empty =
        summary.open + summary.inProgress + summary.doneLast7Days == 0;
    final tasks = overview.upcoming.take(myTasksPreviewLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CountColumn(
                    key: const Key('count_open'),
                    count: summary.open,
                    label: tr('Chưa nhận', 'Unclaimed'),
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                const _CountDivider(),
                Expanded(
                  child: _CountColumn(
                    key: const Key('count_in_progress'),
                    count: summary.inProgress,
                    label: tr('Đã nhận', 'Claimed'),
                    color: WebTuiColors.primary,
                  ),
                ),
                const _CountDivider(),
                Expanded(
                  child: _CountColumn(
                    key: const Key('count_done'),
                    count: summary.doneLast7Days,
                    label: tr('Hoàn thành', 'Done'),
                    color: _doneCountColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (tasks.isEmpty)
          WorkSeamlessNote(
            key: const Key('my_tasks_empty'),
            message: empty
                ? tr(
                    'Chưa có việc nào được giao cho bạn',
                    'No tasks assigned to you yet',
                  )
                : tr('Không còn việc nào chưa xong', 'No unfinished tasks'),
          )
        else
          for (var i = 0; i < tasks.length; i++)
            _WorkTabTaskRow(
              task: tasks[i],
              divider: i < tasks.length - 1,
              onChanged: onChanged,
            ),
      ],
    );
  }
}

class _CountColumn extends StatelessWidget {
  const _CountColumn({
    required this.count,
    required this.label,
    required this.color,
    super.key,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: WebTuiTypography.titleLarge.copyWith(
            fontSize: 26,
            height: 1.2,
            letterSpacing: -0.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.bodySmall.copyWith(
            fontSize: 13,
            color: WebTuiColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _CountDivider extends StatelessWidget {
  const _CountDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 0.5,
      child: ColoredBox(color: WebTuiColors.hairline),
    );
  }
}

/// Một việc ở tab Công việc: biểu tượng việc (bấm để nhận / hoàn thành như ô
/// trạng thái), tiêu đề, "Hạn … – nhóm", mũi tên; bấm dòng mở việc trong kênh.
class _WorkTabTaskRow extends ConsumerWidget {
  const _WorkTabTaskRow({
    required this.task,
    required this.divider,
    required this.onChanged,
  });

  final CollaborationTask task;
  final bool divider;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = task.taskStatus;
    final canAdvance = nextAssignedTaskStatus(status) != null;
    return WorkSeamlessRow(
      key: Key('task_row_${task.id}'),
      divider: divider,
      title: task.title,
      subtitle: workTabTaskSubtitle(task),
      onTap: () => context.push(assignedTaskLocation(task)),
      leadingStart: 6,
      leadingWidth: 44,
      leadingGap: 4,
      leading: Semantics(
        button: canAdvance,
        label: switch (status) {
          CollaborationTaskStatus.open => tr(
            'Nhận việc ${task.title}',
            'Claim task ${task.title}',
          ),
          CollaborationTaskStatus.inProgress => tr(
            'Hoàn thành việc ${task.title}',
            'Complete task ${task.title}',
          ),
          _ => tr('Việc ${task.title}', 'Task ${task.title}'),
        },
        excludeSemantics: true,
        // Vùng bấm 44 × 52 quanh biểu tượng 24.
        child: InkResponse(
          key: Key('task_box_${task.id}'),
          radius: 22,
          onTap: canAdvance
              ? () => advanceAssignedTask(
                  context,
                  ref,
                  task,
                  onChanged: onChanged,
                )
              : null,
          child: SizedBox(
            width: 44,
            height: 52,
            child: Center(
              child: Icon(
                WebTuiDuotoneIcons.tasks.primary,
                size: 24,
                color: status == CollaborationTaskStatus.inProgress
                    ? WebTuiColors.primary
                    : WebTuiColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Một việc: ô vuông đổi trạng thái + tên đậm + "tên kênh · Hạn dd/MM".
class AssignedTaskRow extends ConsumerWidget {
  const AssignedTaskRow({
    required this.task,
    required this.onChanged,
    this.showBox = true,
    super.key,
  });

  final CollaborationTask task;
  final VoidCallback onChanged;
  final bool showBox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = task.taskStatus;
    return Row(
      children: [
        if (showBox)
          Semantics(
            button: true,
            label: switch (status) {
              CollaborationTaskStatus.open => tr(
                'Nhận việc ${task.title}',
                'Claim task ${task.title}',
              ),
              CollaborationTaskStatus.inProgress => tr(
                'Hoàn thành việc ${task.title}',
                'Complete task ${task.title}',
              ),
              _ => tr('Việc ${task.title}', 'Task ${task.title}'),
            },
            child: InkWell(
              key: Key('task_box_${task.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: nextAssignedTaskStatus(status) == null
                  ? null
                  : () => advanceAssignedTask(
                      context,
                      ref,
                      task,
                      onChanged: onChanged,
                    ),
              child: SizedBox(
                width: 48,
                height: 56,
                child: Center(child: TaskStatusBox(status: status)),
              ),
            ),
          ),
        Expanded(
          child: InkWell(
            key: Key('task_row_${task.id}'),
            onTap: () => context.push(assignedTaskLocation(task)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(showBox ? 4 : 0, 10, 0, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: WebTuiColors.textPrimary,
                      decoration: status == CollaborationTaskStatus.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    assignedTaskSubtitle(task),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ô vuông trạng thái: chưa nhận = ô trống viền xám; đã nhận = nền xanh nhạt +
/// tích xanh; xong = nền xanh lá + tích.
class TaskStatusBox extends StatelessWidget {
  const TaskStatusBox({required this.status, super.key});

  final CollaborationTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, border, check) = switch (status) {
      CollaborationTaskStatus.inProgress => (
        WebTuiColors.primarySoft,
        Colors.transparent,
        WebTuiColors.primary,
      ),
      CollaborationTaskStatus.done => (
        _greenTile,
        Colors.transparent,
        _greenTileText,
      ),
      _ => (WebTuiColors.surface, const Color(0xFFB8C0CC), null),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border, width: 2),
      ),
      child: check == null
          ? null
          : Icon(WebTuiIcons.taskDone, size: 20, color: check),
    );
  }
}
