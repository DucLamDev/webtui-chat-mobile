import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../controllers/my_task_display.dart';
import '../controllers/task_status_actions.dart';
import 'my_tasks_card.dart';
import 'work_common.dart';

bool get _dark => WebTuiColors.brightness == Brightness.dark;

/// Màu nền / chữ của ô lọc theo trạng thái (cùng bảng màu thẻ ở tab Công việc).
({Color background, Color foreground}) myTaskStatusColors(
  CollaborationTaskStatus status,
) {
  return switch (status) {
    CollaborationTaskStatus.inProgress => (
      background: WebTuiColors.primarySoft,
      foreground: WebTuiColors.primary,
    ),
    CollaborationTaskStatus.done => (
      background: _dark ? const Color(0xFF14382C) : const Color(0xFFE7F7EE),
      foreground: _dark ? const Color(0xFF4CD49A) : const Color(0xFF16794A),
    ),
    _ => (
      background: _dark ? const Color(0xFF222D3D) : const Color(0xFFF0F2F5),
      foreground: _dark ? const Color(0xFFC3CDDB) : const Color(0xFF4A5565),
    ),
  };
}

/// Ô lọc trạng thái kèm số việc; đang chọn thì viền đậm cùng màu.
class MyTaskFilterTile extends StatelessWidget {
  const MyTaskFilterTile({
    required this.status,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.caption,
    super.key,
  });

  final CollaborationTaskStatus status;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// Dòng nhỏ dưới nhãn ("7 ngày qua").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = myTaskStatusColors(status);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colors.foreground : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.foreground.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 76),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$count',
                      style: WebTuiTypography.titleLarge.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: colors.foreground,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(
                        fontSize: 13,
                        color: colors.foreground,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    if (caption != null)
                      Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodySmall.copyWith(
                          fontSize: 11,
                          color: colors.foreground.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề nhóm việc ("Quá hạn" tô đỏ) kèm số việc.
class MyTaskSectionHeader extends StatelessWidget {
  const MyTaskSectionHeader({required this.section, super.key});

  final TaskSection section;

  @override
  Widget build(BuildContext context) {
    final color = section.overdue
        ? (_dark ? const Color(0xFFF07A7A) : const Color(0xFFC62828))
        : WebTuiColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          if (section.overdue) ...[
            Icon(WebTuiIcons.overdue, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Semantics(
            header: true,
            child: Text(
              section.title,
              style: WebTuiTypography.bodyMedium.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${section.tasks.length}',
            style: WebTuiTypography.bodySmall.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WebTuiColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Khối trắng bo 18 chứa các thẻ việc, đường kẻ mảnh thụt vào sau ô trạng thái.
class MyTaskSectionCard extends StatelessWidget {
  const MyTaskSectionCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E3A64).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 60,
                      color: WebTuiColors.border.withValues(alpha: 0.7),
                    ),
                  children[index],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

({Color background, Color foreground}) _dueColors(TaskDueTone tone) {
  return switch (tone) {
    TaskDueTone.overdue => (
      background: _dark ? const Color(0xFF3A1A1E) : const Color(0xFFFDECEC),
      foreground: _dark ? const Color(0xFFF07A7A) : const Color(0xFFC62828),
    ),
    TaskDueTone.soon => (
      background: _dark ? const Color(0xFF3A2D12) : const Color(0xFFFFF4DD),
      foreground: _dark ? const Color(0xFFEDB04A) : const Color(0xFF8A5300),
    ),
    TaskDueTone.done => myTaskStatusColors(CollaborationTaskStatus.done),
    TaskDueTone.normal => myTaskStatusColors(CollaborationTaskStatus.open),
  };
}

/// Thẻ một việc: ô trạng thái (bấm để nhận / hoàn thành, có Hoàn tác), tên
/// việc tối đa 2 dòng, nhãn hạn màu và tên nhóm; bấm thẻ mở việc trong nhóm.
class MyTaskListTile extends ConsumerWidget {
  const MyTaskListTile({
    required this.task,
    required this.now,
    required this.onChanged,
    super.key,
  });

  final CollaborationTask task;
  final DateTime now;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = task.taskStatus;
    final due = taskDueLabel(task, now);
    final channel = task.channelName?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: TaskStatusBox(status: status)),
              ),
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            key: Key('task_row_${task.id}'),
            onTap: () => context.push(assignedTaskLocation(task)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: status == CollaborationTaskStatus.done
                          ? WebTuiColors.textSecondary
                          : WebTuiColors.textPrimary,
                      decoration: status == CollaborationTaskStatus.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (due != null)
                        _DueChip(label: due.label, tone: due.tone),
                      if (channel != null && channel.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              WebTuiIcons.channel,
                              size: 13,
                              color: WebTuiColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                channel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.bodySmall.copyWith(
                                  fontSize: 12.5,
                                  color: WebTuiColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (due == null && (channel == null || channel.isEmpty))
                        Text(
                          tr('Không có hạn', 'No due date'),
                          style: WebTuiTypography.bodySmall.copyWith(
                            fontSize: 12.5,
                            color: WebTuiColors.textSecondary,
                          ),
                        ),
                    ],
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

class _DueChip extends StatelessWidget {
  const _DueChip({required this.label, required this.tone});

  final String label;
  final TaskDueTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _dueColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: WebTuiTypography.bodySmall.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors.foreground,
        ),
      ),
    );
  }
}

/// Trạng thái trống: biểu tượng tròn lớn, tiêu đề, lời gợi ý.
class MyTasksEmptyState extends StatelessWidget {
  const MyTasksEmptyState({
    required this.title,
    required this.message,
    this.icon,
    super.key,
  });

  final String title;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: WebTuiColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? WebTuiIcons.tasks,
                size: 34,
                color: WebTuiColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleMedium.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WebTuiColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodyMedium.copyWith(
                fontSize: 14,
                height: 1.45,
                color: WebTuiColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khung xương lúc tải: 3 ô lọc + 2 khối thẻ việc.
class MyTasksSkeleton extends StatelessWidget {
  const MyTasksSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 22, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkSkeleton(height: 14, width: 80, radius: 6),
          SizedBox(height: 12),
          WorkSkeleton(height: 72, radius: 18),
          SizedBox(height: 10),
          WorkSkeleton(height: 72, radius: 18),
          SizedBox(height: 22),
          WorkSkeleton(height: 14, width: 110, radius: 6),
          SizedBox(height: 12),
          WorkSkeleton(height: 72, radius: 18),
        ],
      ),
    );
  }
}
