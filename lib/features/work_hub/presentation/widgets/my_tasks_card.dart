import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../controllers/task_status_actions.dart';
import '../controllers/work_hub_providers.dart';
import 'work_common.dart';

const _grayTile = Color(0xFFF0F2F5);
const _grayTileText = Color(0xFF5B6675);
const _greenTile = Color(0xFFE7F7EE);
const _greenTileText = Color(0xFF1E9E5A);

/// Địa chỉ mở một việc trong kênh của nó (bảng việc của kênh).
String assignedTaskLocation(CollaborationTask task) {
  return Uri(
    path: '/conversations/${Uri.encodeComponent(task.channelId)}',
    queryParameters: {
      'workspaceId': task.workspaceId,
      'title': task.channelName ?? 'Hội thoại',
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
    if (task.dueAt != null) 'Hạn ${workShortDate(task.dueAt!)}',
  ];
  return parts.isEmpty ? 'Không có hạn' : parts.join(' · ');
}

/// Thẻ "Việc của tôi" ở tab Công việc.
class MyTasksCard extends ConsumerWidget {
  const MyTasksCard({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(myTasksOverviewProvider(workspaceId));
    return WorkCard(
      key: const Key('my_tasks_card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WorkIconBox(icon: WebTuiIcons.tasks, size: 52, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Việc của tôi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.titleLarge.copyWith(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: WebTuiColors.textPrimary,
                            ),
                          ),
                        ),
                        InkWell(
                          key: const Key('my_tasks_see_all'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => context.push(
                            Uri(
                              path: '/my-tasks',
                              queryParameters: {'workspaceId': workspaceId},
                            ).toString(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Text(
                              'Xem tất cả',
                              style: WebTuiTypography.bodyMedium.copyWith(
                                color: WebTuiColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        // Kính lúp nhỏ cạnh "Xem tất cả": mở Việc của tôi ở
                        // chế độ tìm (vùng bấm 44).
                        IconButton(
                          key: const Key('work_search'),
                          tooltip: 'Tìm việc của tôi',
                          iconSize: 22,
                          color: WebTuiColors.textSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          icon: const Icon(WebTuiIcons.search),
                          onPressed: () => context.push(
                            Uri(
                              path: '/my-tasks',
                              queryParameters: {
                                'workspaceId': workspaceId,
                                'search': '1',
                              },
                            ).toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tự gom từ bảng việc trong các cuộc trò chuyện',
                      style: WebTuiTypography.bodySmall.copyWith(
                        fontSize: 12.5,
                        color: WebTuiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          overview.when(
            loading: () => const _TasksLoading(),
            error: (error, _) => WorkErrorBox(
              message: workHubErrorText(error),
              onRetry: () => ref.invalidate(myTasksOverviewProvider),
            ),
            data: (data) => _TasksLoaded(
              workspaceId: workspaceId,
              overview: data,
              onChanged: () => ref.invalidate(myTasksOverviewProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _TasksLoading extends StatelessWidget {
  const _TasksLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('my_tasks_loading'),
      children: [
        Row(
          children: [
            Expanded(child: WorkSkeleton(height: 66, radius: 16)),
            SizedBox(width: 10),
            Expanded(child: WorkSkeleton(height: 66, radius: 16)),
            SizedBox(width: 10),
            Expanded(child: WorkSkeleton(height: 66, radius: 16)),
          ],
        ),
        SizedBox(height: 14),
        WorkSkeleton(height: 40),
        SizedBox(height: 12),
        WorkSkeleton(height: 40),
        SizedBox(height: 12),
      ],
    );
  }
}

class _TasksLoaded extends StatelessWidget {
  const _TasksLoaded({
    required this.workspaceId,
    required this.overview,
    required this.onChanged,
  });

  final String workspaceId;
  final MyTasksOverview overview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final summary = overview.summary;
    final empty =
        summary.open + summary.inProgress + summary.doneLast7Days == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _CountTile(
                key: const Key('count_open'),
                count: summary.open,
                label: 'Chưa nhận',
                background: _grayTile,
                foreground: _grayTileText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CountTile(
                key: const Key('count_in_progress'),
                count: summary.inProgress,
                label: 'Đã nhận',
                background: WebTuiColors.primarySoft,
                foreground: WebTuiColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CountTile(
                key: const Key('count_done'),
                count: summary.doneLast7Days,
                label: 'Hoàn thành',
                background: _greenTile,
                foreground: _greenTileText,
              ),
            ),
          ],
        ),
        if (overview.upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              empty
                  ? 'Chưa có việc nào được giao cho bạn'
                  : 'Không còn việc nào chưa xong',
              key: const Key('my_tasks_empty'),
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
                for (var i = 0; i < overview.upcoming.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 52,
                      color: WebTuiColors.border.withValues(alpha: 0.7),
                    ),
                  AssignedTaskRow(
                    task: overview.upcoming[i],
                    onChanged: onChanged,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.count,
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final int count;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: WebTuiTypography.titleLarge.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: foreground,
              height: 1.1,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            style: WebTuiTypography.bodySmall.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
              CollaborationTaskStatus.open => 'Nhận việc ${task.title}',
              CollaborationTaskStatus.inProgress =>
                'Hoàn thành việc ${task.title}',
              _ => 'Việc ${task.title}',
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
